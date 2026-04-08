# GCP + GitHub Actions: Workload Identity Federation (theory, setup, results)

This document records what was configured so **GitHub Actions** can authenticate to **Google Cloud** to run **Terraform**—without storing a **service account JSON key** in GitHub.

---

## 1. Goals

| Goal | Why |
|------|-----|
| Learn GCP with Terraform | Infrastructure as code against real APIs |
| Use GitHub Actions as CI | Plans/applies from the repo, auditable history |
| Avoid long-lived keys | Keys leak; OIDC + WIF uses short-lived tokens |

**Deferred for later:** Terraform **remote state** (GCS backend, locking). This guide stops at **identity**: GitHub → GCP trust + a service account Terraform can use.

---

## 2. Core concepts

### 2.1 Git tags vs GitHub Releases (short)

- A **Git tag** points to a commit (e.g. `v0.1.0`). It is a Git object.
- A **GitHub Release** is usually **metadata + notes (and sometimes assets)** attached to a tag.
- For this learning repo, tags mark milestones (e.g. “WIF working”, “first `terraform plan` in CI”).

### 2.2 Do you need a GCP Organization?

**No** for personal learning. A **project** under **no organization** is valid. An **Organization** becomes important when a company centralizes folders, org policies, and shared VPC.

### 2.3 Why a Workload Identity **Pool** and still a **Service Account**?

| Piece | What it answers |
|-------|------------------|
| **Workload Identity Pool + OIDC provider** | “Is this token really from **GitHub Actions** for **this repo/branch**?” |
| **Service Account (SA)** | “Once trusted, **which GCP identity** should Terraform use, and **what IAM roles** does it have?” |

The pool **does not replace** the service account: it **replaces static keys** by letting GitHub exchange an OIDC token for **short-lived credentials** to **impersonate** one specific SA.

### 2.4 End-to-end flow (how)

1. Workflow runs on GitHub; GitHub issues an **OIDC token** (when `permissions: id-token: write` is set).
2. Google’s **Workload Identity Federation** validates the token against the **issuer** `https://token.actions.githubusercontent.com`.
3. **Attribute mapping** copies claims (e.g. `repository`, `ref`) into Google’s model.
4. **Attribute condition** (CEL) restricts which workflows may proceed (e.g. only repo `vsbotu/tf-gcp` and branch `main`).
5. IAM allows that external identity to **impersonate** `sa-github-terraform` (**Workload Identity User** on the SA).
6. The workflow receives credentials as that SA; **Terraform** uses them to call GCP APIs.

---

## 3. What was created (checklist)

In project **`terraform-vsbotu`** (friendly name **terraform**):

| # | Resource | Purpose |
|---|----------|---------|
| 1 | Billing linked | Most APIs and resources require billing |
| 2 | APIs enabled | e.g. IAM Credentials, STS, Resource Manager (enable others as Terraform needs them) |
| 3 | Service Account `sa-github-terraform` | Identity Terraform uses inside GCP |
| 4 | Project IAM: SA → **Editor** (learning) | Lets that SA create/manage many resources (tighten later) |
| 5 | Workload Identity Pool `github-pool` | Namespace for external identities |
| 6 | OIDC provider (GitHub) | Trusts GitHub’s OIDC issuer |
| 7 | SA resource IAM: `principalSet` → **Workload Identity User** | Lets GitHub impersonate the SA |

---

## 4. Your environment (reference values)

Use these when you write the GitHub Actions workflow or Terraform provider config.

| Item | Value |
|------|--------|
| **Project ID** | `terraform-vsbotu` |
| **Project number** | `935459376295` |
| **Pool ID** | `github-pool` |
| **Provider type** | OIDC |
| **Issuer URL** | `https://token.actions.githubusercontent.com` |
| **GitHub repo** (for conditions / bindings) | `vsbotu/tf-gcp` |
| **Service account email** | `sa-github-terraform@terraform-vsbotu.iam.gserviceaccount.com` |

**Full workload identity provider resource name** (replace `<PROVIDER_ID>` with the ID shown under **Workload Identity Federation → github-pool → Providers**, often `github`):

```text
projects/935459376295/locations/global/workloadIdentityPools/github-pool/providers/<PROVIDER_ID>
```

**Example** if the provider ID is `github`:

```text
projects/935459376295/locations/global/workloadIdentityPools/github-pool/providers/github
```

**IAM principal for GitHub (used on the service account)** — allows that repo’s federated identities to impersonate the SA:

```text
principalSet://iam.googleapis.com/projects/935459376295/locations/global/workloadIdentityPools/github-pool/attribute.repository/vsbotu/tf-gcp
```

