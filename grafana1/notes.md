# grafana1 — repo and process notes

This repo stands up two Ubuntu EC2 nodes in AWS, then configures them with Ansible. Node1 runs a Docker Compose monitoring stack (Prometheus + Grafana). Both nodes run nginx and (when the exporter playbook is applied) node_exporter.

Region: `ap-southeast-1`. VPC CIDR: `10.20.0.0/16`. Public subnet: `10.20.1.0/24`.

```
Browser
  ├─ :80   nginx (both nodes)
  ├─ :3000 Grafana  (node1, Docker)
  └─ :9090 Prometheus UI (node1, Docker)

Grafana  --http://prometheus:9090-->  Prometheus container
Prometheus --scrape :9100-->  node_exporter on 10.20.1.157 and 10.20.1.149
```

`localhost` inside a container is that container only. Grafana must use the Compose service name `prometheus`, not `localhost:9090`.

---

## Layout

| File | Role |
|---|---|
| `providers.tf` | AWS provider, S3 backend `bootcamp-2026-afiq` / `grafana1/terraform.tfstate` |
| `network.tf` | VPC + one public subnet |
| `security.tf` | SG: 80 from world; 22 / 3000 / 9090 from your public IP; 9100 from VPC |
| `ec2.tf` | `node1` and `node2` (`t3.small`, Ubuntu 24.04, key `afiq`, SSM profile) |
| `outputs.tf` | Public IPs, private IPs, SSM session commands |
| `inventory.tf` + `inventory.ini.tftpl` | Terraform writes `inventory.ini` after apply |
| `ansible.cfg` | Inventory `./inventory.ini`, user `ubuntu`, host key checking off |
| `playbook-disk.yaml` | Grow root partition + ext4 after the 16 GiB volume |
| `playbook-web.yaml` | nginx + templated `index.html` on both nodes |
| `playbook-exporter.yaml` | `prometheus.prometheus.node_exporter` on both nodes (`:9100`) |
| `playbook-prometheus.yaml` | Optional: install Prometheus **on the host** via Ansible role |
| `playbook-stack.yaml` | Docker + Compose stack on **node1** at `/opt/monitoring` |
| `compose.yaml` | Prometheus + Grafana services |
| `prometheus.yaml` | Prometheus scrape config (mounted into the container) |
| `grafana/provisioning/datasources/prometheus.yaml` | Grafana datasource URL `http://prometheus:9090` |

Two different Prometheus files exist on purpose:

- `prometheus.yaml` — Prometheus **server config** (YAML mapping: `global`, `scrape_configs`). Copied to `/opt/monitoring/prometheus.yaml` and mounted as `/etc/prometheus/prometheus.yml`.
- `playbook-prometheus.yaml` — Ansible **playbook** that installs Prometheus with the `prometheus.prometheus.prometheus` role. Do not mount this into the container.

---

## Process

Run from the repo root. SSH key expected at `~/.ssh/id_ed25519`.

### 1. Infrastructure

```bash
terraform init
terraform apply
```

This creates the VPC, security group, two EC2 instances, and writes `inventory.ini` with the public IPs.

SSH and Grafana/Prometheus ports are locked to the IP returned by `https://ipv4.icanhazip.com` at apply time. If your public IP changes, re-apply so the SG updates.

### 2. Disk (if the root FS is still the AMI default size)

```bash
ansible-playbook playbook-disk.yaml
```

`growpart /dev/nvme0n1 1` then `resize2fs /dev/nvme0n1p1`. Exit code 2 from `growpart` is treated as “already grown”.

### 3. Web

```bash
ansible-playbook playbook-web.yaml
```

Installs nginx on `nodes`, writes `/var/www/html/index.html` from `index.html.j2`, and `/etc/nginx/sites-available/default` from `nginx-site.conf.j2`. Open `http://<public-ip>/`.

### 4. Node exporter

```bash
ansible-playbook playbook-exporter.yaml
```

Listens on `:9100`. The SG only allows that port from `10.20.0.0/16`, so Prometheus on node1 can scrape private IPs. The public internet cannot.

### 5. Monitoring stack (the path Grafana uses)

```bash
ansible-playbook playbook-stack.yaml
```

On node1 this:

