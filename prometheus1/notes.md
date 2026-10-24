# Prometheus 1 — Setup Notes

**Terraform (AWS) + Ansible (Prometheus + node_exporter)**

Lab this folder builds: two Ubuntu nodes in a public subnet. **node1** runs Prometheus. **Both nodes** run `node_exporter`. Prometheus scrapes itself and both exporters over the VPC private network.

---

## Architecture

```
Operator laptop
  │  SSH :22  (your public IP only)
  │  HTTP :80 (open)
  │  Prometheus UI :9090 (your public IP only)
  ▼
┌──────────────────────────── VPC 10.20.0.0/16 ─────────────────────────────┐
│  public subnet 10.20.1.0/24  ·  ap-southeast-1a                           │
│                                                                            │
│   node1 (t3.micro, Ubuntu 24.04)              node2 (t3.micro, Ubuntu 24.04)
│   ┌──────────────────────────┐                ┌──────────────────────────┐ │
│   │ nginx           :80      │                │ nginx           :80      │ │
│   │ Prometheus      :9090    │                │                          │ │
│   │ node_exporter   :9100    │◄── scrape ─────│ node_exporter   :9100    │ │
│   │ scrape localhost:9090    │                │                          │ │
│   └──────────────────────────┘                └──────────────────────────┘ │
│         ▲  scrape private IP:9100                                          │
└─────────┴──────────────────────────────────────────────────────────────────┘
```

| Role | Host | What it does |
|------|------|----------------|
| Prometheus server | `node1` | Pulls metrics, UI at `:9090` |
| node_exporter | `nodes` (node1 + node2) | Exposes host metrics at `:9100` |
| nginx | `nodes` | Sample web app at `:80` |

Prometheus **pulls**. Exporters only listen. Prometheus on node1 reaches node2 on **private IP :9100**, not the public IP.

---

## Ports and security group

From `security.tf`:

| Rule | Port | Source | Why |
|------|------|--------|-----|
| `http` | 80/tcp | `0.0.0.0/0` | nginx from the internet |
| `ssh` | 22/tcp | your public IP `/32` | Ansible + SSH |
| `prometheus` | 9090/tcp | your public IP `/32` | Prometheus UI from your laptop |
| `node_exporter` | 9100/tcp | `10.20.0.0/16` | scrape inside the VPC only |
| egress | all | `0.0.0.0/0` | packages, galaxy, AMI updates |

Your IP is resolved at `terraform apply` via `https://ipv4.icanhazip.com`. If your home/office IP changes, re-apply so SSH and `:9090` still work.

`:9100` is VPC-only. You cannot hit node_exporter from the laptop unless you tunnel. That is intentional.

---

## Terraform inventory

`providers.tf` — AWS `ap-southeast-1`, state in S3:

```
bucket = bootcamp-2026-afiq
key    = prometheus1/terraform.tfstate
```

`ec2.tf` — two instances:

- AMI: Ubuntu 24.04 Noble (`ubuntu-noble-24.04-amd64-server-*`, owner Canonical)
- Type: `t3.micro`
- Disk: 16 GB root (`playbook-disk.yaml` grows the partition after boot)
- Key: `afiq`
- IAM profile: `EC2-SSM-Role-devops` (browser SSM session)

`inventory.tf` writes `inventory.ini` from `inventory.ini.tftpl` using **public** IPs (Ansible SSH).

`ansible.cfg`:

```
inventory = ./inventory.ini
remote_user = ubuntu
host_key_checking = False
```

After apply, useful outputs:

```bash
terraform output node1_ip
terraform output node2_ip
terraform output node1_private_ip
terraform output node2_private_ip
terraform output ssm_command_1
terraform output ssm_command_2
```

Put the **private** IPs into `prometheus.yaml` scrape targets. Public IPs go to Ansible inventory only.

---

## Ansible playbooks — run order

Install the collection once on the laptop:

```bash
ansible-galaxy collection install prometheus.prometheus
```

Then, after `terraform apply` and SSH works:

```bash
ansible-playbook playbook-disk.yaml
ansible-playbook playbook-web.yaml
ansible-playbook playbook-exporter.yaml
ansible-playbook prometheus.yaml
```

| Playbook | Hosts | Job |
|----------|-------|-----|
| `playbook-disk.yaml` | `nodes` | `growpart` + `resize2fs` on `/dev/nvme0n1` so the 16 GB disk is actually used |
| `playbook-web.yaml` | `nodes` | nginx + `index.html.j2` + `nginx-site.conf.j2` |
| `playbook-exporter.yaml` | `nodes` | role `prometheus.prometheus.node_exporter` |
| `prometheus.yaml` | `node1` | role `prometheus.prometheus.prometheus` + scrape config |

