#!/bin/bash
set -euxo pipefail

dnf install -y docker
systemctl enable --now docker

aws ecr get-login-password --region ${aws_region} | docker login --username AWS --password-stdin ${ecr_registry}

docker pull ${image_uri}

docker rm -f productcatalogservice || true
docker run -d --name productcatalogservice \
  --restart unless-stopped \
  -p 3000:3000 \
  -e PORT=3000 \
  ${image_uri}
