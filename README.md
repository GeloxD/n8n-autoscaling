# n8n Autoscaling System (n8n 2.0 ready)

A Docker-based autoscaling solution for n8n. Dynamically scales worker
containers based on Redis queue length. Fronted by your own npmplus
(Nginx Proxy Manager) instance - no Cloudflare Tunnel, no Tailscale, no
n8n Instance AI module.

## What changed in this update

Your previous build used a custom `node:20` image with `npm install -g n8n`
(no version pin) and the pre-2.0 internal task-runner wiring
(`N8N_TASK_BROKER_URL`, etc). n8n 2.0 requires task runners to run outside
the main process, so that old wiring silently stopped executing Code nodes
once n8n auto-updated past 2.0 on a rebuild.

This update:

- Switches to the official, version-**pinned** `n8nio/n8n` image
  (`N8N_VERSION` in `.env`) - no more silently floating to "latest".
- Uses n8n 2.0's **internal** task runner mode (the simpler of two options -
  runners spawn automatically inside each container, no sidecar containers).
- Adds Redis password authentication (previously open to anything that could
  reach the container).
- Removes the Caddy reverse proxy - your npmplus instance handles that now,
  reached over a shared external Docker network instead of exposed ports.
- Removes Cloudflare Tunnel and Tailscale entirely (upstream added these;
  you don't use either).
- No changes needed: `autoscaler/autoscaler.py` and
  `monitor/monitor_redis_queue.py` already work fine as-is against n8n 2.0 -
  they only talk to Redis and the Docker socket, not to n8n's internals.

**Not included** (deliberately, since you don't need them for a single-VPS
setup): the interactive setup wizard, systemd generator, and the scheduled
backup system from upstream. Happy to add any of these later if useful.

## Migration steps (existing instance with real data)

1. **Back up first.** Before touching anything:
   ```bash
   docker compose exec postgres pg_dump -U postgres -d n8n -F c -f /tmp/n8n-backup.dump
   docker cp <postgres_container>:/tmp/n8n-backup.dump ./n8n-backup.dump
   docker cp <n8n_container>:/n8n ./n8n_main_backup
   ```
2. Copy these updated files into your repo, replacing the old ones:
   `Dockerfile`, `docker-compose.yml`. Delete `caddy_config/` - it's no
   longer used.
3. **Do not regenerate `N8N_ENCRYPTION_KEY` or `N8N_USER_MANAGEMENT_JWT_SECRET`**
   if you have existing credentials/users - copy the exact values from your
   current `.env` into the new one, or your saved credentials become
   unreadable and users get logged out permanently.
4. Set a real `REDIS_PASSWORD` (new requirement) and a real
   `POSTGRES_PASSWORD` if you haven't already rotated the ones committed to
   your old `.env.example`.
5. Create the shared proxy network (one time):
   ```bash
   docker network create n8n-proxy
   ```
6. Attach your npmplus container to that same network in Portainer, and
   point its proxy host at `n8n:5678` (forward hostname `n8n`, port `5678`)
   instead of whatever Caddy/host-port setup you had before.
7. Rebuild and start:
   ```bash
   docker compose down
   docker compose build --no-cache
   docker compose up -d
   ```
8. Check logs, confirm workers pick up jobs and a Code node with Puppeteer
   still runs:
   ```bash
   docker compose logs -f n8n n8n-worker n8n-autoscaler
   ```

## Quick Start (fresh install)

1. Clone/copy this repo.
2. `cp .env.example .env` and fill in every `CHANGE_ME_*` value with your own
   generated secrets (e.g. `openssl rand -base64 32`).
3. `docker network create n8n-proxy`
4. Attach npmplus to that network and point a proxy host at `n8n:5678`
   (forward hostname `automate.corderocloud.com` -> `n8n:5678`).
5. `docker compose up -d --build`

## Key Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `N8N_VERSION` | Pinned n8n image tag - bump deliberately | `2.32.6` |
| `MIN_REPLICAS` | Minimum worker containers | `1` |
| `MAX_REPLICAS` | Maximum worker containers | `3` |
| `SCALE_UP_QUEUE_THRESHOLD` | Queue length to trigger scale up | `5` |
| `SCALE_DOWN_QUEUE_THRESHOLD` | Queue length to trigger scale down | `1` |
| `POLLING_INTERVAL_SECONDS` | How often to check queue length | `10` |
| `COOLDOWN_PERIOD_SECONDS` | Time between scaling actions | `10` |
| `REDIS_PASSWORD` | Redis auth (required now) | - |
| `PROXY_NETWORK_NAME` | External network shared with npmplus | `n8n-proxy` |

## Networking

- `n8n-internal`: private bridge network for n8n <-> postgres/redis/worker
  traffic. Nothing outside this compose project can reach it.
- `n8n-proxy` (external): only `n8n` and `n8n-webhook` join this. Your
  npmplus container joins it too, so it can reverse-proxy to `n8n:5678`
  without any port being published to the host.

No ports are published to the host at all in this setup - everything routes
through the shared Docker network and npmplus.

## Task Runners (internal mode)

n8n 2.0 requires Code node execution to happen in a task runner. This build
uses **internal mode**: `N8N_RUNNERS_ENABLED=true` and nothing else needed -
the runner is spawned as a child process inside each `n8n`/`n8n-worker`
container automatically. This is the simpler of the two supported modes.
n8n's own docs note internal mode shares uid/gid with the main process and
recommend **external mode** (a separate sidecar container per worker) for
stronger isolation in production/multi-tenant environments. For a
single-VPS personal/small-business setup, internal mode is fine - if you
later want the sidecar model, let me know and I can wire it up (it needs
the autoscaler to scale worker + runner pairs together).

## Adding Puppeteer / System Packages

The base image is now Alpine (`n8nio/n8n`), not Debian, so packages are
added via `apk` in the `Dockerfile`, not `apt`. To add more:

```dockerfile
RUN apk add --no-cache your-package-here
```

Then rebuild:
```bash
docker compose build --no-cache n8n n8n-worker n8n-webhook
docker compose up -d
```

## Scaling Behavior

Unchanged from before:
1. Autoscaler checks Redis queue length every `POLLING_INTERVAL_SECONDS`.
2. Scales up when queue length > `SCALE_UP_QUEUE_THRESHOLD` and replicas <
   `MAX_REPLICAS`.
3. Scales down when queue length < `SCALE_DOWN_QUEUE_THRESHOLD` and
   replicas > `MIN_REPLICAS`.
4. Respects `COOLDOWN_PERIOD_SECONDS` between scaling actions.

## Troubleshooting

```bash
# Container status
docker compose ps

# Logs
docker compose logs -f [service]

# Verify Redis auth works
docker compose exec redis redis-cli -a "$REDIS_PASSWORD" --no-auth-warning ping

# Check queue length manually
docker compose exec redis redis-cli -a "$REDIS_PASSWORD" --no-auth-warning LLEN bull:jobs:wait

# Confirm which n8n version is actually running
docker compose exec n8n n8n --version
```

## License

MIT License - See [LICENSE](LICENSE) for details.
