# Homelab

Kubernetes homelab running on Proxmox, provisioned with Terraform + Ansible.

## Server Inventory

Use this section for the current host list and simple hardware notes.
Keep the hardware column brief for now; if a machine is a Raspberry Pi, note that explicitly.

| Host | IP | Role | Notes |
|------|----|------|------------------|
| proxmox1 | 192.168.1.30 | Hypervisor | Lenovo 3136 |
| proxmox2 | 192.168.1.31 | Hypervisor | Lenovo 3130 |
| proxmox3 | 192.168.1.32 | Hypervisor | Lenovo 3135 |
| k8s-cp-01 | 192.168.1.60 | k3s control plane | VM |
| k8s-worker-01 | 192.168.1.61 | k3s worker | VM |
| k8s-worker-02 | 192.168.1.62 | k3s worker | VM |
| Synology NAS | 192.168.1.11 | NFS storage | NAS |
| OPNsense | 192.168.1.1 | Gateway | Firewall/router |
| kwsdisplay | - | - | Raspberry Pi 4 Model B Rev 1.5 |
| kws-rpi-1 | - | - | Raspberry Pi 4 Model B Rev 1.5 |
| burndev | - | - | MSI X470 GAMING PLUS desktop |

## Running Services

| App | URL | Description |
|-----|-----|-------------|
| Homepage | `home.homelab.lan` | Dashboard |
| VS Code | `code.homelab.lan` | Browser-based IDE |
| Trilium | `trilium.homelab.lan` | Notes |
| Kanboard | `kanboard.homelab.lan` | Kanban board |
| Termix | `termix.homelab.lan` | Web terminal |
| Immich | `immich.homelab.lan` | Photo/video backup |
| Prometheus | `prometheus.homelab.lan` | Metrics |
| Grafana | `grafana.homelab.lan` | Dashboards |

## Stack

- **Hypervisor**: Proxmox VE
- **IaC**: Terraform (bpg/proxmox provider)
- **Config management**: Ansible
- **Kubernetes**: k3s v1.36.1 (Traefik & ServiceLB disabled)
- **Ingress**: nginx-ingress

## Prerequisites

- Terraform >= 1.5
- Ansible >= 2.14 with `community.general` collection
- kubectl
- SSH key at `~/.ssh/id_ed25519`
- Proxmox API token with VM provisioning privileges
- Synology NAS with NFS exported at `/volume1/homelab/k8s/`

## Deployment Order

### 1. Provision VMs — Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Set Proxmox API token via environment variable (NEVER commit it):
export TF_VAR_proxmox_api_token="<user>@pve!<token-name>=<secret>"

# Trust the Proxmox self-signed CA (do once):
scp root@<proxmox-ip>:/etc/pve/pve-root-ca.pem /tmp/proxmox-ca.pem
# Install to system trust store
sudo cp /tmp/proxmox-ca.pem /usr/local/share/ca-certificates/proxmox.crt && sudo update-ca-certificates

terraform init
terraform plan
terraform apply
```

Creates 3 VMs on the Proxmox cluster.

### 2. Bootstrap Kubernetes — Ansible

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventory/hosts.ini site.yml
```

This runs the full bootstrap:
- `common` role: disables swap, loads kernel modules, sets sysctl, installs dependencies, configures UFW firewall
- `control_plane` role: installs k3s server on the control plane node
- `worker` role: joins worker nodes to the cluster

### 3. Install Cert-Manager (for TLS)

```bash
bash kubernetes/cert-manager/install-cert-manager.sh
kubectl apply -f kubernetes/cert-manager/ca-issuer.yml
```

All ingresses are pre-configured with TLS annotations. 
Once cert-manager is running, certs are issued automatically.

To trust certs in your browser, export the CA certificate:

```bash
kubectl get secret homelab-ca-secret -n cert-manager -o jsonpath='{.data.tls\.crt}' | base64 -d > homelab-ca.crt
```

Import `homelab-ca.crt` into your OS/browser trust store.

