# VideoStream Infrastructure Deployment Report

**Timestamp:** 2026-06-27T14:20 UTC  
**Deployed by:** Claude Code (claude-sonnet-4-6)  
**Control node:** master VM (192.168.100.6)

---

## Section Results

| Section | Status | Notes |
|---------|--------|-------|
| 1 — Directory structure | PASS | Dirs created: terraform/, terraform/modules/vm/, ansible/, k8s/ |
| 2 — Terraform files | PASS | 9 files created across terraform/ and modules/vm/ |
| 3 — Terraform init & apply | PASS | 3 VMs provisioned in 1m23s; IPs match expected |
| 4 — Ansible files | PASS | ansible.cfg, inventory.ini, install-k3s.yml, configure-registry.yml created |
| 5 — Run Ansible | PARTIAL | install-k3s.yml: PASS; configure-registry.yml: PARTIAL (see note below) |
| 6 — Kubernetes manifests | PASS | secret, deployment, service, ingress, metallb-config, clusterissuer created |
| 7 — Install cluster addons | PASS | ingress-nginx, MetalLB, cert-manager all Running (with workaround, see note) |
| 8 — Configure cert-manager | PASS | homelab-ca-secret created, ClusterIssuer homelab-ca-issuer Ready=True |
| 9 — Apply manifests | PASS | All resources created; deployment rolled out 2/2 replicas |
| 10 — Verify | PASS | All checks passed (see details below) |
| 11 — .gitignore and README | PASS | Both files created |
| 12 — Final report | PASS | This document |

---

## Issues Encountered & Resolutions

### Section 5 — configure-registry.yml: "Restart containerd" task failed

**Root cause:** The playbook targeted a standalone `containerd` service (`systemctl restart containerd`), but k3s uses its own bundled containerd managed under the `k3s` / `k3s-agent` service — there is no separate `containerd.service`.

**Resolution:** All preceding tasks (deploy registries.yaml, copy CA cert, update-ca-certificates) completed successfully. After playbook failure, k3s services were restarted directly:
```
sudo systemctl restart k3s          # on k3s-master
sudo systemctl restart k3s-agent    # on k3s-worker1 and k3s-worker2
```
All 3 nodes returned to Ready state after restart. Registry mirror and CA trust are operational.

### Section 7 — Traefik claiming MetalLB IP

**Root cause:** k3s ships with Traefik as a default ingress controller, and Traefik's LoadBalancer service claimed the only MetalLB IP (192.168.100.40) before ingress-nginx could acquire it.

**Resolution:** Traefik's service was patched to ClusterIP to release the IP:
```
kubectl patch svc traefik -n kube-system -p '{"spec":{"type":"ClusterIP"}}'
```
MetalLB then immediately assigned 192.168.100.40 to the ingress-nginx-controller service.

---

## Final Cluster State

### Nodes (3/3 Ready)

```
NAME          STATUS   ROLES           AGE   VERSION        INTERNAL-IP
k3s-master    Ready    control-plane   25m   v1.36.2+k3s1   192.168.100.35
k3s-worker1   Ready    <none>          18m   v1.36.2+k3s1   192.168.100.36
k3s-worker2   Ready    <none>          19m   v1.36.2+k3s1   192.168.100.37
```

### Application Pods (2/2 Running)

```
NAME                           READY   STATUS    RESTARTS   NODE
videostream-79dff6dd8f-g9rr2   1/1     Running   0          k3s-worker2
videostream-79dff6dd8f-xzbj7   1/1     Running   0          k3s-worker1
```

### ingress-nginx Service

```
NAME                       TYPE           CLUSTER-IP     EXTERNAL-IP      PORTS
ingress-nginx-controller   LoadBalancer   10.43.234.62   192.168.100.40   80:32680/TCP,443:31998/TCP
```

EXTERNAL-IP = 192.168.100.40 ✓

### Certificate

```
NAME              READY   SECRET
videostream-tls   True    videostream-tls
```

Ready = True ✓

### Ingress

```
NAME          CLASS   HOSTS             ADDRESS          PORTS
videostream   nginx   videostream.lan   192.168.100.40   80, 443
```

### Health Check

```
curl -sk https://videostream.lan/health
→ {"status":"ok","uptime":265.81710493}
```

---

## Verification Checklist

- [x] 3 nodes Ready
- [x] 2 pods 1/1 Running
- [x] ingress-nginx EXTERNAL-IP = 192.168.100.40
- [x] Certificate videostream-tls Ready = True
- [x] curl https://videostream.lan/health returns {"status":"ok",...}

---

## Post-Deployment Action Required

Copy the new homelab CA certificate from k3s-master to the laptop OS trust store:

```bash
scp k3smaster@192.168.100.35:~/ca/ca.crt homelab-ca.crt
sudo cp homelab-ca.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates
```

This replaces the OLD CA cert previously trusted on the laptop.
