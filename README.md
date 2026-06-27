# videostream-infra

IaC for deploying [VideoStream](https://github.com/Mohammed-Hassan-123/videostream-app) on a self-hosted k3s cluster. Provisions three VMs on Proxmox via Terraform, configures k3s with Ansible, and deploys the app to Kubernetes with ingress-nginx, MetalLB, and cert-manager.

---

## Prerequisites

The following must exist before running this deployment:

- **Proxmox VE** at `192.168.100.9` with API access and VM template **VMID 9001** (cloud-init enabled)
- **MinIO** running at `192.168.100.25:9000` (bucket: `videostream`)
- **PostgreSQL** running at `192.168.100.26:5432` (database: `videostream_db`)
- **Private registry** at `192.168.100.11:5000` with `videostream:latest` pushed
- **DNS** resolving `videostream.lan` → `192.168.100.40`
- **Control node tools:** `terraform`, `~/.local/bin/ansible-playbook`, `ssh` key at `~/.ssh/id_ed25519`

---

## Directory Structure

```
videostream-infra/
├── terraform/          # VM provisioning via bpg/proxmox — creates k3s-master, k3s-worker1, k3s-worker2
│   └── modules/vm/     # Reusable VM module (clone from template 9001, cloud-init networking)
├── ansible/            # k3s installation and registry/CA configuration across all nodes
└── k8s/                # Kubernetes manifests — deployment, service, ingress, MetalLB, cert-manager
```

---

## Deploy

### 1. Provision VMs

```bash
cd terraform/
terraform init
terraform apply -auto-approve
```

Expected output:
```
k3s_master_ip  = "192.168.100.35"
k3s_worker1_ip = "192.168.100.36"
k3s_worker2_ip = "192.168.100.37"
```

### 2. Wait for VMs to boot, verify connectivity

```bash
cd ../ansible/
~/.local/bin/ansible all -m ping
```

All three nodes must return `pong` before proceeding.

### 3. Install k3s

```bash
~/.local/bin/ansible-playbook install-k3s.yml
```

Installs k3s server on the master, then joins both workers as agents.

### 4. Generate homelab CA on k3s-master

```bash
ssh k3smaster@192.168.100.35 "
  mkdir -p ~/ca
  openssl genrsa -out ~/ca/ca.key 4096
  openssl req -new -x509 -days 3650 -key ~/ca/ca.key -out ~/ca/ca.crt \
    -subj '/C=BD/ST=Dhaka/L=Dhaka/O=Homelab-CA/CN=Homelab Root CA'
"
```

### 5. Configure registry mirror and distribute CA

```bash
~/.local/bin/ansible-playbook configure-registry.yml
```

Deploys `/etc/rancher/k3s/registries.yaml` (mirror for `192.168.100.11:5000`) and copies the CA to the system trust store on all nodes.

> **Note:** The "Restart containerd" task will fail — k3s bundles containerd internally, there is no standalone `containerd.service`. Manually restart k3s services to apply the changes:
> ```bash
> ssh k3smaster@192.168.100.35 "sudo systemctl restart k3s"
> ssh k3sworker1@192.168.100.36 "sudo systemctl restart k3s-agent"
> ssh k3sworker2@192.168.100.37 "sudo systemctl restart k3s-agent"
> ```

### 6. Install cluster addons

```bash
# ingress-nginx
ssh k3smaster@192.168.100.35 "sudo kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.0/deploy/static/provider/cloud/deploy.yaml"
ssh k3smaster@192.168.100.35 "sudo kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=120s"

# MetalLB
ssh k3smaster@192.168.100.35 "sudo kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml"
ssh k3smaster@192.168.100.35 "sudo kubectl rollout status deployment/controller -n metallb-system --timeout=90s"
ssh k3smaster@192.168.100.35 "sudo kubectl rollout status daemonset/speaker -n metallb-system --timeout=90s"

# cert-manager
ssh k3smaster@192.168.100.35 "sudo kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.17.2/cert-manager.yaml"
ssh k3smaster@192.168.100.35 "sudo kubectl rollout status deployment/cert-manager -n cert-manager --timeout=120s"
ssh k3smaster@192.168.100.35 "sudo kubectl rollout status deployment/cert-manager-webhook -n cert-manager --timeout=120s"
ssh k3smaster@192.168.100.35 "sudo kubectl rollout status deployment/cert-manager-cainjector -n cert-manager --timeout=120s"
```

### 7. Free MetalLB IP from Traefik

> **Note:** k3s ships with Traefik as a default ingress controller. Its LoadBalancer service will claim the only MetalLB IP (`192.168.100.40`) before ingress-nginx can acquire it. Patch it to ClusterIP:

```bash
ssh k3smaster@192.168.100.35 "sudo kubectl patch svc traefik -n kube-system -p '{\"spec\":{\"type\":\"ClusterIP\"}}'"
```

Verify ingress-nginx gets the IP:
```bash
ssh k3smaster@192.168.100.35 "sudo kubectl get svc -n ingress-nginx ingress-nginx-controller"
# EXTERNAL-IP should be 192.168.100.40
```

### 8. Configure cert-manager

```bash
# Create CA secret
ssh k3smaster@192.168.100.35 "sudo kubectl create secret tls homelab-ca-secret \
  --cert=/home/k3smaster/ca/ca.crt \
  --key=/home/k3smaster/ca/ca.key \
  --namespace=cert-manager"

# Apply ClusterIssuer
ssh k3smaster@192.168.100.35 "sudo kubectl apply -f -" < k8s/clusterissuer.yaml

# Verify
ssh k3smaster@192.168.100.35 "sudo kubectl get clusterissuer homelab-ca-issuer"
# READY should be True
```

### 9. Apply application manifests

```bash
ssh k3smaster@192.168.100.35 "sudo kubectl apply -f -" < k8s/metallb-config.yml
ssh k3smaster@192.168.100.35 "sudo kubectl apply -f -" < k8s/secret.yml
ssh k3smaster@192.168.100.35 "sudo kubectl apply -f -" < k8s/deployment.yml
ssh k3smaster@192.168.100.35 "sudo kubectl apply -f -" < k8s/service.yml
ssh k3smaster@192.168.100.35 "sudo kubectl apply -f -" < k8s/ingress.yml
ssh k3smaster@192.168.100.35 "sudo kubectl rollout status deployment/videostream -n default --timeout=120s"
```

### 10. Verify

```bash
curl -sk https://videostream.lan/health
# → {"status":"ok","uptime":...}
```

Full state check:
```bash
ssh k3smaster@192.168.100.35 "sudo kubectl get nodes,pods,svc,ingress,certificate -A"
```

---

## Post-Deploy

Trust the new homelab CA on your laptop:

```bash
scp k3smaster@192.168.100.35:~/ca/ca.crt homelab-ca.crt
sudo cp homelab-ca.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates
```

---

## App Repository

https://github.com/Mohammed-Hassan-123/videostream-app
