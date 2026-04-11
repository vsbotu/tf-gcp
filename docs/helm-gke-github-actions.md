# Helm, GKE, and GitHub Actions — concepts and this repo

This guide explains **Helm**, how it maps to **Kubernetes on GKE**, how we structured **`deploy/helm`** and **`app/nginx/values.yaml`**, and how **`.github/workflows/helm-deploy-nginx.yml`** deploys from CI. Use it as a reference when you revisit the setup.

---

## 1. What Helm is (mental model)

| Idea | Plain language |
|------|----------------|
| **Chart** | A **folder** of templated Kubernetes YAML + metadata (`Chart.yaml`, `values.yaml`, `templates/`). |
| **Template** | A file under `templates/` with **`{{ ... }}`** placeholders; Helm renders it to real YAML. |
| **values.yaml** | **Defaults** for those placeholders (image, replicas, service type, …). |
| **Release** | One **installed instance** of a chart in a cluster: **release name** + **namespace** + **revision**. |
| **`helm install` / `helm upgrade --install`** | Apply rendered manifests; **`upgrade --install`** creates the release if missing (idempotent for CI). |

Helm does **not** replace kubectl — it **generates** manifests and **applies** them (and tracks what it installed in a **Secret** by default, for history/rollback).

**Compared to raw YAML:** one chart can serve many environments by swapping **values files** (`-f prod.yaml`) instead of duplicating entire manifests.

---

## 2. How this maps to GKE

- **GKE** is Kubernetes; **Helm** talks to whatever cluster **`kubectl`** points at.
- **`gcloud container clusters get-credentials ...`** writes **`kubeconfig`** entries so **`kubectl` / `helm`** use your **GKE** API server.
- **Workload Identity / IAM:** the identity running Helm (your laptop or GitHub Actions SA) needs permission to **get credentials** and **create** Deployments/Services in the cluster (e.g. **Kubernetes Engine Developer** or appropriate RBAC + IAM).

Nothing GKE-specific is *inside* the nginx chart unless you add node pools, GCP LB annotations, etc. Our sample uses **ClusterIP** — exposure via **Gateway / Ingress** is a separate step.

---

## 3. Repository layout (this project)

```text
deploy/helm/nginx-sample/     # Helm chart
  Chart.yaml                  # chart name, version
  values.yaml                 # default values (defaults)
  templates/
    _helpers.tpl              # named templates (names, labels)
    deployment.yaml           # Deployment
    service.yaml              # Service
    NOTES.txt                 # post-install hints (helm install notes)

app/nginx/values.yaml         # environment/app overrides (passed with -f)

.github/workflows/helm-deploy-nginx.yml   # manual Helm deploy from GitHub
```

- **Chart defaults** live in **`deploy/helm/nginx-sample/values.yaml`**.
- **`app/nginx/values.yaml`** is an **overlay** (e.g. `replicaCount: 2`) you pass with:

  ```bash
  helm upgrade --install nginx-sample ./deploy/helm/nginx-sample \
    -f app/nginx/values.yaml \
    -n demo --create-namespace
  ```

Later you can add **`app/staging/values.yaml`**, **`app/prod/values.yaml`**, etc., without copying the chart.

---

## 4. Commands to run locally (after `get-credentials`)

```bash
cd /path/to/terraform-gcp

# Optional: see rendered YAML without applying
helm template myrel ./deploy/helm/nginx-sample -f app/nginx/values.yaml -n demo

# Lint chart + values
helm lint ./deploy/helm/nginx-sample -f app/nginx/values.yaml

# Deploy / upgrade
kubectl create namespace demo --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install nginx-sample ./deploy/helm/nginx-sample \
  -f app/nginx/values.yaml \
  -n demo --wait --timeout 5m

kubectl get deploy,svc,pods -n demo
kubectl port-forward -n demo svc/nginx-sample 8080:80
curl -s http://127.0.0.1:8080/ | head -5
```

**Release name** (`nginx-sample` above) appears in labels like `app.kubernetes.io/instance=nginx-sample`.

---

## 5. Example `helm template` output (what to expect)

