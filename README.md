# Local AI Infrastructure

A complete, production-ready stack for serving LLMs on your own hardware. One `docker compose up -d` gives you an OpenAI-compatible API gateway, per-team auth and rate limiting, full request tracing, cost tracking, GPU monitoring, and pre-built dashboards — all self-hosted, no cloud dependencies.

Models are deployed separately, registered at runtime through an API, and can be added, removed, or scaled across GPUs without restarting any infrastructure.

## Architecture

```
                    ┌─────────────────────────────┐
                    │      Internal Products       │
                    │     (OpenAI-compatible)       │
                    └──────────────┬───────────────┘
                                   │
                    ┌──────────────▼───────────────┐
                    │     LiteLLM Gateway (:4000)   │
                    │  Auth · Routing · Rate Limits  │
                    │  Load Balancing · Callbacks     │
                    └──┬──────────────────────┬─────┘
                       │                      │
          ┌────────────▼────┐      ┌──────────▼──────────┐
          │  model-net       │      │  Langfuse (:3001)    │
          │  ┌────────────┐  │      │  Traces · Usage      │
          │  │ vLLM GPU 0 │  │      │  Cost · Per-team     │
          │  └────────────┘  │      └──────────────────────┘
          │  ┌────────────┐  │
          │  │ vLLM GPU 1 │  │      ┌──────────────────────┐
          │  └────────────┘  │      │  Grafana (:3000)      │
          │  ┌────────────┐  │      │  Hardware · GPU · LLM  │
          │  │ SGLang     │  │      │  Container dashboards  │
          │  └────────────┘  │      └──────────────────────┘
          └──────────────────┘               ▲
                                             │
          ┌──────────────────────────────────┘
          │  Alloy → Prometheus (metrics)
          │  Alloy → Loki (logs)
          │  DCGM Exporter (GPU metrics)
          └──────────────────────────────────
```

## What This Gives You

**AI Gateway** — LiteLLM provides an OpenAI-compatible API (`/v1/chat/completions`) that routes to any number of local models. Models are registered dynamically via API — no config file changes, no restarts. Built-in load balancing across multiple instances of the same model.

**Access Control** — Per-team API keys with rate limits (requests/min, tokens/min) and budget caps. Each team's usage is tracked and attributable.

**LLM Observability** — Langfuse captures every request as a structured trace: prompt, response, token counts, latency, cost, which API key was used. This is the layer you show leadership when they ask what the infrastructure is being used for.

**Hardware Monitoring** — CPU, memory, disk, network, system logs, Docker container metrics, and NVIDIA GPU metrics (utilization, memory, temperature, power, clocks). Pre-built Grafana dashboards for all of it.

**Operational Logs** — Loki collects raw logs from every container. When vLLM OOMs at 3am, the crash dump is in Loki. Langfuse tells you about usage; Loki tells you about failures.

**LLM Gateway Metrics** — Request rate, latency percentiles, token throughput, error rates, per-team and per-key breakdowns — all in Prometheus with a pre-built Grafana dashboard.

## Services

The stack runs 12 containers:

| Service | Port | Role |
|---------|------|------|
| **LiteLLM** | 4000 | API gateway — routing, auth, rate limits, load balancing |
| **Langfuse Web** | 3001 | LLM observability UI — traces, usage, cost |
| **Langfuse Worker** | 3030 | Background trace processing |
| **Grafana** | 3000 | Dashboards (anonymous admin, no login) |
| **Prometheus** | 9090 | Metrics storage |
| **Loki** | 3100 | Log aggregation |
| **Alloy** | 12345 | Metrics + log collection agent |
| **DCGM Exporter** | 9400 | NVIDIA GPU metrics |
| **Postgres** | 5432 | Database (LiteLLM + Langfuse) |
| **ClickHouse** | 8123 | Langfuse analytics engine |
| **Redis** | 6379 | Langfuse cache and job queue |
| **MinIO** | 9000 | S3-compatible blob storage (Langfuse traces) |

Model containers (vLLM, SGLang) are **not** part of this stack. They are deployed separately and join the shared `model-net` Docker network.

## Requirements

- Ubuntu 20.04+ (or similar Linux with systemd)
- Docker and Docker Compose v2
- NVIDIA drivers + [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)

## Quick Start

```bash
# Clone
git clone https://github.com/SohaibTaqat/local-ai-infrastructure.git
cd local-ai-infrastructure

# Create the shared network for model containers (one-time)
docker network create model-net

# Configure
cp .env.example .env
# Edit .env — at minimum change passwords and secrets

# Start
docker compose up -d
```

## Verify

