# Trailhead Boutique — 3-microservice demo app

A trimmed-down, AWS-native reimplementation of Google's "Online Boutique" demo,
reduced from 11 microservices down to 3, and rewritten in a single stack
(Node.js + Express) instead of the original's five different languages.

## Services

| Service                | Language      | Port | Responsibility                                   |
|-------------------------|---------------|------|---------------------------------------------------|
| `frontend`               | Node/Express + EJS | 80   | Web UI: browse products, cart, checkout forms      |
| `productcatalogservice`  | Node/Express  | 3000 | REST API serving the product catalog               |
| `cartcheckoutservice`    | Node/Express  | 3001 | REST API for cart + checkout, persists to Postgres |

`cartcheckoutservice` combines the original demo's separate cart, checkout,
payment, and shipping services into one, with payment/shipping mocked
(no real charge is made, shipping is a flat rate) since this is a demo.

## Run it locally with Docker Compose

```bash
cd app
docker compose up --build
```

Then visit http://localhost:8080. Postgres, the catalog API, and the cart/checkout
API all come up together; the frontend talks to the other two over the compose network.

## Deploying to AWS (matches the Terraform in this repo)

The Terraform under `environment/dev` provisions:
- 3 ECR repositories (one per service)
- A public ALB in front of a frontend Auto Scaling Group, and an internal
  ALB in front of the product catalog and cart/checkout ASGs — instances
  pull their image from ECR and run it as a Docker container on boot
- A bastion host for SSH into the (now private) app tier
- An RDS Postgres instance that `cartcheckoutservice` connects to

The normal way to deploy this is through CI/CD (see
`.github/workflows/README.md`): open a PR, review the plan it posts, merge
to `main`, then approve the deployment in GitHub's Environments tab.

### Deploying manually, if you need to

Because instances need an image to already exist in ECR before they can
start successfully, do a first pass to create just the ECR repos and IAM,
then build/push, then apply everything else:

```bash
cd environment/dev
terraform init

# 1. Create the ECR repos + IAM first
terraform apply -target=aws_ecr_repository.frontend \
                 -target=aws_ecr_repository.productcatalogservice \
                 -target=aws_ecr_repository.cartcheckoutservice \
                 -target=aws_iam_instance_profile.ec2_ecr_pull

# 2. Build and push each image (repeat for each service)
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com

docker build -t <account-id>.dkr.ecr.us-east-1.amazonaws.com/dev-frontend:latest ../../app/frontend
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/dev-frontend:latest

docker build -t <account-id>.dkr.ecr.us-east-1.amazonaws.com/dev-productcatalogservice:latest ../../app/productcatalogservice
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/dev-productcatalogservice:latest

docker build -t <account-id>.dkr.ecr.us-east-1.amazonaws.com/dev-cartcheckoutservice:latest ../../app/cartcheckoutservice
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/dev-cartcheckoutservice:latest

# 3. Apply everything else (ALBs, ASGs, RDS, security groups, bastion)
terraform apply
```

`terraform output frontend_url` gives you the public ALB's URL once the ASG
instances finish their `user_data` boot script and pass their first health
check (usually 1-2 minutes).

### Redeploying after a code change

Push a new image with the same `:latest` tag, then trigger an instance
refresh so the ASG replaces its instances with fresh ones that pull the new
image on boot:

```bash
aws autoscaling start-instance-refresh --auto-scaling-group-name dev-frontend
```

(or `dev-productcatalog` / `dev-cartcheckout`). The CI/CD pipeline's deploy
job does the build-and-push step automatically; a plain `terraform apply`
of an unchanged plan won't restart running instances on its own since the
launch template's `:latest` tag reference doesn't change — an instance
refresh (or a `terraform apply` right after the image is pushed, which
triggers the ASG's own rolling refresh via `instance_refresh` on the launch
template) is what actually rolls it out.

