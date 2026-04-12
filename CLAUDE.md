# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Production-grade, single-node local AI infrastructure stack. Combines an LLM gateway (LiteLLM), LLM observability (Langfuse), and full hardware/container monitoring (Prometheus, Loki, Grafana, Alloy, DCGM). Model containers (vLLM, SGLang) are deployed separately and registered dynamically.

## Commands

```bash
docker network create model-net  # One-time: create the shared model network
docker compose up -d             # Start the stack
docker compose down              # Stop the stack
docker compose restart alloy     # Restart Alloy after config changes
docker compose logs -f           # Tail all logs
```

There is no build step, linter, or test suite — this is a configuration-only repo.

## Architecture

```
Host OS (Ubuntu)
  │
  ├── LiteLLM (:4000) — AI gateway (auth, routing, rate limits, load balancing)
  │     ├── Postgres — backing DB (teams, keys, model registry)
  │     ├── callbacks → Langfuse (LLM traces) + Prometheus (metrics)
  │     └── routes to model containers on model-net
  │
  ├── Langfuse (:3001) — LLM observability (traces, token usage, cost)
  │     ├── Postgres — metadata storage (shared instance, separate DB)
  │     ├── ClickHouse — analytics/trace storage
  │     └── Redis — cache/queue
  │
  ├── Alloy (grafana/alloy) — collects metrics + logs
  │     ├── prometheus.exporter.unix → scrape → prometheus.remote_write → Prometheus:9090
  │     ├── loki.source.journal ──→ loki.write → Loki:3100
  │     ├── loki.source.file ────→ loki.write → Loki:3100
  │     ├── loki.source.docker ──→ loki.write → Loki:3100  (container logs)
  │     ├── prometheus.exporter.cadvisor → scrape → prometheus.remote_write → Prometheus:9090  (container metrics)
  │     ├── prometheus.scrape (dcgm-exporter:9400) → prometheus.remote_write → Prometheus:9090  (GPU metrics)
  │     ├── prometheus.scrape (litellm:4000) → prometheus.remote_write → Prometheus:9090  (gateway metrics)
  │     └── discovery.file (model_targets.json) → prometheus.scrape → prometheus.remote_write → Prometheus:9090  (model metrics)
  │
  ├── DCGM Exporter (:9400) — NVIDIA GPU metrics (requires nvidia-container-toolkit)
  ├── Prometheus (:9090) — metrics storage
  ├── Loki (:3100) — log storage
  ├── Grafana (:3000) — dashboards (auto-provisioned)
  │
  └── [model-net] ← external Docker network
        ├── vLLM containers (deployed separately)
        └── SGLang containers (deployed separately)
```

## Networks

- **ai-internal** — all infrastructure services communicate here
- **model-net** (external) — shared network between LiteLLM/Alloy/Prometheus and model containers. Must be created before first run: `docker network create model-net`

## Key Config Relationships

- **docker-compose.yml** — defines all services. Alloy runs `privileged: true` with `pid: host` and mounts the host root at `/host:ro,rslave` so node_exporter collectors can read host-level metrics.
- **config.alloy** — Alloy pipeline config (River syntax). Collects host metrics, container logs/metrics, GPU metrics, LiteLLM gateway metrics, and model endpoint metrics via file-based service discovery.
- **litellm-config.yaml** — LiteLLM gateway settings only (callbacks, timeouts). No model list — models are stored in Postgres and managed via the `/model/new` API at runtime.
- **model_targets.json** — file-based service discovery for model endpoints. Add model container addresses here for Alloy to scrape their `/metrics`. Format: `[{"targets": ["host:port"], "labels": {"model": "name", "backend": "vllm"}}]`
- **init-multi-db.sh** — creates additional Postgres databases (langfuse) on first startup. Runs via Docker entrypoint init.
- **prom-config.yaml** — minimal Prometheus config; Alloy pushes via remote write.
- **loki-config.yaml** — single-instance Loki with TSDB + filesystem storage.
- **.env.example** — all configurable environment variables with defaults. Copy to `.env` before deploying.
- **dashboards/** — auto-provisioned Grafana dashboards: `hardware-overview.json`, `docker-containers.json`, `gpu-overview.json`.

## Dynamic Model Management

Models are NOT in the compose file. Deploy them separately and register via LiteLLM API:

```bash
# Start a model container on the shared network
docker run -d --name vllm-llama70b --network model-net --gpus '"device=0"' \
  vllm/vllm-openai --model meta-llama/Llama-3.1-70B-Instruct --port 8000

# Register it in LiteLLM
curl -X POST http://localhost:4000/model/new \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model_name": "llama-70b", "litellm_params": {"model": "openai/meta-llama/Llama-3.1-70B-Instruct", "api_base": "http://vllm-llama70b:8000/v1"}}'

# Add to model_targets.json for metrics scraping
# [{"targets": ["vllm-llama70b:8000"], "labels": {"model": "llama-70b", "backend": "vllm"}}]
```

## Deployment Notes

- Target: Ubuntu 20.04+ with Docker and nvidia-container-toolkit installed
- Image versions are parameterized via environment variables with defaults in docker-compose.yml
- Grafana has anonymous admin enabled (no login) — suitable for internal/trusted networks only
- One shared Postgres instance with separate databases for LiteLLM and Langfuse
- Langfuse v3 uses ClickHouse for analytics and Redis for caching
