# Deploy SynchronAIse on local k3s (Rancher Desktop)

One-command deploy for the audit backend into the **hackathon** namespace on the Rancher Desktop k3s cluster.

## Prerequisites

1. **Rancher Desktop** running with Kubernetes enabled.
2. **rancher-hackathon-paris bootstrap** — run `init.bat` from that repo **once** on this machine. It sets up:
   - kubectl context `rancher-desktop`
   - namespace `hackathon`
   - image-pull secret `application-collection` (for `dp.apps.rancher.io`)
   - `helm` / container engine login to the Application Collection registry
3. **CLI tools** in `PATH`: `kubectl`, `helm`, and either `nerdctl` (containerd, default) or `docker` (dockerd).

## Quick start

From the repo root:

```powershell
# Windows (PowerShell)
.\deploy\deploy.ps1
```

```bash
# macOS / Linux / Git Bash
chmod +x deploy/deploy.sh
./deploy/deploy.sh
```

The script will:

1. Verify kubectl context is `rancher-desktop`
2. Verify `application-collection` secret exists in `hackathon`
3. Build `synchronaise-backend:dev` into the k3s image store
4. Run `helm upgrade --install synchronaise ./deploy/helm/synchronaise --namespace hackathon`

Then forward the service locally:

```bash
kubectl port-forward -n hackathon svc/synchronaise 8080:8080
```

Health check:

```bash
curl http://localhost:8080/healthz
```

## LLM / VLM secrets

The Helm chart mounts a Kubernetes secret named `synchronaise-llm` for provider API keys. Variable names match `backend/.env.example`:

| Key | Purpose |
|-----|---------|
| `LLM_PROVIDER` | `gemini` or `openai` |
| `GEMINI_API_KEY` | Google Gemini API key |
| `GEMINI_MODEL` | e.g. `gemini-2.0-flash` |
| `OPENAI_API_KEY` | OpenAI API key |
| `OPENAI_MODEL` | e.g. `gpt-4o-mini` |

**Option A — create the secret manually (recommended for local dev):**

```bash
cp backend/.env.example backend/.env
# edit backend/.env — leave keys empty for mock mode

kubectl create secret generic synchronaise-llm \
  --from-env-file=backend/.env \
  -n hackathon
```

**Option B — let Helm create the secret:**

```bash
helm upgrade --install synchronaise ./deploy/helm/synchronaise \
  --namespace hackathon \
  --set global.imagePullSecrets={application-collection} \
  --set secret.create=true \
  --set secret.data.GEMINI_API_KEY=your-key-here
```

> Never commit real keys. `backend/.env` is gitignored.

With empty API keys the backend runs in **mock mode** and serves the frozen demo audit payload.

## Image build details

Rancher Desktop can use **containerd** (default) or **dockerd**:

| Engine | Build command (run by deploy scripts) |
|--------|---------------------------------------|
| containerd | `nerdctl --namespace k8s.io build -t synchronaise-backend:dev backend` |
| dockerd | `docker build -t synchronaise-backend:dev backend` |

Images are loaded directly into k3s — no registry push required for local dev.

## Script options

### PowerShell (`deploy.ps1`)

```powershell
.\deploy\deploy.ps1                          # full deploy
.\deploy\deploy.ps1 -SkipBuild               # helm only (image already built)
.\deploy\deploy.ps1 -SkipHelm                # build only
.\deploy\deploy.ps1 -Namespace hackathon     # override namespace
```

### Bash (`deploy.sh`)

```bash
./deploy/deploy.sh
./deploy/deploy.sh --skip-build
./deploy/deploy.sh --skip-helm
./deploy/deploy.sh --namespace hackathon --release synchronaise
```

## Application Collection MCP (Cursor)

Copy `.cursor/mcp.example.json` to `.cursor/mcp.json` and fill in your Basic-auth token (from the rancher bootstrap). This lets Cursor agents browse and deploy charts from `https://mcp.apps.rancher.io`.

### mcp-proxy fallback

Some MCP clients handle HTTP Basic auth poorly. The rancher-hackathon-paris repo documents **mcp-proxy** as a local workaround: run the proxy on port **3000** and point your MCP client at `http://localhost:3000` instead of `https://mcp.apps.rancher.io`. The proxy forwards requests with the `Authorization` header attached.

See the rancher repo README for `mcp-proxy` install and usage.

## Adding supporting charts (Postgres, Redis, …)

Audit persistence beyond in-memory storage can use Application Collection charts from the registry:

```bash
helm install my-postgres oci://dp.apps.rancher.io/charts/postgresql \
  --namespace hackathon \
  --set global.imagePullSecrets={application-collection}
```

Browse available charts via the Application Collection MCP in Cursor, or at [dp.apps.rancher.io](https://dp.apps.rancher.io). Always pass `--set global.imagePullSecrets={application-collection}` when installing into `hackathon`, matching the rancher bootstrap contract.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `kubectl context is '...', expected 'rancher-desktop'` | Start Rancher Desktop; `kubectl config use-context rancher-desktop` |
| `Secret 'application-collection' not found` | Run `init.bat` from rancher-hackathon-paris |
| Pod `CreateContainerConfigError` | Create `synchronaise-llm` secret (see above) |
| `ImagePullBackOff` for Application Collection images | Re-run rancher `init.bat` to refresh registry login |
| `nerdctl: command not found` | Enable containerd in Rancher Desktop, or switch to dockerd |

Manual Helm install (equivalent to what the scripts run):

```bash
helm upgrade --install synchronaise ./deploy/helm/synchronaise \
  --namespace hackathon \
  --set global.imagePullSecrets={application-collection}
```
