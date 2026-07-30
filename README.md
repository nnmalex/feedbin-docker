# Feedbin on Docker Compose

Self-hosted [Feedbin](https://github.com/feedbin/feedbin) behind [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/).

Feedbin itself is **built locally from source** (no third-party Feedbin images). Supporting services use upstream open-source images.

## Architecture

| Service | Image / build | Purpose |
|---|---|---|
| `web` | built from `feedbin/` | Rails app served by Pitchfork on port 8080 |
| `workers` | same image | Sidekiq background jobs (feed crawling, parsing, search indexing) |
| `clock` | same image | Clockwork scheduler (enqueues periodic jobs) |
| `extract` | built from `extract/` | Feedbin's Node.js full-content extraction service |
| `camo` | `ghcr.io/cactus/go-camo` | Camo-compatible HTTPS image proxy |
| `postgres` | `postgres:16-alpine` | Primary database |
| `redis` | `redis:7-alpine` | Sidekiq queues, cache, public IDs |
| `elasticsearch` | `elasticsearch:8.17.0` | Full-text search |
| `minio` | `minio/minio` | S3-compatible storage (favicons, images, newsletters) |
| `cloudflared` | `cloudflare/cloudflared` | Outbound tunnel to Cloudflare's edge |

Nothing is exposed to the internet directly — `cloudflared` makes an outbound connection to Cloudflare and proxies requests to `web:8080` over the compose network. The only published port is `127.0.0.1:8080` for local debugging.

## Setup

### 1. Configure

```sh
cp .env.example .env
```

Fill in `.env` — each secret has a generation command in the comments (`openssl rand -hex ...`). Set `FEEDBIN_HOST` to the hostname you'll serve Feedbin from.

### 2. Create the Cloudflare Tunnel

1. In [Cloudflare Zero Trust](https://one.dash.cloudflare.com/) → **Networks → Tunnels**, create a *cloudflared* tunnel and copy the token into `CLOUDFLARE_TUNNEL_TOKEN` in `.env`.
2. Add **Public Hostnames** to the tunnel (service type **HTTP** — TLS terminates at Cloudflare's edge; the tunnel talks plain HTTP to the containers):

   | Public hostname | Service |
   |---|---|
   | `feedbin.example.com` | `http://web:8080` |
   | `api.feedbin.example.com` | `http://web:8080` (optional, for API clients) |
   | `camo.example.com` | `http://camo:8080` (if using the image proxy) |

Because TLS is handled by Cloudflare, no certificates are needed anywhere in this stack. `FORCE_SSL=true` stays enabled: cloudflared forwards `X-Forwarded-Proto: https`, so Rails knows requests are secure and won't redirect-loop.

### 3. Build and start

```sh
docker compose build
docker compose up -d
```

The first build takes a while (full `bundle install` plus asset precompilation). On first boot, `web` runs `rails db:prepare` to create and load the schema before workers start.

Check on things with:

```sh
docker compose ps
docker compose logs -f web workers
```

### 4. Create your user

Feedbin has no open self-serve signup without Stripe configured. Provision your account with:

```sh
scripts/create-user.sh you@example.com your-password --admin
```

This seeds the `Plans` table if it's empty (needed once per fresh volume — see below) and creates the user on the `free` plan with no expiration — not `trial`, which has a 30-day `expires_at` that a periodic Sidekiq job (`TrialExpiration`, enqueued by `clock`) enforces by setting `suspended: true`. A suspended user gets locked out of the web UI on every login with no way to pay, since Stripe isn't configured. `free` has no expiry and that job never touches it. Safe to re-run: if the email already exists it repairs a nil/`trial` plan or a stuck `suspended` flag instead of erroring.

Then log in at `https://feedbin.example.com`.

> If you signed up through the web UI before running this and got a blank page after login, that's a `nil` plan from Plans not being seeded yet — `scripts/create-user.sh <same email> <anything>` will fix it in place (the password argument is ignored for existing users).

## Operations

**Update Feedbin** (rebuild from the pinned ref, then restart):

```sh
docker compose build --no-cache web
docker compose up -d
```

Pin `FEEDBIN_REF` / `EXTRACT_REF` in `.env` to a commit SHA or tag for reproducible builds; `master` builds whatever upstream currently has.

**Backups** — everything lives in the named volumes `postgres-data`, `redis-data`, `elasticsearch-data`, `minio-data`. The one that matters most is Postgres:

```sh
docker compose exec postgres pg_dump -U feedbin feedbin | gzip > feedbin-$(date +%F).sql.gz
```

Elasticsearch content can be rebuilt from Postgres; Redis holds queues and caches.

## Design notes

- **Shared hostname for Feedbin containers.** Feedbin routes some Sidekiq jobs to hostname-derived queues (`crawl_<hostname>`, `parse_<hostname>`, …) — a leftover of its multi-server crawler architecture. `web`, `workers`, and `clock` all set `hostname: feedbin` so the enqueuer and the worker agree on queue names. Don't remove this or those jobs will sit in queues nothing consumes.
- **Sidekiq config.** Workers run with the repo's `config/sidekiq-development.yml` — despite the name it's the only queue map the repo ships and lists every queue Feedbin uses.
- **MinIO instead of AWS S3.** Feedbin requires S3-compatible storage for favicons, extracted images, and newsletters. Credentials and endpoint are wired via the `AWS_*` variables. The `minio-init` one-shot container creates the `feedbin` bucket and enables anonymous downloads. If you want stored images/favicons publicly reachable, add another tunnel hostname (e.g. `files.example.com` → `http://minio:9000`).
- **Image proxy.** `go-camo` is URL-compatible with the original camo protocol Feedbin expects (`CAMO_HOST`/`CAMO_KEY`). It needs a public hostname through the tunnel since browsers fetch proxied images directly.
- **Extract stays internal.** Feedbin reaches it at `extract:3000` with an HMAC-signed URL; it doesn't need to be public.

## Troubleshooting

- **`web` unhealthy on first boot** — schema load + boot can be slow; the healthcheck allows 120 s. Check `docker compose logs web`.
- **Search not returning results** — confirm Elasticsearch is healthy (`docker compose exec elasticsearch curl -s localhost:9200/_cluster/health`), then check `workers` logs; entries are indexed by Sidekiq jobs.
- **Feeds not updating** — check `clock` (enqueues the refresh schedule) and `workers` logs.
- **Elasticsearch exits with code 137** — it's being OOM-killed; raise Docker's memory or lower `ES_JAVA_OPTS`.
- **Upstream changes** — Feedbin's maintainer explicitly warns that self-hosting takes real configuration effort, and master moves without release tags. If a build breaks, pin `FEEDBIN_REF` to a known-good commit.
- **Blank page after login, `NoMethodError: undefined method 'restricted?' for nil` in `web` logs** — the user's `plan_id` is nil. `db:prepare` only runs `db:seed` on the run that creates the database from scratch, so a Postgres volume that already existed from an earlier failed build attempt can end up with an empty `Plans` table, and signup silently assigns no plan. Fix with `scripts/create-user.sh <email> <anything>` (repairs an existing user in place).
- **Locked out after ~30 days, redirected to a billing page you can't submit** — the account is on the `trial` plan and `TrialExpiration` (a Sidekiq job the `clock` container enqueues periodically) suspended it once `expires_at` passed. Only happens to accounts created before this repo's `scripts/create-user.sh` existed, or ones provisioned outside it. Fix with `scripts/create-user.sh <email> <anything>` — it moves the account to `free`, clears `expires_at`, and un-suspends it.