`prometheus.yaml` is **node1 only**. Installing Prometheus on both nodes is wrong for this lab.

---

## Scrape config (the important bit)

From `prometheus.yaml`:

```yaml
prometheus_scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ['localhost:9090']
  - job_name: node_exporter
    static_configs:
      - targets:
          - '10.20.1.83:9100'   # node1 private IP — replace after apply
          - '10.20.1.38:9100'   # node2 private IP — replace after apply
```

| Job | Target | Metrics |
|-----|--------|---------|
| `prometheus` | `localhost:9090` | Prometheus itself (up, scrape duration, TSDB) |
| `node_exporter` | both private `:9100` | CPU, mem, disk, net (`node_*`) |

Those two IPs are **static**. Recreate the instances → new private IPs → edit `prometheus.yaml` → re-run the playbook. Do not point scrape at public IPs: SG blocks `:9100` from outside the VPC.

Check targets after install:

1. Browser: `http://<node1_public_ip>:9090`
2. **Status → Targets** — both `node_exporter` rows and `prometheus` should be **UP**
3. Query examples:

```promql
up
node_cpu_seconds_total
node_memory_MemAvailable_bytes
node_filesystem_avail_bytes
```

`up == 1` means that scrape target answered. `up == 0` means Prometheus cannot reach it (wrong IP, exporter down, or SG).

---

## How Prometheus fits together

```
node_exporter :9100  ──(pull every scrape interval)──►  Prometheus :9090  ──► UI / PromQL
nginx :80            (app traffic; not scraped in this lab)
```

- **Exporter** = small HTTP process that turns OS stats into Prometheus text format.
- **Scrape** = Prometheus HTTP GET to `/metrics` on each target (default interval 15s unless the role changes it).
- **Job** = named group of targets (`job_name` becomes the `job` label).
- **Instance** label = usually `host:port` of the target.

This lab uses **static_configs**. No Consul, no EC2 service discovery, no file_sd.

---

## Verify

```bash
# from laptop — nginx
curl http://$(terraform output -raw node1_ip)
curl http://$(terraform output -raw node2_ip)

# Prometheus UI (must be your current public IP, matching SG)
# http://<node1_public_ip>:9090

# SSM if SSH is awkward
aws ssm start-session --target <instance_id>
```

On the nodes (via SSH/SSM):

```bash
sudo systemctl status prometheus
sudo systemctl status node_exporter
curl -s localhost:9100/metrics | head
curl -s localhost:9090/-/ready
```

---

## Files

| File | Role |
|------|------|
| `providers.tf` | AWS provider, S3 backend |
| `network.tf` | VPC + public subnet |
| `security.tf` | SG: 80 / 22 / 9090 / 9100 |
| `ec2.tf` | node1, node2, AMI, 16 GB disk, SSM profile |
| `inventory.tf` + `inventory.ini.tftpl` | generate Ansible inventory (public IPs) |
| `outputs.tf` | public IPs, private IPs, SSM commands |
| `ansible.cfg` | inventory path, `ubuntu` user |
| `playbook-disk.yaml` | grow root filesystem |
| `playbook-web.yaml` | nginx demo site |
| `playbook-exporter.yaml` | node_exporter on all nodes |
| `prometheus.yaml` | Prometheus on node1 + scrape jobs |
| `index.html.j2` / `nginx-site.conf.j2` | web templates |

---

## Checklist

- [ ] `terraform init && terraform apply`
- [ ] Copy **private** IPs into `prometheus.yaml` scrape targets
- [ ] `ansible-galaxy collection install prometheus.prometheus`
- [ ] Disk playbook → web playbook → exporter playbook → prometheus playbook
- [ ] Open `http://<node1_public>:9090` → Status → Targets all **UP**
- [ ] PromQL `up` shows 3 series (prometheus + 2 exporters)
- [ ] nginx answers on both public IPs port 80
- [ ] `:9100` is not reachable from the laptop (VPC-only)

---

## Gotchas

1. **Stale scrape IPs** — most common Targets DOWN cause after recreate.
2. **Wrong host for Prometheus** — play is `hosts: node1`, not `nodes`.
3. **Scraping public :9100** — SG denies it; use private IPs.
4. **Your IP changed** — SSH and :9090 fail until SG re-apply.
5. **16 GB disk unused** — Ubuntu AMI may still show ~8 GB until `playbook-disk.yaml`.
6. **Collection missing** — `prometheus.prometheus.prometheus` needs Galaxy, not apt.