---

## 5. Provider configuration (what you set in the console)

### 5.1 Attribute mapping (OIDC → Google)

These map GitHub token claims into attributes Google can use in conditions and principal names:

| Google (left) | OIDC / CEL (right) |
|---------------|---------------------|
| `google.subject` | `assertion.sub` |
| `attribute.repository` | `assertion.repository` |
| `attribute.ref` | `assertion.ref` |
| `attribute.actor` | `assertion.actor` |

### 5.2 Attribute condition (CEL) — restrict who can authenticate

Example used in discussion (**only this repo, only `main`**):

```text
assertion.repository == "vsbotu/tf-gcp" && assertion.ref == "refs/heads/main"
```

**Why:** Without a condition, any identity accepted by the issuer configuration could be too broad; the condition scopes access to **your repo** (and optionally **only `main`**).

---

## 6. IAM: two different places (why people get confused)

| Where | Principal | Role | Meaning |
|-------|-----------|------|--------|
| **Project IAM** (project “terraform”) | `sa-github-terraform@terraform-vsbotu.iam.gserviceaccount.com` | **Editor** (example) | What the **service account** may do **in the project** (create VMs, buckets, etc.). |
| **Service account → Permissions** (“who can use this SA”) | `principalSet://.../attribute.repository/vsbotu/tf-gcp` | **Workload Identity User** | Who may **impersonate** this SA — here, **GitHub Actions** that match the pool rules. |

Both are needed: **Editor** (or narrower roles) for **what Terraform can do**; **Workload Identity User** for **GitHub being allowed to assume that identity**.

---

## 7. Expected results / “outputs” (what you should see)

### 7.1 Pool details (example)

After creating the pool, the console shows an **IAM principal** pattern like:

```text
principal://iam.googleapis.com/projects/935459376295/locations/global/workloadIdentityPools/github-pool/subject/SUBJECT_ATTRIBUTE_VALUE
```

That illustrates how Google names federated identities; your **GitHub** access is then narrowed via **attribute mapping + conditions** and the **principalSet** binding.

### 7.2 Service account — “Principals with access to this service account”

You should see a row similar to:

| Type / Principal | Role |
|------------------|------|
| `…/github-pool/…/vsbotu/tf-gcp` (truncated in UI) | **Workload Identity User** |

Console may show: **Policy updated. It may take a few minutes for these changes to become active.**

### 7.3 Service account keys

**Result:** **No keys** on `sa-github-terraform` — correct for the WIF approach.

---

## 8. Next steps (not yet done in this doc)

1. Add a GitHub Actions workflow with:
   - `permissions: id-token: write`
   - `google-github-actions/auth@v2` using `workload_identity_provider` + `service_account`
2. Run `terraform plan` (and later `apply`) from CI.
3. Tag a milestone (e.g. `v0.1.0-wif`) when the workflow authenticates successfully.
4. Later: move state to a **GCS backend** and tighten IAM from **Editor** to least-privilege roles.

### 8.1 Example workflow fragment (reference)

```yaml
permissions:
  id-token: write
  contents: read

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: >-
            projects/935459376295/locations/global/workloadIdentityPools/github-pool/providers/github
          service_account: sa-github-terraform@terraform-vsbotu.iam.gserviceaccount.com

      - name: Verify GCP access
        run: gcloud config get-value project
        env:
          CLOUDSDK_CORE_PROJECT: terraform-vsbotu
```

Adjust `workload_identity_provider` if your **provider ID** is not `github`.

---

## 9. Security notes (for later you)

- Prefer **branch** or **environment** restrictions in the WIF condition as your team matures.
- Replace **Editor** with **least privilege** per service (Storage, Compute, IAM, etc.).
- When you add remote state, grant the SA **only** what it needs on the state bucket (e.g. `storage.objectAdmin` on that bucket).

---

## 10. Revision log

| Milestone | Notes |
|-----------|--------|
| Project created | No org; Project ID `terraform-vsbotu` |
| WIF | Pool `github-pool`, GitHub OIDC issuer |
| SA | `sa-github-terraform`; impersonation via **Workload Identity User** for `vsbotu/tf-gcp` |
| Doc | **§11** documents the same setup via `gcloud` CLI |

---

## 11. Equivalent setup with Google Cloud CLI (`gcloud`)

This section mirrors **§3–§6** using the **command line**. Use it to reproduce the same resources in another project, automate setup, or compare with what you created in the console.

**Prerequisites**

- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) installed (`gcloud` on your `PATH`).
- You are logged in: `gcloud auth login`
- Billing is linked to the target project.
- You can set the active project: `gcloud config set project terraform-vsbotu`

**Conventions**

- Replace `terraform-vsbotu` if your **Project ID** differs.
- Replace `935459376295` with your **project number** (see below)—do not assume it matches this doc.
- If a resource **already exists**, the corresponding `create` command will fail; skip that step or delete the resource in a lab only.

### 11.1 Variables (recommended)

```bash
export PROJECT_ID="terraform-vsbotu"
export POOL_ID="github-pool"
export PROVIDER_ID="github"          # must match provider ID you want in the resource name
export SA_ID="sa-github-terraform"
export SA_EMAIL="${SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
export GITHUB_REPO="vsbotu/tf-gcp"   # owner/name
export GITHUB_OWNER="vsbotu"         # for optional audience

# Project number (required for principalSet and some checks)
export PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"
echo "PROJECT_NUMBER=${PROJECT_NUMBER}"
```

### 11.2 Enable APIs

Same idea as enabling services in **APIs & Services → Library**:

```bash
gcloud services enable \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  --project="${PROJECT_ID}"
```

### 11.3 Create the service account

```bash
gcloud iam service-accounts create "${SA_ID}" \
  --project="${PROJECT_ID}" \
  --display-name="Terraform from GitHub Actions" \
  --description="Terraform from GitHub Actions"
```

### 11.4 Grant the service account permissions on the project (learning: Editor)

This matches **project IAM**: what the SA may do **inside the project**.

```bash
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/editor"
```

For tighter access later, replace `roles/editor` with specific roles (Storage, Compute, etc.).

### 11.5 Create the workload identity pool

```bash
gcloud iam workload-identity-pools create "${POOL_ID}" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --display-name="GITHUB POOL"
```

### 11.6 Create the OIDC provider (GitHub)

Maps attributes and applies the **CEL condition** (same as **§5**).

**Main branch only** for repo `vsbotu/tf-gcp`:

```bash
gcloud iam workload-identity-pools providers create-oidc "${PROVIDER_ID}" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --workload-identity-pool="${POOL_ID}" \
  --display-name="GitHub" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref,attribute.actor=assertion.actor" \
  --attribute-condition="assertion.repository == \"${GITHUB_REPO}\" && assertion.ref == \"refs/heads/main\""
```

**Any branch** for that repo (alternative condition):

```bash
# --attribute-condition="assertion.repository == \"${GITHUB_REPO}\""
```

**Optional — restrict OIDC audience** (often set in console as “Allowed audiences”):

```bash
# Append to create-oidc (example):
# --allowed-audiences="https://github.com/${GITHUB_OWNER}"
```

### 11.7 Allow GitHub (federated identity) to impersonate the service account

This matches **§6**: **Workload Identity User** on the **service account resource** for the `principalSet` built from `attribute.repository`.

```bash
gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${GITHUB_REPO}"
```

### 11.8 Verify (CLI “outputs”)

List pool and provider:

```bash
gcloud iam workload-identity-pools list --location=global --project="${PROJECT_ID}"

gcloud iam workload-identity-pools providers list \
  --location=global \
  --workload-identity-pool="${POOL_ID}" \
  --project="${PROJECT_ID}"
```

Show IAM policy on the service account (look for `principalSet` + `workloadIdentityUser`):

```bash
gcloud iam service-accounts get-iam-policy "${SA_EMAIL}" --project="${PROJECT_ID}"
```

Confirm **no keys** on the SA:

```bash
gcloud iam service-accounts keys list \
  --iam-account="${SA_EMAIL}" \
  --project="${PROJECT_ID}"
```

Expected: **no keys** (empty list) if you rely on WIF only.

### 11.9 Provider resource name for GitHub Actions

After CLI creation, the **workload identity provider** string is:

```text
projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}
```

Example with this doc’s IDs (verify `PROJECT_NUMBER` and `PROVIDER_ID` on your machine):

```text
projects/935459376295/locations/global/workloadIdentityPools/github-pool/providers/github
```

### 11.10 Notes and troubleshooting

| Issue | What to check |
|-------|----------------|
| `create` fails: already exists | Resource was created earlier (console or script). List/describe instead of create. |
| GitHub Actions auth fails | `permissions: id-token: write`; provider ID path matches **§11.9**; condition matches branch/repo. |
| Permission denied on GCP | SA needs roles on the **project** (**§11.4**); impersonation needs **§11.7**. |
| Wrong project number in `principalSet` | Re-run **§11.1** and **§11.7** with `echo $PROJECT_NUMBER`. |
