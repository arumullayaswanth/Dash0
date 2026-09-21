# Setup

The supported setup and operating procedure is the repository-root [deploy.md](../deploy.md).

That guide covers the only manual work required once: creating the S3 state bucket in the AWS Console, creating/verifying the AWS GitHub OIDC provider and repository-restricted IAM role, and adding the repository variables and Dash0 token secret.

After that, use the single **Dash0 EKS lifecycle** workflow under GitHub Actions:

| Goal | action | profile | confirm | delete_backend |
|---|---|---|---|---|
| Preview core | `plan` | `core` | empty | `false` |
| Create core | `apply` | `core` | `apply:core` | `false` |
| Create observability profile | `apply` | `observability` | `apply:observability` | `false` |
| Remove live resources | `destroy` | applied profile | `destroy:PROFILE` | `false` |
| Final removal including state bucket | `destroy` | applied profile | `destroy:PROFILE` | `true` |

Do not run local Terraform, Helm, kubectl, or AWS CLI commands for routine operation. The workflow verifies the manually created backend bucket, saves and applies exact plans, checks EKS and Dash0, performs ordered teardown, checks owned AWS orphans, and publishes the result and resource counts in GitHub Summary.
