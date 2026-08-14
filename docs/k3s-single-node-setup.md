# k3s Single-Node Setup (burndev)

> **Status: historical.** Documents the decommissioned single-node k3s on burndev. k3s now runs as a 3-node cluster (k3s-core/exu/gpu) on Proxmox VMs 120–122 (192.168.1.70/.71/.72), all control-plane+etcd. See `proxmox-cluster.md` and `pve-k3s.md`.

How the homelab moved from Proxmox VMs to bare-metal k3s on `burndev` (192.168.1.50), plus complete setup and configuration.

## Architecture Decision

**Previous**: Three Proxmox VMs (k8s-cp-01, k8s-worker-01, k8s-worker-02) on mini-PC cluster.
**Current**: Single-node k3s with embedded etcd on burndev, the bare-metal Debian desktop.

### Why the change
- Proxmox VMs added complexity without benefit for a single-user homelab
- burndev runs 24/7 and had capacity
- Single-node means no cross-node networking, no quorum concerns, no etcd split-brain risk

## Prerequisites

- Debian-based OS (burndev runs Debian 13 trixie)
- Static IP configured (192.168.1.50)
- Docker already installed and running
- Synology NAS mounted at `/mnt/syn` for NFS PVCs
- DNS records: `*.burndev.lan` and `*.homelab.lan` → `192.168.1.50`

## Install k3s

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.36.1+k3s1 sh -s - server \
  --write-kubeconfig-mode 644 \
  --disable traefik \
  --disable servicelb \
  --cluster-init \
  --node-name burndev
```

**Flags explained**:
| Flag | Purpose |
|------|---------|
| `--write-kubeconfig-mode 644` | kubectl works without sudo |
| `--disable traefik` | use nginx-ingress instead |
| `--disable servicelb` | no need for built-in load balancer on single node |
| `--cluster-init` | initializes embedded etcd (required even for single node) |
| `--node-name burndev` | explicit node name matching the host |

## Verify

```bash
sudo k3s kubectl get nodes
# Expected: burndev   Ready   control-plane,etcd   <age>   v1.36.1+k3s1
```

## Post-Install Steps

### 1. Install nginx-ingress (replaces Traefik)

k3s disables Traefik; nginx-ingress is the replacement.

**Note**: nginx-ingress is currently not running (stuck Terminating as of July 2026). Caddy routes directly to NodePorts (30080-30086) instead. The NetworkPolicy allow rules referencing `ingress-nginx` are vestigial. To fully reinstate nginx-ingress, delete the stale namespace and reinstall:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.13.1/deploy/static/provider/baremetal/deploy.yaml
```

### 2. Install cert-manager

```bash
chmod +x kubernetes/cert-manager/install-cert-manager.sh
bash kubernetes/cert-manager/install-cert-manager.sh
kubectl apply -f kubernetes/cert-manager/ca-issuer.yml
```

### 3. Deploy Apps (in order)

```bash
# 1. Namespaces
kubectl apply -f kubernetes/namespaces/

# 2. Network policies
kubectl apply -f kubernetes/policies/tools/
kubectl apply -f kubernetes/policies/monitoring/

# 3. Apps
kubectl apply -f kubernetes/apps/

# 4. Monitoring (optional)
kubectl apply -f kubernetes/monitoring/
```

**Note**: `blackbox-values.yml` and `prometheus-additional-scrape.yml` are **not** `kubectl apply`-able. They are Helm values / Prometheus config snippets used when installing kube-prometheus-stack and blackbox-exporter.

## Ansible Notes (Optional)

When running from burndev itself, Ansible is overkill — it was designed for remote provisioning of Proxmox VMs. Direct `kubectl` or `k3s kubectl` is simpler and sufficient for a local single-node cluster.

### Ansible gotchas (if using)
- The playbook is `ansible/site.yml`, NOT `inventory/site.yml`
- `ansible_user` must be `npburney` (not `debian` which was for Proxmox VMs)
- When running locally, use `connection: local` or skip SSH entirely:
  ```yaml
  # ansible/inventory/host_vars/burndev.yml
  ansible_connection: local
  ansible_user: npburney
  ```

## Kubeconfig

- `/etc/rancher/k3s/k3s.yaml` is the cluster kubeconfig
- The context name is `default`, pointing at `https://127.0.0.1:6443`
- If you switch between burndev and mini-PC, you need separate contexts

```bash
# Copy k3s config to user kubeconfig
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config

# Or set KUBECONFIG
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Rename context for clarity
kubectl config rename-context default homelab-local
```

## UFW Rules

These ports must be open on the host:

| Port | Proto | Purpose |
|------|-------|---------|
| 22 | TCP | SSH |
| 80 | TCP | HTTP ingress |
| 443 | TCP | HTTPS ingress |
| 6443 | TCP | k3s API server |
| 10250 | TCP | kubelet |
| 8472 | UDP | Flannel VXLAN |
| 9345 | TCP | k3s supervisor |
| 2379 | TCP | etcd client |
| 2380 | TCP | etcd peer |

## Storage Classes

| StorageClass | Backend | Used By |
|-------------|---------|---------|
| `local-path` | Local host disk | termix, trilium, immich-postgres |
| `nfs` | Synology NAS (`/volume1/homelab/k8s/`) | code-server, kanboard, grafana, homepage, immich-upload |
| `immich-upload-manual` | NFS (manually provisioned PV) | immich uploads |

**Important**: Services using `local-path` have data tied to burndev's disk. NFS-backed services survive node rebuilds.

## Services Running on k3s

| Service | Namespace | NodePort | Domain |
|---------|-----------|----------|--------|
| Homepage | default | 30080 | home.homelab.lan |
| Trilium | tools | 30081 | trilium.homelab.lan |
| Termix | tools | 30082 | termix.homelab.lan |
| VS Code | tools | 30083 | code.homelab.lan |
| Kanboard | tools | 30084 | kanboard.homelab.lan |
| Omni Tools | tools | 30085 | omni.homelab.lan |
| Grafana | monitoring | 30086 | grafana.homelab.lan |

## Common Issues

### k3s not found / service not found
This means k3s was never installed or was cleaned up. No `k3s-uninstall.sh` needed — just run the install command.

### Ansible SSH failures
If using Ansible on the same machine, set `ansible_connection: local` in host vars instead of SSH (see Ansible Notes above).

### Missing nginx-ingress
Symptoms: Ingress resources fail with "no matches for kind Ingress" or webhook errors.
Fix: Install nginx-ingress (see Post-Install Steps above).

### cert-manager warnings on first apply
`missing annotation` warnings from `kubectl apply` are normal on first install. cert-manager works correctly despite them.

### DNS hairpin
Symptom: Internal clients can't reach homelab services by domain.
Fix: Enable NAT reflection in OPNsense, or ensure internal DNS resolves directly to `192.168.1.50`.

## k3s Uninstall (if needed)

```bash
/usr/local/bin/k3s-uninstall.sh
```

## Architecture Notes

- Single-node k3s with embedded etcd (no external datastore)
- Caddy runs in Docker (`network_mode: host`, owns ports 80/443)
- Caddy reverse-proxies: Docker services → `127.0.0.1:<port>`, K8s services → `127.0.0.1:30080-30086` (NodePort)
- Docker socket proxy at `192.168.1.50:2375` for Homepage auto-discovery
- NAS at `192.168.1.11` provides NFS for persistent K8s storage and backups

---

# Multi-Node Troubleshooting (Historical — Proxmox Cluster)

These issues occurred on the old 3-node Proxmox cluster. Documented here for reference.

## Node NotReady (kubelet stopped posting)

**Symptom**: Node shows `NotReady`, last heartbeat weeks ago, pods stuck `Terminating`.
**Root cause**: VM went down and never came back.
**Fix**:
```bash
kubectl delete node k8s-worker-01
kubectl delete pods --force --grace-period=0 -n <ns> <stuck-pod>
```

If the node should come back:
1. SSH to the node
2. Check `sudo systemctl status k3s` / `sudo systemctl status k3s-agent`
3. Check disk space: `df -h`
4. Restart k3s: `sudo systemctl restart k3s`

## Cross-node pod networking broken

**Symptom**: Pod on node A cannot reach pod on node B (ECONNREFUSED despite DNS resolution).
**Root cause**: Flannel routing between nodes broke. No CNI DaemonSets visible (k3s uses embedded flannel).
**Diagnosis**: Check CNI with `kubectl get pods -n kube-system`, test cross-node connectivity with `nc -zv <pod-ip> <port>` from a debug pod.
**Fix**: Requires node-level investigation (iptables rules, firewall, flannel config on each node).

## homepage CrashLoopBackOff (readOnly mount)

**Symptom**: Container `chown` fails on a readOnly file.
**Root cause**: ConfigMap mounted with `readOnly: true` but container init tries to `chown`.
**Fix**: Remove `readOnly: true` from the volume mount in the deployment.

## immich-server CrashLoopBackOff (postgres unreachable)

**Symptom**: ECONNREFUSED to postgres, but postgres pod is Running.
**Root cause**: Cross-node networking failure or postgres listening config.
**Diagnosis**: Check postgres `listen_addresses` config, check network policies, verify cross-node connectivity.