After rendering, you should see a **Deployment** and a **Service** with:

- Image **`nginx:1.25`** (from values),
- **2 replicas** (from `app/nginx/values.yaml`),
- **ClusterIP** Service on port **80**.

Exact names depend on **release name** (e.g. resources may be named `nginx-sample-nginx-sample` or shortened — see `fullname` helper in `_helpers.tpl`).

---

## 6. GitHub Actions workflow: `helm-deploy-nginx.yml`

### 6.1 Trigger

- **`workflow_dispatch` only** — run from **Actions → Helm deploy (nginx-sample) → Run workflow**.
- Inputs: **`namespace`** (default `demo`), **`release_name`** (default `nginx-sample`).

### 6.2 Authentication (same idea as Terraform)

1. **`google-github-actions/auth@v2`** with **Workload Identity Federation**:
   - **`GCP_WIF_PROVIDER`**, **`GCP_SA_EMAIL`**, **`GCP_WIF_AUDIENCE`** — same **repository variables** as **`terraform-infra.yml`** / **`validate-gcp-connection.yml`**.
2. **`setup-gcloud`** with **`gke-gcloud-auth-plugin`** so **`kubectl`** works with modern GKE auth.

### 6.3 Cluster selection

- **`gcloud container clusters get-credentials`** uses:
  - **`GKE_CLUSTER_NAME`** (optional repo variable; default **`gke-us-east1-demo`** in the script),
  - **`GKE_ZONE`** (optional; default **`us-east1-b`**).

Set **`GKE_CLUSTER_NAME`** / **`GKE_ZONE`** in GitHub **Variables** if your Terraform uses different names/regions.

### 6.4 Helm steps

1. **`helm lint`** — fail fast on chart errors.
2. **`helm template`** — print first lines of rendered YAML (sanity check).
3. **`helm upgrade --install`** — deploy with **`app/nginx/values.yaml`**, **`--wait`** for rollout.

### 6.5 IAM / RBAC expectations

The **GitHub Actions service account** must be able to:

- Call **`container.clusters.getCredentials`** (or equivalent) — often covered by **Kubernetes Engine Admin** / **Developer** on the project.
- Inside the cluster, the SA’s **GCP identity** must map to **Kubernetes RBAC** if your cluster enforces **User/SA** restrictions. For many dev clusters, the default binding for the **cluster creator** / **GCP SA** is enough; if **`helm`** fails with **Forbidden**, add a **RoleBinding** for that identity.

---

## 7. Theory: CI vs local `kubectl`

| Topic | Detail |
|-------|--------|
| **Same commands** | CI runs the same **`helm upgrade`** you would run locally after **`get-credentials`**. |
| **Ephemeral runner** | The job VM disappears after the run; only **cluster state** (Helm release in GKE) persists. |
| **State** | Helm stores release metadata in the **cluster** (Secrets by default), not in the repo. |

---

## 8. Troubleshooting

| Symptom | Things to check |
|---------|------------------|
| **Auth failed** | WIF variables; **audience**; **service account** still has **Workload Identity User** for the pool principal. |
| **Cannot get credentials** | **`GKE_CLUSTER_NAME` / `GKE_ZONE`** match Terraform; project ID correct. |
| **Helm: forbidden** | RBAC for the GCP SA used by GitHub Actions. |
| **Wrong image/replicas** | Which **`-f`** file is passed; later values **override** earlier keys. |

---

## 9. How this ties to Terraform

- **Terraform** in **`infra/`** creates **VPC + GKE** (and Gateway API channel).
- **Helm** deploys **workloads** into that cluster.
- Order: **`terraform apply`** (or existing cluster) → **`helm upgrade`**.

---

## 10. Optional next steps (not in this chart)

- **Gateway API**: add **`HTTPRoute` + `Gateway`** templates or a second chart; requires **GatewayClass** on the cluster.
- **Remote Terraform state** (GCS backend) so CI **Terraform** and **Helm** align with shared infrastructure lifecycle.

---

*Document version: written alongside `deploy/helm/nginx-sample` and `helm-deploy-nginx.yml`.*
