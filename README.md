# Local AI Infrastructure

Production-grade, single-node local AI serving infrastructure. Deploy models with vLLM/SGLang, route requests through LiteLLM, track usage with Langfuse, and monitor everything with Grafana.

## Services

| Service | Port | Purpose |
|---------|------|---------|
| LiteLLM | 4000 | AI gateway — routing, auth, rate limits, load balancing |
| Langfuse | 3001 | LLM observability — traces, token usage, cost tracking |
| Grafana | 3000 | Dashboards (no login required) |
| Prometheus | 9090 | Metrics storage |
| Loki | 3100 | Log storage |
| Alloy | 12345 | Metrics + log collector |
| DCGM Exporter | 9400 | NVIDIA GPU metrics |
| Postgres | 5432 | Database for LiteLLM + Langfuse |
| ClickHouse | 8123 | Langfuse analytics storage |
| Redis | 6379 | Langfuse cache/queue |
| MinIO | 9000 | S3-compatible blob storage for Langfuse |

## Requirements

- Ubuntu 20.04+ with Docker and Docker Compose
- NVIDIA Container Toolkit (for GPU monitoring + model serving)

## Quick Start

```bash
git clone https://github.com/SohaibTaqat/local-ai-infrastructure.git
cd local-ai-infrastructure

# Create the external network for model containers
docker network create model-net

# Configure environment
cp .env.example .env
# Edit .env — change passwords, secrets, and Langfuse init settings

# Start the stack
docker compose up -d
```

## Deploy a Model

Models run separately on the `model-net` network:

```bash
# Start a vLLM container
docker run -d \
  --name vllm-qwen \
  --network model-net \
  --gpus '"device=0"' \
  vllm/vllm-openai \
  --model Qwen/Qwen2.5-7B-Instruct \
  --port 8000

# Register it in LiteLLM (no restart needed)
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

# Add to metrics scraping (edit model_targets.json)
# [{"targets": ["vllm-qwen:8000"], "labels": {"model": "qwen-7b", "backend": "vllm"}}]
```

## Send a Request

```bash
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen-7b",
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

## Teams and API Keys

```bash
# Create a team
curl -X POST http://localhost:4000/team/new \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"team_alias": "backend-team"}'

# Create an API key for that team
curl -X POST http://localhost:4000/key/generate \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"team_id": "<team_id>", "key_alias": "backend-prod"}'
```

## Load Balancing

Register the same model name with multiple backends:

```bash
# GPU 0
curl -X POST http://localhost:4000/model/new \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model_name": "llama-70b",
    "litellm_params": {
      "model": "openai/meta-llama/Llama-3.1-70B-Instruct",
      "api_base": "http://vllm-llama-gpu0:8000/v1"
    }
  }'

# GPU 1 — same model_name, different backend
curl -X POST http://localhost:4000/model/new \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model_name": "llama-70b",
    "litellm_params": {
      "model": "openai/meta-llama/Llama-3.1-70B-Instruct",
      "api_base": "http://vllm-llama-gpu1:8000/v1"
    }
  }'
```

LiteLLM routes across them automatically.

## Dashboards

| Dashboard | Content |
|-----------|---------|
| Hardware Overview | CPU, memory, disk, network, load |
| GPU Overview | Utilization, memory, temperature, power per GPU |
| Docker Containers | Per-container CPU, memory, network + logs |
| LLM Gateway | Request rate, latency, tokens, per-team/key breakdown |

## Commands

```bash
docker compose up -d              # Start
docker compose down               # Stop
docker compose down -v            # Stop + delete all data
docker compose restart alloy      # Restart after config changes
docker compose logs -f            # Tail all logs
docker compose logs -f litellm    # Tail specific service
```

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | All service definitions |
| `.env.example` | Environment variables template |
| `config.alloy` | Metrics and log collection pipeline |
| `litellm-config.yaml` | LiteLLM gateway settings (callbacks, timeouts) |
| `model_targets.json` | Model endpoints for metrics scraping |
| `prom-config.yaml` | Prometheus settings |
| `loki-config.yaml` | Loki settings |
| `init-multi-db.sh` | Creates Langfuse database on first Postgres startup |
| `dashboards/` | Auto-provisioned Grafana dashboards |

## Verify

```bash
curl http://localhost:4000/health/liveliness   # LiteLLM
curl http://localhost:3001/api/public/health    # Langfuse
curl http://localhost:3100/ready               # Loki
curl http://localhost:3000/api/health           # Grafana
```
