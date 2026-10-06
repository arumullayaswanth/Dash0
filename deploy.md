# Deploy — steps only

Values you will reuse:

- `OWNER/REPO` = `arumullayaswanth/Dash0`
- `ACCOUNT_ID` = `713939171080`
- OIDC subject = `repo:arumullayaswanth/Dash0:*`
- `AWS_REGION` = `us-east-1`
- `TF_STATE_BUCKET` = `dash0demo`

## 1. Collect Dash0 values

1.1 Sign in to <https://app.dash0.com>.

1.2 **Settings** → **Endpoints** → find the **OTLP/gRPC** row → copy it → save as `DASH0_OTLP_GRPC_ENDPOINT`.
   - Must look like `ingress.us-west-2.aws.dash0.com:4317`.
   - No `https://`, no URL path. Do not use the OTLP/HTTP row.

1.3 Same page → copy **API** → save as `DASH0_API_ENDPOINT`.
   - Must look like `https://api.us-west-2.aws.dash0.com`.

1.4 **Settings** → **Auth Tokens** → **Create token** → name `github-dash0-eks-demo`.

1.5 Click **Copy** and keep the dialog open until Step 5.2.

1.6 **Settings** → **Datasets** → **Create dataset** → name it `demo`. This is where all telemetry from the cluster lands, and it must exist before you apply or Dash0 drops the data.
   - The workflow uses `demo` by default (baked into the workflow env).
   - If you prefer the built-in `default` dataset instead of creating one, skip creating `demo` and set the `DASH0_DATASET` repository variable to `default` in Step 5.1.
   - To use any other name, create that dataset here and set `DASH0_DATASET` to match in Step 5.1.

## 2. Create the S3 state bucket (AWS Console)

1. AWS Console → set Region to `us-east-1`.
2. **S3** → **Create bucket**.
3. **Bucket name** = `dash0demo`.
4. **Block all public access** = on.
5. **Bucket Versioning** = Enable.
6. **Default encryption** = SSE-S3.
7. Click **Create bucket**.

## 3. Create the AWS OIDC provider

1. **IAM** → **Identity providers**.
2. If `token.actions.githubusercontent.com` is already listed, click it, confirm **Audience** = `sts.amazonaws.com`, and skip to Step 4.
3. Otherwise click **Add provider**.
4. Type = **OpenID Connect**.
5. Provider URL = `https://token.actions.githubusercontent.com` → **Get thumbprint**.
6. Audience = `sts.amazonaws.com`.
7. Click **Add provider**.
8. Confirm `token.actions.githubusercontent.com` now appears in the list.

> This provider must exist. Without it the trust policy in Step 4 still saves, but every run fails with `Not authorized to perform sts:AssumeRoleWithWebIdentity`.

## 4. Create the AWS role

1. **IAM** → **Roles** → **Create role**.
2. Trusted entity = **Web identity**.
3. Identity provider = `token.actions.githubusercontent.com`, Audience = `sts.amazonaws.com`.
4. **Next** → attach **PowerUserAccess** and **IAMFullAccess** → **Next**.
5. Name = `github-dash0-eks-demo` → **Create role**.
6. Open the role → **Trust relationships** → **Edit trust policy**.
7. Select all existing JSON, delete it, and paste this exactly as-is:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "GitHubActionsOIDC",
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::713939171080:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:arumullayaswanth/Dash0:*"
        }
      }
    }
  ]
}
```

4.8 Click **Update policy**.

4.9 Reopen the **Trust relationships** tab and confirm the JSON shown matches what you pasted. If it does not, the save did not apply.

4.10 Copy the role **ARN** from the role summary → save as `AWS_ROLE_ARN`. It should read `arn:aws:iam::713939171080:role/github-dash0-eks-demo`.

**Checklist** if a run fails with `Not authorized to perform sts:AssumeRoleWithWebIdentity`:

| Check | Where | Must be |
|---|---|---|
| Provider exists | IAM → Identity providers | `token.actions.githubusercontent.com` listed |
| Provider audience | click the provider | `sts.amazonaws.com` |
| Trust policy saved | role → Trust relationships | matches the JSON above |
| Repo name case | trust policy `sub` | `Dash0`, capital D |
| Account matches | role ARN vs provider ARN | both `713939171080` |
| `AWS_ROLE_ARN` | GitHub repo variable | the same role ARN |

## 5. Configure GitHub

### 5.1 Add repository variables

5.1.1 Repo → **Settings** → **Secrets and variables** → **Actions** → **Variables** tab.

5.1.2 Click **New repository variable** for each row:

| Name | Value |
|---|---|
| `AWS_ROLE_ARN` | `arn:aws:iam::713939171080:role/github-dash0-eks-demo` |
| `AWS_REGION` | `us-east-1` |
| `TF_STATE_BUCKET` | `dash0demo` |
| `DASH0_OTLP_GRPC_ENDPOINT` | from Step 1.2, e.g. `ingress.us-west-2.aws.dash0.com:4317` |
| `DASH0_API_ENDPOINT` | from Step 1.3, e.g. `https://api.us-west-2.aws.dash0.com` |
| `DASH0_DATASET` | the dataset from Step 1.6, e.g. `demo` |


