# Linux Server Monitoring Stack

A simple hardware monitoring stack for Ubuntu servers using Grafana Alloy, Prometheus, Loki, and Grafana.

## What You Get

- CPU usage (per core)
- Memory and swap usage
- Disk I/O and space
- Network traffic
- System load
- System logs (journald + file logs)
- Docker container metrics (CPU, memory, network per container)
- Docker container logs (auto-discovered, including new containers)
- NVIDIA GPU metrics (utilization, memory, temperature, power, clocks)

## Requirements

- Ubuntu 20.04+ (or other modern Linux with systemd)
- Docker and Docker Compose
- NVIDIA Container Toolkit (for GPU monitoring)

## Setup

```bash
git clone https://github.com/SohaibTaqat/server-monitor.git
cd server-monitor
docker compose up -d
```

## Access

| Service | URL | Purpose |
|---------|-----|---------|
| Grafana | http://localhost:3000 | Dashboards and logs |
| Alloy | http://localhost:12345 | Pipeline debugging |
| Prometheus | http://localhost:9090 | Raw metrics queries |
| DCGM Exporter | http://localhost:9400 | GPU metrics endpoint |

No login required - anonymous admin is enabled.

## Dashboards

### Hardware Overview (auto-provisioned)
A quick-glance dashboard with:
- **System stats** — uptime, CPU cores, total RAM, load average
- **Health gauges** — CPU, RAM, swap, root filesystem usage
- **Per-core CPU** bar chart + CPU temperature gauge
- **Network & Disk I/O** — stats with sparklines

### Node Exporter Full (optional manual import)
1. Open Grafana at http://localhost:3000
2. Go to **Dashboards** > **Import**
3. Enter ID `1860` and click **Load**
4. Select **Prometheus** as the data source
5. Click **Import**

### GPU Overview (auto-provisioned)
A dashboard for NVIDIA GPUs with:
- **GPU info** — count and model names (auto-discovered)
- **Utilization & memory gauges** — per GPU side by side
- **Temperature & power gauges** — per GPU
- **Clock speeds** — SM and memory clocks as bar gauges
- **Trend graphs** — utilization, memory, temperature, and power over time

### Docker Containers (auto-provisioned)
A "Docker Containers" dashboard with:
- **Overview table** — all containers with CPU %, memory, and network I/O at a glance
- **Per-container detail** — select a container from the dropdown to see CPU, memory, and network graphs plus live logs

### Log Explorer
Open http://localhost:3000/a/grafana-lokiexplore-app to explore system and container logs.

## Commands

```bash
# Start the stack
docker compose up -d

# Stop the stack
docker compose down

# View logs
docker compose logs -f

# Restart after config changes
docker compose restart alloy
```

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Container definitions |
| `config.alloy` | Metrics and log collection config |
| `prom-config.yaml` | Prometheus settings |
| `loki-config.yaml` | Loki settings |
| `dashboards/` | Auto-provisioned Grafana dashboards |

## Customization

Edit `config.alloy` to:
- Add/remove metric collectors
- Change scrape intervals
- Modify log collection paths

After changes, run `docker compose restart alloy`.
