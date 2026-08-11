# k3s Troubleshooting Guide

> **Status: historical.** Written for the burndev single-node k3s. The cluster now runs on Proxmox VMs (k3s-core/exu/gpu). Most concepts (CrashLoopBackOff, NotReady, etcd) still apply; access via `ssh npburney@192.168.1.70` + `sudo kubectl`. See `proxmox-cluster.md`.

Common issues encountered in the homelab k3s cluster and how to diagnose/fix them.

## Diagnostic Commands

```bash
# Cluster health
kubectl get nodes -o wide
kubectl get pods -A | grep -v Running
kubectl get events -A --sort-by='.lastTimestamp' | tail -30

# Specific node
kubectl describe node <node-name> | tail -40

# Pods on a specific node
kubectl get pods -A -o wide | grep <node-name>
kubectl get pods -A --field-selector spec.nodeName=<node>

# CrashLoopBackOff pods
kubectl get pods -A | grep CrashLoopBackOff
```

### Pod investigation

```bash
kubectl describe pod <pod-name> -n <ns>    # events, conditions, mounts
kubectl logs <pod-name> -n <ns>            # container logs
kubectl logs <pod-name> -n <ns> --previous # logs from previous (crashed) container
```

## Issue: Node NotReady

### Symptoms
- `kubectl get nodes` shows status `NotReady`
- Pods stuck in `Terminating` on that node
- Kubelet stopped posting heartbeats

### Causes
- Node is powered off or unreachable
- Kubelet stopped (crashed, OOM, disk pressure)
- Network partition — node can't reach the control plane

### Diagnosis
```bash
# Check when node last reported
kubectl describe node <node-name> | grep -A5 Conditions
# Look for: KubeletReady, MemoryPressure, DiskPressure, NetworkUnavailable

# Check if node is reachable
ping -c 2 <node-ip>

# Check k3s service on the node
ssh <node> "sudo systemctl status k3s"
ssh <node> "sudo journalctl -u k3s -n 50"
```

### Fix
If the node is permanently gone:

```bash
# Remove node from cluster
kubectl delete node <node-name>

# Force-delete stuck pods
kubectl delete pods --force --grace-period=0 -n <ns> <pod-name>
```

If the node should come back:
1. SSH to the node
2. Check `sudo systemctl status k3s` / `sudo systemctl status k3s-agent`
3. Check disk space: `df -h`
4. Restart k3s: `sudo systemctl restart k3s`

## Issue: CrashLoopBackOff — Read-Only Volume Mount

### Symptoms
- Pod enters CrashLoopBackOff
- Logs show `chown: changing ownership of '...': Read-only file system`
- Container has an init or startup script that runs `chown` on a config volume

### Example (homepage)
Homepage container runs `chown -R 1000:1000 /app/config` at startup, but `/app/config/docker.yaml` is mounted `readOnly: true` from a ConfigMap.

### Fix
Remove `readOnly: true` from the volume mount in the Deployment spec:

```yaml
volumeMounts:
  - name: docker-config
    mountPath: /app/config/docker.yaml
    subPath: docker.yaml
    readOnly: true   # ← REMOVE THIS LINE
```

Apply: `kubectl apply -f kubernetes/apps/homepage.yml`

## Issue: CrashLoopBackOff — Database Connection Refused

### Symptoms
- App pod in CrashLoopBackOff
- Logs show: `ECONNREFUSED <ip>:5432` (PostgreSQL) or similar

### Diagnosis Tree

```bash
# 1. Is the database pod running?
kubectl get pods -n <ns> | grep postgres

# 2. Can the database pod accept local connections?
kubectl exec -n <ns> deployment/<db-deploy> -- pg_isready

# 3. Does DNS resolve from the app pod?
kubectl exec -n <ns> deployment/<app-deploy> -- nslookup <db-svc>

# 4. Can a test pod reach the database?
kubectl run -n <ns> -it --rm test-conn --image=alpine:3.19 --restart=Never -- \
  sh -c "apk add netcat-openbsd; nc -zv -w 3 <db-svc> 5432"

# 5. Check if cross-node networking works (multi-node only):
# Run test pod on same node as DB, then on different node
kubectl get pods -n <ns> -o wide  # note which node each pod is on
```

### Common Causes & Fixes

| Cause | Fix |
|-------|-----|
| DB pod not running | Check DB pod logs, restart if needed |
| NetworkPolicy blocks traffic | Check `kubernetes/policies/` for deny rules |
| CNI broken (flannel) | Restart k3s, check `iptables -L -n -t nat` |
| Wrong DB_HOST env var | Check deployment env vars match service name |
| DB not listening on all interfaces | Check `listen_addresses` in postgresql.conf |

## Issue: Cross-Node Networking (CNI / Flannel)

If pods on different nodes can't reach each other (flannel issue):

```bash
# On the node: check iptables
sudo iptables -L -n -t nat | grep FLANNEL

# Check flannel interface
ip link show flannel.1
ip addr show flannel.1

# Restart k3s (flannel is embedded)
sudo systemctl restart k3s
```

## Issue: kubectl Context Wrong

### Symptoms
- `kubectl --context <name>` fails with "context was not found"
- Commands target the wrong cluster

### Diagnosis
```bash
# See all contexts
kubectl config get-contexts

# Current context
kubectl config current-context

# Full config
kubectl config view
```

### Kubeconfig Locations
- k3s writes config to `/etc/rancher/k3s/k3s.yaml`
- User config at `~/.kube/config`
- `KUBECONFIG` env var overrides everything

### Fix
```bash
# Copy k3s config to user kubeconfig
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config

# Or set KUBECONFIG
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Rename/migrate context if needed
kubectl config rename-context default homelab-local
```

## Issue: Stuck Terminating Pods

**Symptom**: Pods in `Terminating` state for minutes/hours.

**Cause**: The node the pod was running on is unreachable, so the kubelet can't confirm the container has been stopped.

**Fix**:
```bash
kubectl delete pod <pod> -n <ns> --force --grace-period=0
```

## Issue: etcd Quorum Loss

**Symptom**: `kubectl` commands time out. API server is unresponsive.

**Cause**: In an HA etcd cluster (odd number of nodes), more than half are offline. The remaining node can't achieve quorum.

**Fix**: Reinstall k3s as single-node:
```bash
/usr/local/bin/k3s-uninstall.sh
curl -sfL https://get.k3s.io | sh -s - server --cluster-init ...
```

## Quick Reference: Pod Status Meanings

| Status | Meaning | Action |
|--------|---------|--------|
| `Running` | Healthy | None |
| `CrashLoopBackOff` | Container crashes repeatedly | Check logs |
| `ImagePullBackOff` | Can't pull image | Check image name, registry access |
| `Pending` | Can't schedule | Check resources, node capacity, PVC binding |
| `Terminating` | Stuck shutting down | Force delete: `kubectl delete pod --force --grace-period=0` |
| `Error` | Container exited with error | Check logs |
| `Completed` | Job finished | Normal for Jobs/CronJobs |

## Prevention

1. **Single-node is simpler** — fewer failure modes than HA clusters
2. **Monitor node health** — Prometheus alerts for NodeNotReady
3. **Regular backups** — NFS PVCs survive node reinstall; local-path PVCs need separate backup
4. **Test restores** — verify backup integrity before you need it
