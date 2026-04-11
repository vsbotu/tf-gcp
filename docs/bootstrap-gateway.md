# Bootstrap: shared Gateway + HTTPRoutes (Helm)

The **Gateway** is a **single shared load balancer** for all apps. It lives in a **plain manifest** (`bootstrap/gateway.yaml`) — apply once (or when you change listeners). **HTTPRoutes** are **Helm-managed** (`bootstrap/http-routes`) so each app can add routes that attach to the same Gateway via **`parentRefs`**.

---

## 1. Prerequisites

| Requirement | Why |
|-------------|-----|
| **GKE cluster** with **Gateway API** enabled | `kubectl get gatewayclass` shows `gke-l7-global-external-managed`. |
| **Backend `Service`s** in the same namespace (for `allowedRoutes.namespaces.from: Same`) | HTTPRoute `backendRefs` point to **Kubernetes Service** names (e.g. `nginx-sample` from the nginx Helm chart). |
| **Order** | Create namespace → apply **Gateway** → deploy workloads → **Helm HTTPRoutes** (or routes show `ResolvedRefs=False` until Services exist). |

---

## 2. Layout

```text
bootstrap/gateway.yaml           # Shared Gateway (kubectl apply; not Helm)
bootstrap/http-routes/             # Helm chart: HTTPRoute resources only
  Chart.yaml
  values.yaml
  templates/
    httproute.yaml                # loops over .Values.httpRoutes
    _helpers.tpl
    NOTES.txt

app/gateway/values.yaml           # Overrides for http-routes chart (routes + gatewayRef)
.github/workflows/bootstrap-gateway.yml
```

---

## 3. Values model (`bootstrap/http-routes` + `app/gateway/values.yaml`)

### `gatewayRef`

Must match **`bootstrap/gateway.yaml`** (`metadata.name` / `namespace` and listener `name` for `sectionName`).

| Field | Meaning |
|-------|---------|
| `name` | Gateway object name (e.g. `external-http`). |
| `namespace` | Namespace where the Gateway runs. |
| `sectionName` | Listener name on the Gateway (e.g. `http`). |

### `httpRoutes`

List of **`HTTPRoute`** objects. Each item has:

- `name` — Kubernetes resource name.
- `rules` — list of rules, each with:
  - `pathPrefix`
  - `serviceName` — **must match** `kubectl get svc -n <ns>`
  - `servicePort` — Service **port** (not targetPort)

**Path order:** Put **more specific** prefixes **before** `/` in the same route’s `rules` list.

Example (`app/gateway/values.yaml`):

```yaml
gatewayRef:
  name: external-http
  namespace: demo
  sectionName: http

httpRoutes:
  - name: nginx-root
    rules:
      - pathPrefix: /
        serviceName: nginx-sample
        servicePort: 80
```

---

## 4. Local install

```bash
gcloud container clusters get-credentials gke-us-east1-demo --zone us-east1-b --project YOUR_PROJECT_ID

kubectl create namespace demo --dry-run=client -o yaml | kubectl apply -f -

# Shared Gateway (once; edit bootstrap/gateway.yaml if namespace/name change)
kubectl apply -f bootstrap/gateway.yaml

helm lint ./bootstrap/http-routes -f app/gateway/values.yaml
helm template routes ./bootstrap/http-routes -f app/gateway/values.yaml -n demo

helm upgrade --install http-routes ./bootstrap/http-routes \
  -f app/gateway/values.yaml \
  -n demo

kubectl get gateway,httproute -n demo
kubectl get gateway external-http -n demo -w   # wait for ADDRESS
curl -s http://ADDRESS/
```

---

## 5. GitHub Actions

**Workflow:** `.github/workflows/bootstrap-gateway.yml`

- **Manual** (`workflow_dispatch`).
- Same **WIF** variables as Terraform / nginx Helm (`GCP_PROJECT_ID`, `GCP_WIF_PROVIDER`, `GCP_SA_EMAIL`, `GCP_WIF_AUDIENCE`).
- Optional **`GKE_CLUSTER_NAME`** / **`GKE_ZONE`** (defaults: `gke-us-east1-demo`, `us-east1-b`).
- **`apply_gateway`**: run **`kubectl apply -f bootstrap/gateway.yaml`** (disable if the shared Gateway already exists).
- Runs **`kubectl get gatewayclass`**, **`helm lint`**, **`helm template`**, **`helm upgrade --install`** for **http-routes** only.

---

## 6. Theory (quick)

| Object | Role |
|--------|------|
| **`GatewayClass`** | Cluster-scoped; GKE provides **`gke-l7-global-external-managed`**. |
| **`Gateway`** | Listener (e.g. :80) + LB front end; gets an **external IP**. |
| **`HTTPRoute`** | Attaches to a **`Gateway`** via **`parentRefs`**; routes **paths** to **Services**. |

The **GKE controller** provisions the **Google Cloud load balancer** (can take several minutes).

---

## 7. Troubleshooting

| Issue | Check |
|-------|--------|
| **No ADDRESS on Gateway** | Wait; `kubectl describe gateway -n demo` |
| **404 / wrong backend** | `serviceName` / `port`; path order; Service endpoints ready |
| **ResolvedRefs=False** | Backend Service missing or wrong port |
| **Forbidden** | GitHub SA **RBAC** in cluster |

---

*See also: [helm-gke-github-actions.md](helm-gke-github-actions.md), [gke-gateway-api-lab.md](gke-gateway-api-lab.md).*
