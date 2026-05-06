# testing-infra — `pve1-testing1`

Terraform provisions a single-node **k3s** VM on **Proxmox** (`pve1`). Helm values live under `gitops/` for **Headlamp** and **Infisical** (GitOps-friendly layout; Argo CD is out of scope for phase 1).

## Prerequisites

- **Proxmox**: API token whose role can use VM + **Datastore** on the snippet storage (see **Troubleshooting**); **Snippets** enabled on that datastore (often **`local`**). Guest disks stay on **`nvme-thin`** in Terraform; snippets cannot use thin pools — directory-backed storage only.
- **Ubuntu cloud template**: Noble **24.04** cloud-init template VM you clone from (set `template_vm_id`).
- **SSH to Proxmox node**: Snippet uploads use **SSH public-key auth** as **`root`** (API tokens do not supply a password). Install your laptop’s pubkey in **`/root/.ssh/authorized_keys`** on `pve1`, then set **`PROXMOX_VE_SSH_PRIVATE_KEY`** or **`PVE1_SSH_PRIVATE_KEY_FILE`** (see below).
- **Repo root**: `.env` (see `.env.example`) and `id_ed25519.pub` for the `ubuntu` user on the guest.

### Credentials

Never commit `.env`. Variables consumed by the helper script:

| `.env` | Maps to |
|--------|---------|
| `PVE1_URL` | `PROXMOX_VE_ENDPOINT` (normalized with trailing `/`) |
| `PVE1_TOKEN_ID` + `PVE1_SECRET` | `PROXMOX_VE_API_TOKEN` as `TOKEN_ID=SECRET` |
| `PVE1_SSH_PRIVATE_KEY_FILE` | If set and `PROXMOX_VE_SSH_PRIVATE_KEY` is unset, the script reads that PEM path into `PROXMOX_VE_SSH_PRIVATE_KEY` |

**SSH auth for snippet uploads:** With an API token, the provider never uses your interactive root password. **`root@10.0.0.201`** must accept the **same** key Terraform sends:

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@10.0.0.201
ssh -o PreferredAuthentications=publickey -o PasswordAuthentication=no root@10.0.0.201   # should succeed without password
```

Then either:

```bash
export PROXMOX_VE_SSH_PRIVATE_KEY="$(cat ~/.ssh/id_ed25519)"
```

or add `PVE1_SSH_PRIVATE_KEY_FILE=~/.ssh/id_ed25519` to `.env` (recommended).

Optional: use **`ssh-add ~/.ssh/id_ed25519`** and **`export PROXMOX_VE_SSH_AGENT=true`** instead of embedding the PEM (provider prefers the agent when enabled).

Optional: `export PROXMOX_VE_INSECURE=false` when using valid TLS on Proxmox.

### Locked lab inputs (this environment)

| Setting | Value |
|---------|--------|
| Guest VM ID | `701` |
| Node | `pve1` |
| Bridge | `vmbr0` |
| Disk storage | `nvme-thin`, ~60 GiB |
| CPU / RAM | 2 vCPU / 4096 MiB (EC2 **t3a.medium** class) |
| IPv4 | `10.0.0.205/24`, gw `10.0.0.1`, DNS Quad9 + Google |

Override defaults via `terraform.tfvars` (gitignored); copy `environments/pve1-testing1/terraform/terraform.tfvars.example`.

## One-time: Ubuntu cloud template on Proxmox

Import [Ubuntu Noble cloud image](https://cloud-images.ubuntu.com/noble/current/) per Proxmox docs, add Cloud‑Init drive + QEMU agent via cloud-init, convert to **template**, note its **VM ID** → `template_vm_id`.

## Terraform

```bash
chmod +x scripts/with-proxmox-env.sh
# Install pubkey on Proxmox root (once): ssh-copy-id -i ~/.ssh/id_ed25519.pub root@10.0.0.201
# Put PVE1_SSH_PRIVATE_KEY_FILE=~/.ssh/id_ed25519 in .env OR export PROXMOX_VE_SSH_PRIVATE_KEY="$(cat ~/.ssh/id_ed25519)"
make terraform-init
make terraform-plan   # requires terraform.tfvars or TF_VAR_template_vm_id
make terraform-apply       # type yes when prompted
# or: make terraform-apply-auto
```

If you previously applied with the wrong **`disk_interface`** (extra empty **virtio** disk + tiny **scsi** root), pull the latest Terraform defaults or set **`disk_interface = "scsi0"`**, then destroy and recreate the VM:

```bash
make terraform-destroy    # removes VM 701 (and Proxmox disks attached to it); confirms before apply
make terraform-apply-auto
```

Retrieve kubeconfig (after cloud‑init finishes):

```bash
scp ubuntu@10.0.0.205:/home/ubuntu/.kube/config ./kubeconfig.pve1-testing1
kubectl --kubeconfig kubeconfig.pve1-testing1 get nodes
```

## Helm (Headlamp + Infisical)

Requires **Helm 3** and **kubectl** on the machine where you run `make` (not on the cluster node). macOS: `brew install helm kubectl`.

Uses bundled **Traefik** on k3s; chart overrides set `ingressClassName: traefik`.

```bash
export KUBECONFIG="$(pwd)/kubeconfig.pve1-testing1"
make helm-headlamp
```

**Infisical** does not create `infisical-secrets` for you. Until it exists, app pods stay **`0/1`** (readiness checks `/api/status`). With **bundled** Postgres/Redis from this chart, you only need the core keys (the chart sets `DB_CONNECTION_URI` and `REDIS_URL` on the Deployment itself):

```bash
export KUBECONFIG="$(pwd)/kubeconfig.pve1-testing1"
kubectl create secret generic infisical-secrets \
  --namespace infisical \
  --from-literal=AUTH_SECRET="$(openssl rand -base64 32)" \
  --from-literal=ENCRYPTION_KEY="$(openssl rand -hex 16)" \
  --from-literal=SITE_URL="http://infisical.pve1-testing1.local"
