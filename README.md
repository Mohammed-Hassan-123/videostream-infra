# VideoStream Infrastructure

Automated homelab deployment of the [VideoStream](https://github.com/Mohammed-Hassan-123/videostream-app) application on a self-hosted Kubernetes cluster provisioned from scratch using Terraform, Ansible, and k3s.

---

## Stack

| Layer | Tool |
|-------|------|
| VM provisioning | Terraform + bpg/proxmox provider |
| OS configuration | Ansible |
| Kubernetes | k3s (single-server, multi-agent) |
| Ingress | ingress-nginx |
| Load balancer | MetalLB (L2 mode) |
| TLS | cert-manager + homelab CA |
| Object storage | MinIO (pre-existing) |
| Database | PostgreSQL (pre-existing) |

---

## Architecture

```
                    ┌─────────────────────────────────────────────────┐
                    │  Proxmox Host (192.168.100.9)                   │
                    │                                                 │
                    │  ┌────────────┐  ┌────────────┐  ┌──────────┐ │
                    │  │ k3s-master │  │k3s-worker1 │  │k3s-worker│ │
                    │  │ .35  VMID  │  │ .36  VMID  │  │  .37     │ │
                    │  │      112   │  │      113   │  │  VMID 114│ │
                    │  └─────┬──────┘  └─────┬──────┘  └────┬─────┘ │
                    └────────┼───────────────┼───────────────┼───────┘
                             │               │               │
                    ┌────────▼───────────────▼───────────────▼───────┐
                    │  LAN 192.168.100.0/24                           │
                    │                                                 │
                    │  MetalLB VIP: 192.168.100.40 → ingress-nginx   │
                    │                                                 │
                    │  MinIO:      192.168.100.25:9000               │
                    │  PostgreSQL: 192.168.100.26:5432               │
                    │  Registry:   192.168.100.11:5000               │
                    └─────────────────────────────────────────────────┘

Client → https://videostream.lan → 192.168.100.40 → ingress-nginx → videostream pods
```

---

## Directory Structure

```
videostream-infra/
├── terraform/
│   ├── provider.tf            # bpg/proxmox provider config
│   ├── variables.tf           # Input variable declarations
│   ├── main.tf                # Module calls for 3 VMs
│   ├── outputs.tf             # VM IP outputs
│   ├── terraform.tfvars       # Values (gitignored)
│   ├── .gitignore
│   └── modules/vm/
│       ├── main.tf            # proxmox_virtual_environment_vm resource
│       ├── variables.tf
│       └── outputs.tf
├── ansible/
│   ├── ansible.cfg
│   ├── inventory.ini          # 3 k3s nodes
│   ├── install-k3s.yml        # k3s server + agents
│   └── configure-registry.yml # Private registry + CA trust
├── k8s/
│   ├── secret.yml             # App env vars (gitignored)
│   ├── deployment.yml         # 2-replica Deployment
│   ├── service.yml            # ClusterIP service
│   ├── ingress.yml            # nginx ingress + TLS
│   ├── metallb-config.yml     # IP pool 192.168.100.40
│   └── clusterissuer.yaml     # cert-manager homelab CA issuer
├── .gitignore
├── README.md
└── DEPLOY_REPORT.md
```

---

## Prerequisites

- Proxmox VE host reachable at 192.168.100.9
- VM template (VMID 9001) with cloud-init support
- MinIO running at 192.168.100.25
- PostgreSQL running at 192.168.100.26
- Private Docker registry at 192.168.100.11:5000 with `videostream:latest`
- DNS resolving `videostream.lan` to 192.168.100.40
- Tools on control node: `terraform` (v1.15+), `ansible-playbook` (~/.local/bin/), `ssh`

---

## Deploy Steps

### 1. Provision VMs

```bash
cd terraform/
terraform init
terraform apply -auto-approve
terraform output
```

Expected output:
```
k3s_master_ip  = "192.168.100.35"
k3s_worker1_ip = "192.168.100.36"
k3s_worker2_ip = "192.168.100.37"
```

### 2. Wait for VMs to boot, then test connectivity

```bash
cd ../ansible/
~/.local/bin/ansible all -m ping
```

### 3. Install k3s

```bash
~/.local/bin/ansible-playbook install-k3s.yml
```

### 4. Generate homelab CA on k3s-master

```bash
ssh k3smaster@192.168.100.35 "mkdir -p ~/ca && \
  openssl genrsa -out ~/ca/ca.key 4096 && \
  openssl req -new -x509 -days 3650 -key ~/ca/ca.key -out ~/ca/ca.crt \
    -subj '/C=BD/ST=Dhaka/L=Dhaka/O=Homelab-CA/CN=Homelab Root CA'"
```

### 5. Configure registry mirror and distribute CA

```bash
~/.local/bin/ansible-playbook configure-registry.yml
```

> **Note:** If the "Restart containerd" task fails (containerd is bundled in k3s, not a separate service), manually restart k3s services:
> ```bash
> ssh k3smaster@192.168.100.35 "sudo systemctl restart k3s"
> ssh k3sworker1@192.168.100.36 "sudo systemctl restart k3s-agent"
> ssh k3sworker2@192.168.100.37 "sudo systemctl restart k3s-agent"
> ```

### 6. Install cluster addons

```bash
# ingress-nginx
ssh k3smaster@192.168.100.35 "sudo kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.0/deploy/static/provider/cloud/deploy.yaml"

# MetalLB
ssh k3smaster@192.168.100.35 "sudo kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml"

# cert-manager
ssh k3smaster@192.168.100.35 "sudo kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.17.2/cert-manager.yaml"
```

> **Note:** k3s ships with Traefik which will claim the MetalLB IP. Patch it to release the IP for ingress-nginx:
> ```bash
> ssh k3smaster@192.168.100.35 "sudo kubectl patch svc traefik -n kube-system -p '{\"spec\":{\"type\":\"ClusterIP\"}}'"
> ```

### 7. Configure cert-manager CA

```bash
ssh k3smaster@192.168.100.35 "sudo kubectl create secret tls homelab-ca-secret \
  --cert=/home/k3smaster/ca/ca.crt \
  --key=/home/k3smaster/ca/ca.key \
  --namespace=cert-manager"

ssh k3smaster@192.168.100.35 "sudo kubectl apply -f -" < k8s/clusterissuer.yaml
```

### 8. Apply application manifests

```bash
ssh k3smaster@192.168.100.35 "sudo kubectl apply -f -" < k8s/metallb-config.yml
ssh k3smaster@192.168.100.35 "sudo kubectl apply -f -" < k8s/secret.yml
ssh k3smaster@192.168.100.35 "sudo kubectl apply -f -" < k8s/deployment.yml
ssh k3smaster@192.168.100.35 "sudo kubectl apply -f -" < k8s/service.yml
ssh k3smaster@192.168.100.35 "sudo kubectl apply -f -" < k8s/ingress.yml
```

### 9. Verify

```bash
curl -sk https://videostream.lan/health
# → {"status":"ok","uptime":...}
```

---

## Post-deploy: Trust the new CA on your laptop

After deployment, copy the new CA to your laptop's trust store:

```bash
scp k3smaster@192.168.100.35:~/ca/ca.crt homelab-ca.crt
sudo cp homelab-ca.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates
```

---

## App Repository

https://github.com/Mohammed-Hassan-123/videostream-app