### 4. Deploy Apps — kubectl

```bash
# Copy secret examples into appsecret.yml.
cp /PATH/TO/secret.example.yml /PATH/TO/secret.yml 

# Edit secret file as needed.

# Apply secrets.
kubectl apply -f /PATH/TO/secret.yml 

kubectl apply -f kubernetes/namespaces/
kubectl apply -f kubernetes/policies/
kubectl apply -f kubernetes/apps/
kubectl apply -f kubernetes/monitoring/
```

### 5. Remove Proxmox Subscription Notice (optional)

```bash
ansible-playbook -i ansible/inventory/hosts.ini ansible/pve-nag-buster.yml
```

## Operations

### Verify Alerting

Prometheus alert rules are deployed via `kubernetes/monitoring/alert-rules.yml`.
To verify they are loaded and firing:

```bash
# Check rules are registered
kubectl get prometheusrule -n monitoring

# View active alerts in Prometheus UI
open https://prometheus.homelab.lan/alerts

# Trigger a test alert (temporary down)
kubectl -n monitoring port-forward svc/alertmanager-operated 9093:9093 &
curl http://localhost:9093/api/v2/alerts
```

Alertmanager is deployed by kube-prometheus-stack and routes to the default receiver.
To configure external notifications (email, Slack, etc), update the Alertmanager config
via the kube-prometheus-stack Helm values.

### Restore from Backup

The NAS backup at `/mnt/syn/backups/homelab` contains a full copy of this repo.
To restore on a new machine:

```bash
# 1. Restore the repo from NAS
rsync -aHAX /mnt/syn/backups/homelab/ ~/dev/homelab/

# 2. Verify backup log for last successful run
cat ~/dev/homelab/scripts/backup.log

# 3. Re-run Terraform (no-op if VMs exist, validates state)
cd ~/dev/homelab/terraform
terraform init
terraform plan

# 4. Re-run Ansible (idempotent, checks cluster health)
cd ~/dev/homelab/ansible
ansible-playbook site.yml

# 5. Re-apply all K8s manifests (idempotent)
kubectl apply -f kubernetes/namespaces/
kubectl apply -f kubernetes/policies/
kubectl apply -f kubernetes/apps/
kubectl apply -f kubernetes/monitoring/
```

## Storage Classes

| Name | Provisioner | Backend |
|------|------------|---------|
| `local-path` | rancher.io/local-path | Node-local storage (default) |
| `nfs` | nfs-subdir-external-provisioner | Synology NAS (192.168.1.11) |
| `proxmox-local` | Proxmox CSI plugin | Proxmox local-lvm storage (requires Proxmox CSI driver installed on cluster) |

## Project Structure

```
├── ansible/                  # Ansible config management
│   ├── site.yml              # Main entry point
│   ├── k8s-bootstrap.yml     # K3s cluster bootstrap
│   ├── pve-nag-buster.yml    # Proxmox license notice removal
│   ├── inventory/
│   │   ├── hosts.ini         # Inventory file
│   │   └── group_vars/       # Group-level variables
│   └── roles/
│       ├── common/           # Shared node setup
│       ├── control_plane/    # K3s server install
│       └── worker/           # K3s agent install
├── terraform/                # Infrastructure provisioning
│   ├── main.tf               # VM definitions
│   ├── variables.tf          # Input variables
│   ├── outputs.tf            # Outputs (IPs)
│   ├── terraform.tfvars      # Secrets (gitignored)
│   └── modules/vm/           # Reusable VM module
├── kubernetes/               # K8s manifests
│   ├── cert-manager/         # TLS certificate setup
│   ├── namespaces/           # Namespace definitions
│   ├── policies/             # Network policies
│   │   ├── tools/            #   Per-namespace policies
│   │   └── monitoring/
│   ├── apps/                 # Application deployments
│   └── monitoring/           # Prometheus rules, Grafana dashboards, Blackbox
├── scripts/                  # Utility scripts
└── docs/                     # Documentation & notes
```