### 5.2 Add repository secret

Same page → **Secrets** tab → **New repository secret**:

| Name | Value |
|---|---|
| `DASH0_AUTH_TOKEN` | token from Step 1.5 |

## 6. Apply

1. Repo → **Actions** → **Dash0 EKS lifecycle** → **Run workflow**.
2. action = `apply`.
3. Leave confirm as `no` (not needed for apply).
4. Click **Run workflow**.
5. Wait until **Overall result** is success.

## 7. See results in Dash0

1. Open <https://app.dash0.com>.
2. Select dataset `demo`.
3. Add filter `k8s.cluster.name = dash0-lab-demo`.
4. Open the **Dash0 EKS Demo Overview** dashboard.
5. Open **Kubernetes**, **Services**, **Traces**, **Logs**, **Events**.

## 8. See results from the cluster (bastion)

8.1 In the run **Summary**, note `bastion_instance_id`.

8.2 AWS Console → **Systems Manager** → **Session Manager** → **Start session**.

8.3 Select the matching instance → **Start session**.

8.4 Run:
   - `aws eks update-kubeconfig --region us-east-1 --name dash0-lab-demo`
   - `kubectl get nodes -o wide`
   - `kubectl get pods -A`
   - `kubectl get pods -n otel-demo`
   - `kubectl get statefulsets -A`

## 9. Browse the demo app and inject failures

The demo runs a built-in load generator, so traffic flows into Dash0
automatically. To browse the storefront and trigger errors on demand:

**Option A — public URL (if `expose_demo_frontend = true`):**

9.1 After apply, find `demo_frontend_url` in the Terraform outputs.

9.2 Open that URL in a browser — the demo storefront.

9.3 Browse products, add to cart, check out to generate traces, metrics, and logs.

9.4 Append `/feature` to the URL — flag UI. Toggle a failure flag such as
`adServiceFailure`, `cartServiceFailure`, or `productCatalogFailure`. Within a
minute the resulting errors appear in Dash0 under Traces and Logs.

**Option B — port-forward (private cluster):**

9.5 Run these commands (also printed as the `demo_app_access` output):

```bash
aws eks update-kubeconfig --region us-east-1 --name dash0-lab-demo
kubectl -n otel-demo port-forward svc/frontend-proxy 8080:8080
```

9.6 Open `http://localhost:8080` in a browser.

9.7 Open `http://localhost:8080/feature` to inject failures.

9.8 Press `Ctrl+C` to stop the port-forward.

## 10. Destroy

10.1 **Run workflow**: action = `destroy`, confirm = `yes`.