```

(`SITE_URL` should match how you open the UI—in `/etc/hosts` setups that is usually `http://infisical.pve1-testing1.local`. For local port-forward testing only, `http://localhost` is fine.)

Then install or reconcile Helm (chart name is **`infisical/infisical-standalone`**):

```bash
make helm-infisical
```

**Port-forward** targets the chart-generated Service name (there is no `svc/infisical`):

```bash
kubectl port-forward -n infisical svc/infisical-infisical-standalone-infisical 8080:8080
curl -sS http://localhost:8080/api/status
```

If the Ingress still shows the wrong host/class (`kubectl get ingress -n infisical`), re-run `make helm-infisical` so `gitops/environments/pve1-testing1/infisical-values.yaml` is applied (`ingress.hostName`, `ingress.ingressClassName: traefik`, `ingress.nginx.enabled: false`). Traffic with `Host: infisical.pve1-testing1.local` must match that Ingress rule or you will see **`404`** from the wrong ingress/controller.

See [Infisical — Kubernetes (Helm)](https://infisical.com/docs/self-hosting/deployment-options/kubernetes-helm) for external Postgres/Redis (extra keys on the same secret).

Add hostnames (or route DNS) for:

- `headlamp.pve1-testing1.local`
- `infisical.pve1-testing1.local`

Point them at Traefik (typically the worker node IP `10.0.0.205`, or use `/etc/hosts`).

### Infisical → Kubernetes (Secrets Operator)

The Helm chart above **does not** sync Infisical into workload Secrets by itself. To mirror Infisical secrets into native **`Secret`** objects (pods consume them via `envFrom` / volumes), install Infisical’s **[Kubernetes operator](https://infisical.com/docs/integrations/platforms/kubernetes)**:

```bash
export KUBECONFIG="$(pwd)/kubeconfig.pve1-testing1"
make helm-infisical-operator
```

Values live in `gitops/environments/pve1-testing1/infisical-operator-values.yaml`. They point **`hostAPI`** at the in-cluster Infisical Service (**HTTP**, port **8080**):

`http://infisical-infisical-standalone-infisical.infisical.svc.cluster.local:8080/api`

**Authentication choice for this repo:** **Universal Auth** (machine identity client ID + secret in a Kubernetes Secret). It avoids extra TokenReview/RBAC wiring; **[Kubernetes Auth](https://infisical.com/docs/integrations/platforms/kubernetes/infisical-secret-crd)** is available if you prefer bound SA tokens later.

1. In the Infisical UI, create a **Machine Identity** with **Universal Auth**, attach it to the **project** you want synced, and grant permission to **read** secrets for the target environment (for example **`dev`**).

2. Create credentials once (replace placeholders):

```bash
kubectl create secret generic infisical-operator-machine-identity \
  --namespace infisical-system \
  --from-literal=clientId="YOUR_CLIENT_ID" \
  --from-literal=clientSecret="YOUR_CLIENT_SECRET"
```

3. Edit `gitops/environments/pve1-testing1/infisical-secret-demo.yaml`: set **`projectSlug`** and **`envSlug`** to the **slugs** from Infisical (usually lowercase with hyphens, e.g. `kube-vault-1` / `production` — not display titles like `Kube-Vault-1` / `Production`, which the API rejects).

4. Apply the **`InfisicalSecret`** CR (adjust paths/commits however you track GitOps):

```bash
kubectl apply -f gitops/environments/pve1-testing1/infisical-secret-demo.yaml
```

The operator creates **`demo-infisical-managed-secret`** in **`default`**. Inspect sync status:

```bash
kubectl get infisicalsecret -A
kubectl describe infisicalsecret demo-infisical-sync -n default
kubectl get secret demo-infisical-managed-secret -n default -o yaml
```

Reference: **[InfisicalSecret CRD](https://infisical.com/docs/integrations/platforms/kubernetes/infisical-secret-crd)**.

## Layout

- `environments/pve1-testing1/terraform/` — Proxmox VM + cloud-init snippets  
- `environments/pve1-testing1/bootstrap/cloud-init/` — cloud-init templates  
- `gitops/environments/pve1-testing1/` — Helm values for optional installs (including Infisical operator + demo CR)  
- `scripts/with-proxmox-env.sh` — `.env` → provider env vars  

## Troubleshooting

### `Permission check failed (/storage/local, Datastore.Audit|Datastore.AllocateSpace)` (HTTP 403)

Terraform uploads cloud-init YAML to a storage that supports **Snippets** (`snippets_datastore_id`, default **`local`**). Your API token’s **role** must be allowed to allocate/list on that storage.

1. In Proxmox: **Datacenter → Permissions** — edit the **role** attached to your token (or add an ACL).
2. Ensure the role includes **`Datastore.AllocateSpace`** and **`Datastore.Audit`** on path **`/storage/local`** (or whatever storage ID you set in `snippets_datastore_id`).
3. Alternatively, enable **Snippets** on another directory-backed store your token can already use, then set `snippets_datastore_id` in `terraform.tfvars` to that ID.

After fixing permissions, run `make terraform-apply` again.

### `local` does not support content type "snippets"

Terraform uses **`snippets_datastore_id`** (default **`local`**) for cloud-init uploads. That datastore must list **Snippets** among allowed content types.

In Proxmox: **Datacenter → Storage → `local` → Edit → Content** and enable **Snippets** (directory-backed stores only). If your `local` pool cannot host snippets, add or pick another directory storage with Snippets enabled and set `snippets_datastore_id` in `terraform.tfvars`.

### `unable to authenticate user "root" over SSH` / `attempted methods [none password]`

Snippet uploads connect as **`root`** via SSH. **Interactive password login from your laptop does not help Terraform** — with an API token the provider does not use `PROXMOX_VE_PASSWORD`; unless you set **`PROXMOX_VE_SSH_PASSWORD`** (discouraged), only **public-key** auth applies.

1. Install your laptop’s **public** key on Proxmox:  
   `ssh-copy-id -i ~/.ssh/id_ed25519.pub root@10.0.0.201`
2. Confirm key-only login:  
   `ssh -o PreferredAuthentications=publickey -o PasswordAuthentication=no root@10.0.0.201`
3. Give Terraform the matching **private** key: **`PVE1_SSH_PRIVATE_KEY_FILE=~/.ssh/id_ed25519`** in `.env`, or  
   `export PROXMOX_VE_SSH_PRIVATE_KEY="$(cat ~/.ssh/id_ed25519)"`  
   Or use **`ssh-add ~/.ssh/id_ed25519`** and **`export PROXMOX_VE_SSH_AGENT=true`**.

### `failed to read .../.ssh/known_hosts ... missing host pattern`

The provider parses **`~/.ssh/known_hosts`** with Go’s SSH libraries; **invalid lines break Terraform before any connection attempt**.

1. Open the file and inspect the reported **line number** (often **line 2**): remove stray blanks, partial lines, or directives OpenSSH accepts but the parser rejects (historically some **`@cert-authority`** / `@revoked` edge cases).
2. Back up and clean up: `cp ~/.ssh/known_hosts ~/.ssh/known_hosts.bak` then delete the offending line(s).  
   **If you removed `known_hosts` entirely**, Terraform’s SSH stack won’t prompt to trust the host key — prime the file before `terraform apply`:
   - Non-interactive: `ssh-keyscan -t rsa,ecdsa,ed25519 -H <PROXMOX_IP> >> ~/.ssh/known_hosts && chmod 600 ~/.ssh/known_hosts`
   - Or run `ssh root@<PROXMOX_IP>` once and accept the host key (OpenSSH writes valid entries).
3. Optional: set **`proxmox_ssh_host`** in `terraform.tfvars` to your node IP (same host as in `PVE1_URL`) so SSH targets the expected interface.

Then run `make terraform-apply` again.

### k3s fails with `no space left on device` (root tiny but another disk is large)

Run **`lsblk`** and check **which disk holds `/`** (`findmnt -n -o SOURCE /`).

**Typical mismatch:** Root is on **`/dev/sda1`** (~few GiB) while **`/dev/vda`** shows **60 GiB empty**. That means Terraform resized **`virtio0`** but your template boots from **`scsi0`** — Terraform added a **second** disk instead of growing the OS disk.

**Fix right now**

1. **Proxmox → VM → Hardware:** enlarge the **same disk** the guest uses as **`sda`** (often **SCSI**) to your target size (e.g. 60 GiB). Optionally remove the unused extra **VirtIO** disk later once root is healthy.
2. Inside the guest (partition **`1`** holds `/` in your `lsblk`; **`growpart` needs a number**, not a letter):

```bash
sudo growpart /dev/sda 1
sudo resize2fs /dev/sda1
df -h /
sudo systemctl stop k3s
sudo rm -rf /var/lib/rancher/k3s/data/
sudo systemctl start k3s
```

If **`growpart`** reports **NOCHANGE**, the **hypervisor disk backing `sda` is still small** — enlarge that disk in Proxmox first (or reboot after resize).

**Prevent on future applies:** set **`disk_interface`** to match the template (often **`scsi0`** for Ubuntu cloud templates on Proxmox). Example in `terraform.tfvars`:

```hcl
disk_interface = "scsi0"
disk_size_gb   = 60
```

Then **`terraform apply`** so the OS disk slot is the one resized (review plan for disk changes).

**Fresh clones** from this repo: cloud-init runs **`resize_rootfs` / `growpart`** on `/`, installs **`cloud-guest-utils`**, and skips **`package_upgrade`** during bootstrap so k3s has room once the **correct** disk is large enough.

### `helm: No such file or directory` / `make helm-repos` fails

Install **Helm 3** on your workstation (the Makefile runs `helm` locally against the cluster API). macOS: **`brew install helm`**. See [Helm install docs](https://helm.sh/docs/intro/install/).

### Infisical operator: `Folder with path '/' ... was not found`

You usually see this when **`envSlug`** does not match any environment **slug** in that project (easy to confuse with the display name **Production**), or when nothing exists yet under that environment.

1. In Infisical open **your project** → **Environments** (or the env switcher). Copy each environment’s **slug** (often `development`, `staging`, `production`, or shortened forms like `prod`). Put **exactly that string** in `infisical-secret-demo.yaml` as **`envSlug`** — try **`prod`** if **`production`** fails (and vice versa).
2. Select that environment in the UI and confirm you can see secrets under **/** (root). Create **any test secret** at root if the folder tree looks empty (some setups behave oddly until data exists).
3. Under **Access Control** for your machine identity, confirm it can read secrets for **that same environment**, not only another env (e.g. **Development** only).
4. Optional on the **`InfisicalSecret`**: set **`secretsScope.recursive: true`** if secrets live only under a subfolder.

Then **`kubectl apply -f gitops/environments/pve1-testing1/infisical-secret-demo.yaml`** again and **`kubectl describe infisicalsecret demo-infisical-sync -n default`**.

## Caveats

- **Sizing**: 2 vCPU / 4 GiB matches Infisical “minimum” but is tight with **k3s + Postgres + Redis + Headlamp**. Increase resources if pods pend/OOM.
- **Snippets**: Datacenter → Storage must enable **Snippets** on `snippets_datastore_id`. HTTP **403** on upload almost always means missing **Datastore** privileges on that storage for the token — see **Troubleshooting**.
- **Disk**: Terraform resizes the **`disk_interface`** slot (`virtio0` vs `scsi0`). If it does not match your template’s OS disk, you get a **second empty large disk** and root stays small — see **Troubleshooting**.

## Phase 2

GitOps with **Argo CD** can consume the same `gitops/` values paths once the cluster baseline works.
