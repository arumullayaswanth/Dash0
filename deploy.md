# Deploy — steps only

Values you will reuse:

- `OWNER/REPO` = `arumullayaswanth/Dash0`
- `ACCOUNT_ID` = `713939171080`
- OIDC subject = `repo:arumullayaswanth/Dash0:*`
- `AWS_REGION` = `us-east-1`
- `TF_STATE_BUCKET` = `dash0demo`

## 1. Collect Dash0 values

1. Sign in to <https://app.dash0.com>.
2. **Settings** → **Endpoints** → find the **OTLP/gRPC** row → copy it → save as `DASH0_OTLP_GRPC_ENDPOINT`.
   - Must look like `ingress.us-west-2.aws.dash0.com:4317`.
   - No `https://`, no URL path. Do not use the OTLP/HTTP row.
3. Same page → copy **API** → save as `DASH0_API_ENDPOINT`.
   - Must look like `https://api.us-west-2.aws.dash0.com`.
4. **Settings** → **Auth Tokens** → **Create token** → name `github-dash0-eks-demo`.
5. Click **Copy** and keep the dialog open until Step 5.2.

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

This provider must exist. Without it the trust policy in Step 4 still saves, but every run fails with `Not authorized to perform sts:AssumeRoleWithWebIdentity`.

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

8. Click **Update policy**.
9. Reopen the **Trust relationships** tab and confirm the JSON shown matches what you pasted. If it does not, the save did not apply.
10. Copy the role **ARN** from the role summary → save as `AWS_ROLE_ARN`. It should read `arn:aws:iam::713939171080:role/github-dash0-eks-demo`.

Checklist if a run fails with `Not authorized to perform sts:AssumeRoleWithWebIdentity`:

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

Repo → **Settings** → **Secrets and variables** → **Actions** → **Variables** tab → **New repository variable** for each row:

| Name | Value |
|---|---|
| `AWS_ROLE_ARN` | `arn:aws:iam::713939171080:role/github-dash0-eks-demo` |
| `AWS_REGION` | `us-east-1` |
| `TF_STATE_BUCKET` | `dash0demo` |
| `DASH0_OTLP_GRPC_ENDPOINT` | from Step 1.2, e.g. `ingress.us-west-2.aws.dash0.com:4317` |
| `DASH0_API_ENDPOINT` | from Step 1.3, e.g. `https://api.us-west-2.aws.dash0.com` |

`TF_STATE_KEY` and `DASH0_DATASET` are hardcoded in the workflow; do not add them.

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

1. In the run **Summary**, note `bastion_instance_id`.
2. AWS Console → **Systems Manager** → **Session Manager** → **Start session**.
3. Select the matching instance → **Start session**.
4. Run:
   - `kubectl get nodes -o wide`
   - `kubectl get pods -A`
   - `kubectl get pods -n otel-demo`

## 9. Destroy

1. **Run workflow**: action = `destroy`, confirm = `yes`.
2. Wait until **Overall result** is success and remaining resource counts are `0`.

The `dash0demo` S3 bucket is never deleted by the workflow. Delete it manually in the S3 console if you no longer need it.
