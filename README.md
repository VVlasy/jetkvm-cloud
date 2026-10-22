# jetkvm-cloud

Self-hosted [JetKVM](https://jetkvm.com) cloud on Kubernetes: `cloud-api` (Node/Express/Prisma),
the web UI from `jetkvm/kvm` served by nginx, and an optional single-node PostgreSQL.

Upstream ships only a `compose.yaml`. This repo adds:

| Path | What |
|---|---|
| `build/cloud-api/` | Dockerfile: pinned `jetkvm/cloud-api` commit on Node 22.23.4 |
| `build/cloud-ui/` | Dockerfile: `jetkvm/kvm` `ui/` built in cloud mode, served by nginx; API URL set at container start |
| `charts/jetkvm-cloud/` | Helm chart |
| `values-vvlasy.yaml` | Values matching the existing `jetkvm` namespace |
| `adopt.sh` | Labels the hand-rolled resources so Helm takes them over |
| `.github/workflows/build-images.yml` | Builds and pushes both images to ghcr.io |

## Why not the init-container clone

The previous manifests cloned upstream `main` and ran `npm install` on every pod start, on Node 21
(EOL June 2024), and never ran Prisma migrations. Any restart was an unreviewed upgrade. Here the
upstream ref is a build arg, the image is immutable, migrations run before the API starts, and the
UI tracks the firmware release line (`release/0.5.9`).

## Images

```bash
# cloud-api, pinned commit (default = main @ 2026-10-21, d08418e)
docker build build/cloud-api -t ghcr.io/vvlasy/jetkvm-cloud-api:d08418e \
  --build-arg CLOUD_API_REF=d08418e650b6a03c17dbdc90bbd7cde2b105c7f2

# cloud-ui, tracks the kvm release line your devices run
docker build build/cloud-ui -t ghcr.io/vvlasy/jetkvm-cloud-ui:0.5.9 \
  --build-arg KVM_REF=release/0.5.9
```

Or push this repo to GitHub and run the `Build images` workflow (`workflow_dispatch` takes the refs).
Make both packages visible to the cluster, or add an `imagePullSecrets` entry.

The UI image bakes in a placeholder API URL; `/docker-entrypoint.d/40-cloud-api-url.sh` replaces it
with `CLOUD_API_URL` at start, so one image serves any hostname. Pass `--build-arg VITE_CLOUD_API=…`
to bake a real URL instead.

## Fresh install

```bash
helm upgrade --install jetkvm charts/jetkvm-cloud -n jetkvm --create-namespace \
  --set api.config.API_HOSTNAME=https://api.jetkvm.example.com \
  --set api.config.APP_HOSTNAME=https://jetkvm.example.com \
  --set api.config.CORS_ORIGINS=https://jetkvm.example.com \
  --set api.secret.GOOGLE_CLIENT_ID=… \
  --set api.secret.GOOGLE_CLIENT_SECRET=… \
  --set api.secret.COOKIE_SECRET="$(openssl rand -hex 32)" \
  --set postgres.auth.password="$(openssl rand -hex 24)" \
  --set api.ingress.enabled=true --set api.ingress.host=api.jetkvm.example.com \
  --set ui.ingress.enabled=true --set ui.ingress.host=jetkvm.example.com
```

Register `https://api.jetkvm.example.com/oidc/callback` as the OAuth redirect URI in Google Cloud.

`helm lint charts/jetkvm-cloud -f values-vvlasy.yaml` and `helm template … | kubeconform -strict`
are worth running before the first apply; this chart was written without a `helm` binary at hand.

## Adopting the existing `jetkvm` namespace

The live resources are named `cloud-api`, `cloud-ui`, `postgres`, use selector `app=<name>`, and
the StatefulSet claims volume `data` (5Gi, longhorn, RWO). `values-vvlasy.yaml` reproduces exactly
that, and keeps the existing Secrets (`cloud-api`, `postgres`) untouched, so nothing is recreated:

```bash
# 0. backup
kubectl -n jetkvm exec postgres-0 -- sh -c 'pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' > jetkvm-$(date +%F).sql

# 1. make sure the two images exist in ghcr and are pullable from the cluster

# 2. hand ownership to Helm (labels + annotations only, no restarts)
./adopt.sh jetkvm jetkvm

# 3. see what would change
helm diff upgrade jetkvm charts/jetkvm-cloud -n jetkvm -f values-vvlasy.yaml   # helm-diff plugin
#   or: helm template jetkvm charts/jetkvm-cloud -n jetkvm -f values-vvlasy.yaml > rendered.yaml

# 4. apply (from the checkout, or from the packaged chart in dist/)
helm upgrade --install jetkvm charts/jetkvm-cloud -n jetkvm -f values-vvlasy.yaml
#   helm upgrade --install jetkvm https://raw.githubusercontent.com/VVlasy/jetkvm-cloud/main/dist/jetkvm-cloud-0.1.0.tgz -n jetkvm -f values-vvlasy.yaml

# 5. watch the migration, then the API
kubectl -n jetkvm logs deploy/cloud-api -c migrate -f
kubectl -n jetkvm rollout status deploy/cloud-api deploy/cloud-ui
```

What the upgrade does on first apply:

- `cloud-api`: replaces the Node 21 clone-and-build pod with the image; the `migrate` init container
  applies `20260427143200_add_release_artifacts` (the running code already contains it; the DB does
  not). Expect one API restart (strategy `Recreate`).
- `cloud-ui`: rolls to the 0.5.9 build. The old `cloud-ui-nginx` ConfigMap is no longer mounted and
  can be deleted afterwards (`kubectl -n jetkvm delete configmap cloud-ui-nginx`).
- `REAL_IP_HEADER` changes from `X-Real-IP` to `x-real-ip`. The API looks the header up by exact
  name in Node's lowercased header map, so the old value never matched and device IPs were logged
  as Traefik's pod IP.
- `postgres`: pod template changes (probes read the user from env, resource requests), so the
  StatefulSet rolls `postgres-0` once. The PVC `data-postgres-0` is reused. The
  `volumeClaimTemplates` block is immutable; if the apply is rejected on that field, the live
  template differs from `values-vvlasy.yaml` and the values must be corrected, not the StatefulSet.

The old `cloud-api` Secret still contains config keys (`API_HOSTNAME`, `CORS_ORIGINS`, …). The chart
loads its ConfigMap after the Secret, so the ConfigMap values win. Once things run, you can trim the
Secret down to real secrets (`DATABASE_URL`, `GOOGLE_CLIENT_*`, `COOKIE_SECRET`, …) or move to chart-
managed secrets by removing `existingSecret` and filling `api.secret`.

Rollback: `helm rollback jetkvm 0` restores the pre-Helm manifests only if Helm recorded them, which
it does not for adopted resources. Keep `kubectl -n jetkvm get deploy,sts,svc,ing -o yaml` from
before the upgrade.

## Upgrading later

- API: change `api.image.tag` (and build the image for the new `CLOUD_API_REF`). Migrations run
  automatically.
- UI: change `ui.image.tag` to the firmware release line you flash to devices.
- `CLOUD_ENABLE_VERSIONED_UI` (0.5.9+) lets one cloud UI serve several device versions from a CDN;
  it is off in this build, so keep UI and firmware on the same release line.

## Values

See `charts/jetkvm-cloud/values.yaml`; every key is commented. The main switches:

| Key | Purpose |
|---|---|
| `api.config.*` | non-secret env → ConfigMap |
| `api.secret.*` / `api.existingSecret` | secret env → chart Secret, or a Secret you manage |
| `api.migrations.enabled` | `prisma migrate deploy` init container |
| `ui.cloudApiUrl` | API URL for the browser; defaults to `api.config.API_HOSTNAME` |
| `ui.nginxConfig` | override the nginx server block |
| `postgres.enabled` | in-chart PostgreSQL; off = bring your own `DATABASE_URL` |
| `*.name` | fixed resource names (used for adoption) |