1. Installs Docker (`geerlingguy.docker`).
2. Creates `/opt/monitoring`.
3. Copies `prometheus.yaml`, Grafana provisioning, and `compose.yaml`.
4. Runs `docker compose up -d --force-recreate` in that directory.

`--force-recreate` is required after replacing a bind-mounted file. Docker bind-mounts a file by inode. Ansible `copy` writes a new inode; a running container keeps the old one until recreate.

Default Grafana login is `admin` / `admin`. UI: `http://<node1-public-ip>:3000`. Prometheus UI: `http://<node1-public-ip>:9090`.

### Optional: Prometheus on the host

```bash
ansible-playbook playbook-prometheus.yaml
```

This is a **host** install, not the Compose service. It will fight for port 9090 if the container stack is already bound there. Use one or the other.

---

## How the Compose stack talks

Both services join the default Compose network. DNS name = service name.

| From | To | Address that works |
|---|---|---|
| Browser on your laptop | Grafana | `http://<node1-public-ip>:3000` |
| Browser on your laptop | Prometheus | `http://<node1-public-ip>:9090` |
| Grafana **container** | Prometheus **container** | `http://prometheus:9090` |
| Prometheus **container** (self scrape) | itself | `localhost:9090` |
| Prometheus **container** | node_exporter | `10.20.1.157:9100`, `10.20.1.149:9100` |

Grafana provisioning (`grafana/provisioning/datasources/prometheus.yaml`) sets the datasource to `http://prometheus:9090` with `access: proxy`. Grafana’s backend does the query, so the URL is resolved **inside the Grafana container**.

If you add a datasource by hand in the UI and type `http://localhost:9090`, Grafana queries itself and you get:

```text
dial tcp [::1]:9090: connect: connection refused
```

Fix: URL `http://prometheus:9090`, then Save & test.

---

## Incidents worth remembering

### `services.grafana.ports must be a array`

Compose `ports` must be a YAML list:

```yaml
ports:
  - "3000:3000"
```

`ports: 3000:3000` is a string. Validation fails before anything starts.

### Grafana: connection refused to `localhost:9090`

Two things were true at once:

1. The Grafana datasource URL was `http://localhost:9090`. That is the Grafana container’s loopback.
2. Prometheus was crash-looping. `prometheus.yaml` had been an Ansible playbook (`- name: Pasang Prometheus` …). Prometheus expects a mapping, so it exited with code 2. Pebble kept restarting it. `docker compose ps` still showed `Up` because pebble (PID 1) was alive. Host port 9090 was `docker-proxy`; nothing behind it accepted HTTP.

A container named “up” is not the same as the app inside being ready. Check `docker logs` and `curl http://127.0.0.1:9090/-/ready`.

### Bind mount still served the old playbook

After the real `prometheus.yaml` was copied to the host, `cat /opt/monitoring/prometheus.yaml` looked correct, but the process inside the container still unmarshaled a YAML sequence. The container held the previous inode. Recreate the service after replacing a bind-mounted file.

---

## Checks

On node1:

```bash
sudo docker compose -f /opt/monitoring/compose.yaml ps
sudo docker logs --tail 30 monitoring-prometheus-1
curl -sS http://127.0.0.1:9090/-/ready
curl -sS 'http://127.0.0.1:9090/api/v1/query?query=up'
sudo docker exec monitoring-grafana-1 wget -qO- http://prometheus:9090/-/ready
```

Healthy Prometheus self-scrape:

```text
up{job="prometheus", instance="localhost:9090"}  →  1
```

Node exporter down with `connection refused` means nothing is listening on that host:9100 (exporter playbook not applied, or the service is stopped). SG / routing would look like timeout, not refused.

Private IPs are also Terraform outputs (`node1_private_ip`, `node2_private_ip`). If instances are replaced, update the `targets` list in `prometheus.yaml` and re-run `playbook-stack.yaml`.

---

## Order of operations (short)

```text
terraform apply
        ↓
ansible-playbook playbook-disk.yaml
ansible-playbook playbook-web.yaml
ansible-playbook playbook-exporter.yaml
ansible-playbook playbook-stack.yaml
        ↓
Grafana UI  →  datasource http://prometheus:9090  →  dashboards on job=node_exporter
```
