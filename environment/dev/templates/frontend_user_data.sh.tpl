#!/bin/bash
set -euxo pipefail

dnf install -y docker
systemctl enable --now docker

aws ecr get-login-password --region ${aws_region} | docker login --username AWS --password-stdin ${ecr_registry}

docker pull ${image_uri}

docker rm -f frontend || true
docker run -d --name frontend \
  --restart unless-stopped \
  -p 80:80 \
  -e PORT=80 \
  -e PRODUCT_CATALOG_URL="${product_catalog_url}" \
  -e CART_CHECKOUT_URL="${cart_checkout_url}" \
  -e SESSION_SECRET="${session_secret}" \
  ${image_uri}
