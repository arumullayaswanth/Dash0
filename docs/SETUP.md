# Setup

The supported setup and operating procedure is the repository-root [deploy.md](../deploy.md).

That guide covers the only manual work required once: creating the S3 state bucket in the AWS Console, creating/verifying the AWS GitHub OIDC provider and repository-restricted IAM role, and adding the repository variables and Dash0 token secret.

After that, use the single **Dash0 EKS lifecycle** workflow under GitHub Actions:

| Goal | action | confirm |
|---|---|---|
| Preview changes | `plan` | `no` |
| Create the demo | `apply` | `no` |
| Remove live resources | `destroy` | `yes` |

Do not run local Terraform, Helm, kubectl, or AWS CLI commands for routine operation. The workflow verifies the manually created backend bucket, saves and applies exact plans, checks EKS and Dash0, performs ordered teardown, checks owned AWS orphans, and publishes the result and resource counts in GitHub Summary.
