# opencode-v2-containerized

Unofficial container image of [opencode v2](https://github.com/anomalyco/opencode/tree/v2)
(`anomalyco/opencode`, branch `v2`), automatically rebuilt on every new v2 release
and published on Docker Hub as **`guarnacciaa/opencode-v2`**.

Since upstream does not release a container image for v2, this pipeline:
1. resolves the newest `2.x` version from the npm registry `@opencode/cli-linux-x64`
   (same source used by the official script `https://opencode.ai/v2/install`),
2. multi-arch builds (`linux/amd64`, `linux/arm64`) the `Dockerfile` in this repo,
3. pushes to Docker Hub only if the tag does not exist yet (unless `force`).

Reference version source: branch [`v2`](https://github.com/anomalyco/opencode/tree/v2)
of the `anomalyco/opencode` repo (tags `v2.0.x`, currently newest `2.0.29`).

## Published tags

| Tag | Meaning |
|---|---|
| `guarnacciaa/opencode-v2:2.0.29` | exact version |
| `guarnacciaa/opencode-v2:2.0` | newest `2.0.x` |
| `guarnacciaa/opencode-v2:2` | newest `2.x` |
| `guarnacciaa/opencode-v2:v2` | v2 branch alias |
| `guarnacciaa/opencode-v2:latest` | newest built v2 |

## Usage — web UI (`opencode serve`)

The default command is `serve`, with `--hostname`/`--port` taken from the
environment (explicit flags always win). Easiest path with compose:

```bash
cp .env.example .env   # then set OPENCODE_SERVER_PASSWORD
docker compose -f docker-compose.example.yml up -d
# open http://localhost:4096
```

Or plain docker:

```bash
docker run -d --name opencode-v2 -p 4096:4096 \
  -v "$PWD:/workspace" \
  -e OPENCODE_SERVER_PASSWORD=secret \
  guarnacciaa/opencode-v2:latest
```

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `OPENCODE_SERVER_PASSWORD` | *(none → random per start)* | Web UI password (username is always `opencode` in v2). **Set this.** |
| `OPENCODE_HOSTNAME` | `0.0.0.0` | Bind address. Keep `0.0.0.0` or the UI is unreachable from outside the container (upstream default `127.0.0.1`). |
| `OPENCODE_PORT` | `4096` | Port **inside** the container. |
| `HOST_PORT` | `4096` | Port published **on your machine** (compose only). |
| `WORKSPACE_DIR` | `.` | Local directory mounted as `/workspace`, the project the UI works on (compose only). |
| `IMAGE` | `guarnacciaa/opencode-v2:latest` | Image to run; pin e.g. `:2.0.29` for stability (compose only). |
| `TZ` | `Etc/UTC` | Timezone for logs. |
| `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` | *(empty)* | Optional provider keys; also configurable later from the UI/`opencode.json`. |

Custom port example (env-driven, no hardcoded values):
`docker run -p 8080:8080 -e OPENCODE_PORT=8080 ... :latest`
(also set `OPENCODE_PORT=8080` so the healthcheck follows it).
Explicit flags still work and take precedence:
`... :latest serve --hostname 0.0.0.0 --port 8080`.
CLI/TUI remain available by overriding the command:
`docker run --rm -it -v "$PWD:/workspace" ... :latest --version`,
or attach a TUI to a running server: `opencode attach http://localhost:4096`.

Notes:
- `/workspace` is the served project directory: mount your code there.
- Without `OPENCODE_SERVER_PASSWORD` (or `OPENCODE_PASSWORD`) the server
  generates a random password on every start — check `docker logs opencode-v2`.

## Pipeline

Workflow [docker-publish.yml](.github/workflows/docker-publish.yml):

- `schedule: 0 6 * * *` (daily) → resolve + build + push if the tag is missing
- `push to main` (when `Dockerfile`, `scripts/`, workflow change) → rebuild with newest v2
- `workflow_dispatch` → manual build, with `version` input (e.g. `2.0.29`, empty = newest)
  and `force` (`true` = rebuild even if the tag already exists)

The `check` job queries `https://hub.docker.com/v2/repositories/<IMAGE_NAME>/tags/<ver>/`
and skips the build if the tag already exists (saves CI minutes and useless pushes).

## Required setup (one time)

1. Fork (or clone) this repo.
2. If you forked, point the pipeline at your Docker Hub repo: in
   `.github/workflows/docker-publish.yml` set `env.IMAGE_NAME`
   (e.g. `myuser/opencode-v2`). Labels and the tag-existence check follow
   `IMAGE_NAME` and your repo automatically — no other file needs editing.
   Also point `IMAGE` in your `.env` at your image.
3. On Docker Hub create an **Access Token**:
   Account Settings → Security → New Access Token (Read/Write permissions).
4. In **your** repo on GitHub:
   Settings → Secrets and variables → Actions → New repository secret:
   - `DOCKERHUB_USERNAME` = your Docker Hub username
   - `DOCKERHUB_TOKEN` = the token created above
5. Push to `main`: the first push builds the newest v2 available at that
   time, then the schedule keeps it updated daily.

Check secrets locally (never commit them):
```bash
gh secret list  # requires authenticated gh
```

## Local build

```bash
# auto-detected newest v2
docker build -t opencode-v2:local .
# exact version
docker build --build-arg OPENCODE_VERSION=2.0.29 -t opencode-v2:2.0.29 .
docker run --rm opencode-v2:2.0.29 --version

# newest known v2 without building
./scripts/resolve-latest-v2.sh
```

Multi-arch (requires buildx):
```bash
docker buildx build --platform linux/amd64,linux/arm64 \
  --build-arg OPENCODE_VERSION=latest -t opencode-v2:dev --load .
```

## How the image is built

`Dockerfile` (base `debian:bookworm-slim`):
- installs `ca-certificates curl jq tar git openssh-client ripgrep`,
- maps `TARGETARCH` (`amd64`/`arm64`) → npm target (`x64`/`arm64`),
- if `OPENCODE_VERSION` is `latest`/`v2`/`2`/empty, resolves the newest `2.x` via
  `https://registry.npmjs.org/@opencode/cli-linux-x64` (with fallback to the
  legacy `@opencode-ai` scope for old 2.x),
- downloads `cli-linux-<arch>-<ver>.tgz`, extracts `package/bin/opencode` to
  `/usr/local/bin/opencode` (+ `opencode2` symlink, like the official script),
- creates non-root user `opencode`, `WORKDIR /workspace`,
  `ENTRYPOINT ["docker-entrypoint.sh"]` with default `CMD ["serve"]`: the
  entrypoint fills `--hostname`/`--port` from `OPENCODE_HOSTNAME`/`OPENCODE_PORT`
  (explicit flags win), warns if no server password is set,
  `EXPOSE 4096` and a TCP `HEALTHCHECK` on `${OPENCODE_PORT:-4096}`.

No source build (`bun install` + `build.ts`): it would be slow and fragile in CI;
the npm binary is the official release artifact. A `node` base image would only
add size (~80 MB vs ~28 MB for debian slim) since the binary is standalone and
does not run on Node.

## Disclaimer

Project not affiliated with the opencode team. `opencode` is a trademark of its respective owners.
