# CI/CD pipeline

`.github/workflows/terraform-deploy.yml` runs on every PR/push touching
`environment/`, `modules/`, `state-bootstrap/`, or `app/`, in this order:

1. **Format** — `terraform fmt -check -recursive`
2. **Validate** — `terraform init -backend=false && terraform validate`, run
   independently for every module and environment (matrix job)
3. **Lint** — [TFLint](https://github.com/terraform-linters/tflint) with the
   AWS ruleset (`.tflint.hcl`) — catches things fmt/validate don't, like
   deprecated syntax or unused variables
4. **Security checks & vulnerability scanning**
   - **IaC**: [Checkov](https://www.checkov.io/) (`.checkov.yaml`) and Trivy's
     config scanner, both uploaded as SARIF to the repo's Security tab
   - **Container images**: each of the 3 service images is built and scanned
     with Trivy for CRITICAL/HIGH CVEs before it's ever pushed anywhere
5. **Plan** — `terraform plan`, posted as a PR comment and in the job summary
   so it can actually be reviewed, then saved as a build artifact
6. **Manual approval** — the `deploy` job targets a `production` GitHub
   Environment. See setup below — this is what makes the pipeline stop and
   wait for a human before touching AWS.
7. **Deploy** — applies ECR/IAM first, builds and pushes the 3 images, then
   applies the exact plan that was reviewed in step 5.

## One-time repo setup

**1. An OIDC role in AWS** (no long-lived AWS keys in GitHub):

```bash
# Trust policy allowing GitHub Actions to assume this role
aws iam create-role --role-name github-actions-terraform \
  --assume-role-policy-document file://trust-policy.json
```

Where `trust-policy.json` trusts `token.actions.githubusercontent.com` scoped
to `repo:<your-org>/<your-repo>:*` (see GitHub's
[OIDC docs](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)).
Attach whatever policy grants the permissions Terraform needs (EC2, ALB, ASG,
RDS, ECR, IAM, VPC — broadly, admin over this app's resources).

**2. Repo secrets** (Settings → Secrets and variables → Actions):

| Secret                  | Purpose                                   |
|--------------------------|--------------------------------------------|
| `AWS_OIDC_ROLE_ARN`      | The OIDC role ARN from step 1              |
| `TF_VAR_DB_PASSWORD`     | RDS master password                        |
| `TF_VAR_SESSION_SECRET`  | Frontend session-cookie signing secret     |

**3. The manual-approval gate** (Settings → Environments → New environment,
named `production`):
- Enable **Required reviewers** and add whoever should approve deployments.
- Optionally restrict which branches can deploy to it (`main` only).

Once that's set up, pushing to `main` runs the full pipeline through `plan`,
then pauses on `deploy` until an approver clicks Approve in the Environments
tab — nothing touches AWS before that.

## Notes / things to tighten before a real deployment

- `.checkov.yaml` skips a couple of checks with documented rationale (public
  ALB ingress, WAF). Revisit `CKV2_AWS_28` (attach a WAF) for anything beyond
  a demo.
- The IAM policy attached to the deploy role above should be scoped down
  from broad admin to just what these resources need.
- `admin_cidr` (bastion SSH) defaults to VPC-internal only; set it to your
  own IP via `-var` if you need external SSH access.