10.2 Wait until **Overall result** is success and remaining resource counts are `0`.
on demand, open it locally with a port-forward (also printed as the
> The `dash0demo` S3 bucket is never deleted by the workflow. Delete it manually in the S3 console if you no longer need it.

## 11. Troubleshooting

```bash
aws eks update-kubeconfig --region us-east-1 --name dash0-lab-demo
kubectl -n otel-demo port-forward svc/frontend-proxy 8080:8080
# 11.1 Is the operator config Available?

Then in a browser:
# 11.2 Is there a collector at all?
- `http://localhost:8080` — storefront. Browse products, add to cart, check out
  to generate traces, metrics, and logs.
# 11.3 What is the operator complaining about?
  `adServiceFailure`, `cartServiceFailure`, or `productCatalogFailure`. Within a
  minute the resulting errors appear in Dash0 under Traces and Logs.
# 11.4 Is any namespace monitored?
Leave the `port-forward` command running while you browse; press `Ctrl+C` to

# 11.5 StatefulSet status
kubectl get statefulsets -A

# 11.6 All pods
kubectl get pods -A
stop it.

## 8.5 Browse the demo app and inject failures

The demo already runs a built-in load generator, so traffic flows into Dash0
without any action. To click through the storefront yourself and trigger errors
on demand, open it locally with a port-forward (also printed as the
`demo_app_access` output after apply):

```bash
aws eks update-kubeconfig --region us-east-1 --name dash0-lab-demo
kubectl -n otel-demo port-forward svc/frontend-proxy 8080:8080
```

Then in a browser:

- `http://localhost:8080` — storefront. Browse products, add to cart, check out
  to generate traces, metrics, and logs.
- `http://localhost:8080/feature` — flag UI. Toggle a failure flag such as
  `adServiceFailure`, `cartServiceFailure`, or `productCatalogFailure`. Within a
  minute the resulting errors appear in Dash0 under Traces and Logs.

Leave the `port-forward` command running while you browse; press `Ctrl+C` to
stop it.

## 8.5 Browse the demo app and inject failures

The demo already runs a built-in load generator, so traffic flows into Dash0
without any action. To click through the storefront yourself and trigger errors
on demand, open it locally with a port-forward (also printed as the
`demo_app_access` output after apply):

```bash
aws eks update-kubeconfig --region us-east-1 --name dash0-lab-demo
kubectl -n otel-demo port-forward svc/frontend-proxy 8080:8080
```

Then in a browser:

- `http://localhost:8080` — storefront. Browse products, add to cart, check out
  to generate traces, metrics, and logs.
- `http://localhost:8080/feature` — flag UI. Toggle a failure flag such as
  `adServiceFailure`, `cartServiceFailure`, or `productCatalogFailure`. Within a
  minute the resulting errors appear in Dash0 under Traces and Logs.

Leave the `port-forward` command running while you browse; press `Ctrl+C` to
stop it.

## 8.5 Browse the demo app and inject failures

The demo already runs a built-in load generator, so traffic flows into Dash0
without any action. To click through the storefront yourself and trigger errors
on demand, open it locally with a port-forward (also printed as the
`demo_app_access` output after apply):

```bash
aws eks update-kubeconfig --region us-east-1 --name dash0-lab-demo
kubectl -n otel-demo port-forward svc/frontend-proxy 8080:8080
```

Then in a browser:

- `http://localhost:8080` — storefront. Browse products, add to cart, check out
  to generate traces, metrics, and logs.
- `http://localhost:8080/feature` — flag UI. Toggle a failure flag such as
  `adServiceFailure`, `cartServiceFailure`, or `productCatalogFailure`. Within a
  minute the resulting errors appear in Dash0 under Traces and Logs.

Leave the `port-forward` command running while you browse; press `Ctrl+C` to
stop it.

## 8.5 Browse the demo app and inject failures

The demo already runs a built-in load generator, so traffic flows into Dash0
without any action. To click through the storefront yourself and trigger errors
on demand, open it locally with a port-forward (also printed as the
`demo_app_access` output after apply):

```bash
aws eks update-kubeconfig --region us-east-1 --name dash0-lab-demo
kubectl -n otel-demo port-forward svc/frontend-proxy 8080:8080
```

Then in a browser:

- `http://localhost:8080` — storefront. Browse products, add to cart, check out
  to generate traces, metrics, and logs.
- `http://localhost:8080/feature` — flag UI. Toggle a failure flag such as
  `adServiceFailure`, `cartServiceFailure`, or `productCatalogFailure`. Within a
  minute the resulting errors appear in Dash0 under Traces and Logs.

Leave the `port-forward` command running while you browse; press `Ctrl+C` to
stop it.

## 8.5 Browse the demo app and inject failures

The demo already runs a built-in load generator, so traffic flows into Dash0
without any action. To click through the storefront yourself and trigger errors
on demand, open it locally with a port-forward (also printed as the
`demo_app_access` output after apply):

```bash
aws eks update-kubeconfig --region us-east-1 --name dash0-lab-demo
kubectl -n otel-demo port-forward svc/frontend-proxy 8080:8080
```

Then in a browser:

- `http://localhost:8080` — storefront. Browse products, add to cart, check out
  to generate traces, metrics, and logs.
- `http://localhost:8080/feature` — flag UI. Toggle a failure flag such as
  `adServiceFailure`, `cartServiceFailure`, or `productCatalogFailure`. Within a
  minute the resulting errors appear in Dash0 under Traces and Logs.

Leave the `port-forward` command running while you browse; press `Ctrl+C` to
stop it.

## 9. Destroy

1. **Run workflow**: action = `destroy`, confirm = `yes`.
2. Wait until **Overall result** is success and remaining resource counts are `0`.

The `dash0demo` S3 bucket is never deleted by the workflow. Delete it manually in the S3 console if you no longer need it.

``bash
aws eks update-kubeconfig --region us-east-1 --name dash0-lab-demo

# 1. Is the operator config Available?
kubectl get dash0operatorconfiguration -o yaml | grep -A15 "status:"

# 2. Is there a collector at all?
kubectl get daemonset,deployment -n dash0-system

# 3. What is the operator complaining about?
kubectl logs -n dash0-system -l app.kubernetes.io/name=dash0-operator --tail=60

# 4. Is any namespace monitored?
kubectl get dash0monitoring -A
```