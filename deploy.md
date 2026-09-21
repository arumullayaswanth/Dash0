# Deploy — steps only

Values you will reuse:

- `OWNER/REPO` = `arumullayaswanth/Dash0`
- OIDC subject = `repo:arumullayaswanth/Dash0:*`
- `AWS_REGION` = `us-east-1`
- `TF_STATE_BUCKET` = `dash0demo`
- `TF_STATE_KEY` = `dash0-lab/demo/terraform.tfstate`

## 1. Collect Dash0 values

1. Sign in to <https://app.dash0.com>.
2. **Settings** → **Endpoints** → copy **OTLP/gRPC** → save as `DASH0_OTLP_GRPC_ENDPOINT`.
3. Same page → copy **API** → save as `DASH0_API_ENDPOINT`.
4. Open the dataset selector → pick or create `demo` → save as `DASH0_DATASET`.
5. **Settings** → **Auth Tokens** → **Create token** → name `github-dash0-eks-demo`.
6. Click **Copy** and keep the dialog open until Step 5.2.

## 2. Create the S3 state bucket (AWS Console)

1. AWS Console → set Region to `us-east-1`.
2. **S3** → **Create bucket**.
3. **Bucket name** = `dash0demo`.
4. **Block all public access** = on.
5. **Bucket Versioning** = Enable.
6. **Default encryption** = SSE-S3.
7. Click **Create bucket**.

## 3. Create the AWS OIDC provider

1. **IAM** → **Identity providers** → **Add provider**.
2. Type = **OpenID Connect**.
3. Provider URL = `https://token.actions.githubusercontent.com` → **Get thumbprint**.
4. Audience = `sts.amazonaws.com`.
5. Click **Add provider**.

## 4. Create the AWS role

1. **IAM** → **Roles** → **Create role**.
2. Trusted entity = **Web identity**.
3. Identity provider = `token.actions.githubusercontent.com`, Audience = `sts.amazonaws.com`.
4. **Next** → attach **PowerUserAccess** and **IAMFullAccess** → **Next**.
5. Name = `github-dash0-eks-demo` → **Create role**.
6. Open the role → **Trust relationships** → **Edit trust policy**.
7. Paste this, replacing `ACCOUNT_ID`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
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
9. Copy the role **ARN** → save as `AWS_ROLE_ARN`.

## 5. Configure GitHub

### 5.1 Add repository variables

Repo → **Settings** → **Secrets and variables** → **Actions** → **Variables** tab → **New repository variable** for each row:

| Name | Value |
|---|---|
| `AWS_ROLE_ARN` | role ARN from Step 4.9 |
| `AWS_REGION` | `us-east-1` |
| `TF_STATE_BUCKET` | `dash0demo` |
| `TF_STATE_KEY` | `dash0-lab/demo/terraform.tfstate` |
| `DASH0_OTLP_GRPC_ENDPOINT` | from Step 1.2 |
| `DASH0_API_ENDPOINT` | from Step 1.3 |
| `DASH0_DATASET` | `demo` |

### 5.2 Add repository secret

Same page → **Secrets** tab → **New repository secret**:

| Name | Value |
|---|---|
| `DASH0_AUTH_TOKEN` | token from Step 1.6 |

## 6. Apply

1. Repo → **Actions** → **Dash0 EKS lifecycle** → **Run workflow**.
2. action = `apply`.
3. profile = `core`.
4. confirm = `apply:core`.
5. delete_backend = `false`.
6. Click **Run workflow**.
7. Wait until **Overall result** is success.

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

## 9. Change profile

1. **Run workflow**: action = `apply`, profile = `<name>`, confirm = `apply:<name>`, delete_backend = `false`.

## 10. Destroy

1. **Run workflow**: action = `destroy`, profile = the applied profile, confirm = `destroy:<profile>`, delete_backend = `false`.
2. Wait until **Overall result** is success and remaining resource counts are `0`.

## 11. Final destroy (also delete the bucket)

1. **Run workflow**: action = `destroy`, profile = the applied profile, confirm = `destroy:<profile>`, delete_backend = `true`.
