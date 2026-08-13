#!/bin/bash
set -euxo pipefail

dnf install -y docker jq
systemctl enable --now docker

aws ecr get-login-password --region ${aws_region} | docker login --username AWS --password-stdin ${ecr_registry}

docker pull ${image_uri}

# Fetch DB credentials from Secrets Manager at boot
SECRET=$(aws secretsmanager get-secret-value \
  --region ${aws_region} \
  --secret-id ${db_secret_arn} \
  --query SecretString \
  --output text)

DB_USER=$(echo "$SECRET" | jq -r '.username')
DB_PASSWORD=$(echo "$SECRET" | jq -r '.password')

docker rm -f cartcheckoutservice || true
docker run -d --name cartcheckoutservice \
  --restart unless-stopped \
  -p 3001:3001 \
  -e PORT=3001 \
  -e DB_HOST="${db_host}" \
  -e DB_PORT="${db_port}" \
  -e DB_NAME="${db_name}" \
  -e DB_USER="$DB_USER" \
  -e DB_PASSWORD="$DB_PASSWORD" \
  -e DB_SSL=true \
  -e PRODUCT_CATALOG_URL="${product_catalog_url}" \
  ${image_uri}
