# AWS 3-Tier Application with High Availability

Terraform-managed AWS infrastructure for a small 3-microservice web app
("Trailhead Boutique" — an AWS/Node.js reimagining of Google's Online
Boutique demo, trimmed from 11 services down to 3), fronted by load
balancers and Auto Scaling Groups, deployed through a CI/CD pipeline.

## Repo layout

```
app/                          Application source (3 Node.js microservices)
  frontend/                   Web UI (Express + EJS)
  productcatalogservice/      Product catalog REST API
  cartcheckoutservice/        Cart + checkout REST API (uses RDS Postgres)
  docker-compose.yml          Local dev environment
  README.md                   How to run locally & deploy to AWS

modules/
  vpc/                        VPC, public/private subnets (2 AZs), NAT, routing
  ec2/                        Reusable single-instance module (bastion host)
  asg/                        Reusable Auto Scaling Group + launch template
  alb/                        Reusable Application Load Balancer + target group
  eks/                        (unused by this deployment; kept for future use)
  ecs/                        (empty; kept for future use)

environment/dev/              The "dev" environment: wires the modules above
                               together, plus RDS, ECR, IAM, security groups,
                               ALBs and ASGs
  templates/                  EC2 user_data scripts (install Docker, run container)

state-bootstrap/               One-time setup: S3 bucket for Terraform remote state

.github/workflows/            CI/CD pipeline (see .github/workflows/README.md)
.tflint.hcl, .checkov.yaml    Linting / security-scanning config
```

## Architecture

- **Networking**: 1 VPC across 2 AZs — public subnets (ALBs + bastion),
  private "app" subnets (all 3 services' EC2 instances), private "db"
  subnets (RDS) — with NAT gateways for the private tier's outbound access
  (pulling images from ECR, etc).
- **Edge**: a public, internet-facing ALB in front of the frontend ASG, and
  an internal ALB (two listeners, ports 3000/3001) in front of the product
  catalog and cart/checkout ASGs. The internal ALB gives the frontend a
  stable DNS name to call instead of a private IP that would change every
  time an ASG replaces an instance.
- **Compute**: one Auto Scaling Group per service (2–4 t3.micro instances
  each, target-tracking on CPU), running a single Docker container per
  instance. A small bastion EC2 instance sits in the public subnet for SSH
  access into the now-private app tier.
- **Images**: built in CI and pushed to 3 ECR repositories; instances pull
  their image on boot via `user_data`.
- **Data**: a single RDS Postgres instance used by `cartcheckoutservice`.
- **Security groups**: public ALB open on 80 to the internet; frontend
  instances only reachable from the public ALB; internal ALB only reachable
  from the frontend instances (+ cart/checkout, for its catalog lookups);
  product catalog / cart-checkout instances only reachable from the internal
  ALB; RDS only reachable from the cart/checkout instances; SSH everywhere
  is bastion-only.
- **CI/CD**: GitHub Actions — format, validate, lint, security/vulnerability
  scanning (IaC + container images), a reviewable plan, a manual approval
  gate, then deploy. See `.github/workflows/README.md` for full details and
  one-time setup (OIDC role, secrets, environment protection rules).

See `app/README.md` for the application code and local dev instructions.

## Deploying

Normal path: open a PR (runs fmt/validate/lint/scan/plan for review) →
merge to `main` → approve the `production` environment gate in GitHub →
CI applies it.

Manual/local path, if you need it:

```bash
# One-time: create the remote state bucket
cd state-bootstrap
terraform init && terraform apply

# Then, per environment
cd ../environment/dev
terraform init
terraform apply -target=aws_ecr_repository.frontend \
                 -target=aws_ecr_repository.productcatalogservice \
                 -target=aws_ecr_repository.cartcheckoutservice \
                 -target=aws_iam_instance_profile.ec2_ecr_pull
# build & push the 3 images (see app/README.md), then:
terraform apply
```

## Known simplifications

This is a demo, not a production reference architecture:
- No WAF in front of the public ALB.
- Payment and shipping in `cartcheckoutservice` are mocked.
- `eks/` and `ecs/` modules exist for future exploration but aren't used
  by the `dev` environment.
- The deploy job's IAM role should be scoped down from broad resource
  access to least-privilege before this touches a real account.