```bash
curl http://localhost:4000/health/liveliness    # LiteLLM  → "I'm alive!"
curl http://localhost:3001/api/public/health     # Langfuse → {"status":"OK"}
curl http://localhost:3100/ready                 # Loki     → ready
curl http://localhost:3000/api/health            # Grafana  → {"database":"ok"}
```

## Deploy a Model

Models run on the `model-net` network, separate from infrastructure:

```bash
# 1. Start a model
docker run -d \
  --name vllm-qwen \
  --network model-net \
  --gpus '"device=0"' \
  vllm/vllm-openai \
  --model Qwen/Qwen2.5-7B-Instruct \
  --port 8000

# 2. Register it in LiteLLM (no restart needed)
curl -X POST http://localhost:4000/model/new \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model_name": "qwen-7b",
    "litellm_params": {
      "model": "openai/Qwen/Qwen2.5-7B-Instruct",
      "api_base": "http://vllm-qwen:8000/v1"
    }
  }'

# 3. Add to metrics scraping (edit model_targets.json)
# [{"targets": ["vllm-qwen:8000"], "labels": {"model": "qwen-7b", "backend": "vllm"}}]

# 4. Send a request
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "qwen-7b", "messages": [{"role": "user", "content": "Hello"}]}'
```

## Teams and API Keys

```bash
# Create a team
curl -X POST http://localhost:4000/team/new \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"team_alias": "backend-team"}'

# Generate an API key for that team (use team_id from response above)
curl -X POST http://localhost:4000/key/generate \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"team_id": "<team_id>", "key_alias": "backend-prod", "tpm_limit": 10000}'
```

Teams and keys can also be managed through the LiteLLM Admin UI at `http://localhost:4000/ui`.

## Load Balancing

Register the same `model_name` with multiple backends — LiteLLM routes across them automatically:

```bash
curl -X POST http://localhost:4000/model/new \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model_name": "llama-70b", "litellm_params": {"model": "openai/meta-llama/Llama-3.1-70B-Instruct", "api_base": "http://vllm-llama-gpu0:8000/v1"}}'

curl -X POST http://localhost:4000/model/new \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model_name": "llama-70b", "litellm_params": {"model": "openai/meta-llama/Llama-3.1-70B-Instruct", "api_base": "http://vllm-llama-gpu1:8000/v1"}}'
```

## Dashboards

Four auto-provisioned Grafana dashboards at `http://localhost:3000`:

| Dashboard | What it shows |
|-----------|--------------|
| **Hardware Overview** | CPU (per-core), memory, swap, disk I/O, network, load average |
| **GPU Overview** | Per-GPU utilization, memory, temperature, power, clock speeds |
| **Docker Containers** | Per-container CPU, memory, network + live logs |
| **LLM Gateway** | Request rate, latency, failure rate, tokens, per-team/key breakdown |

## Network Architecture

Two Docker networks isolate infrastructure from models:

- **ai-internal** — all infrastructure services communicate here. Managed by Docker Compose.
- **model-net** — shared between LiteLLM, Alloy, Prometheus, and model containers. Created manually, persists independently of `docker compose down`.

This means you can tear down and rebuild the entire infrastructure stack without disconnecting running models.

## File Layout

| File | Purpose |
|------|---------|
| `docker-compose.yml` | All 12 service definitions |
| `.env.example` | Environment variables — copy to `.env` and customize |
| `config.alloy` | Alloy pipeline — host metrics, container logs, GPU metrics, LiteLLM metrics, model endpoint discovery |
| `litellm-config.yaml` | Gateway settings — Prometheus + Langfuse callbacks, timeouts. No model list (models are in DB) |
| `model_targets.json` | File-based service discovery for model `/metrics` endpoints. Alloy picks up changes automatically |
| `prom-config.yaml` | Prometheus config (minimal — Alloy pushes via remote write) |
| `loki-config.yaml` | Loki storage config (TSDB + filesystem) |
| `init-multi-db.sh` | Creates the `langfuse` database alongside `litellm` in shared Postgres on first run |
| `dashboards/` | Auto-provisioned Grafana dashboard JSON files |

## Common Operations

```bash
docker compose up -d                # Start the stack
docker compose down                 # Stop (preserves data)
docker compose down -v              # Stop and delete all data
docker compose restart alloy        # Apply config.alloy changes
docker compose logs -f litellm      # Tail a specific service
docker compose ps                   # Check service status
```

## Web UIs

| URL | What |
|-----|------|
| `http://localhost:3000` | Grafana — all dashboards |
| `http://localhost:3001` | Langfuse — traces, usage, cost |
| `http://localhost:4000/ui` | LiteLLM Admin — models, keys, teams |
| `http://localhost:12345` | Alloy — pipeline debug UI |

## License

MIT
