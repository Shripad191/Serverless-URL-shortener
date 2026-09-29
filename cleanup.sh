#!/bin/bash
# cleanup.sh — Deletes everything deploy.sh created, in the correct dependency order.
# Usage: ./cleanup.sh
set -euo pipefail

if [ ! -f .last-suffix ]; then
    echo "No .last-suffix file found — nothing to clean up, or run this from the same directory as deploy.sh"
    exit 1
fi

RANDOM_SUFFIX=$(sed -n '1p' .last-suffix)
API_ID=$(sed -n '2p' .last-suffix)

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
TABLE_NAME="url-shortener-${RANDOM_SUFFIX}"
ROLE_NAME="url-shortener-lambda-role-${RANDOM_SUFFIX}"
CREATE_FN="url-shortener-create-${RANDOM_SUFFIX}"
REDIRECT_FN="url-shortener-redirect-${RANDOM_SUFFIX}"

echo "Tearing down resources for suffix: ${RANDOM_SUFFIX}"

aws apigateway delete-rest-api --rest-api-id "${API_ID}" || true
aws lambda delete-function --function-name "${CREATE_FN}" || true
aws lambda delete-function --function-name "${REDIRECT_FN}" || true

aws iam detach-role-policy --role-name "${ROLE_NAME}" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || true
aws iam detach-role-policy --role-name "${ROLE_NAME}" \
    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${ROLE_NAME}-ddb-policy" || true
aws iam delete-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${ROLE_NAME}-ddb-policy" || true
aws iam delete-role --role-name "${ROLE_NAME}" || true

aws dynamodb delete-table --table-name "${TABLE_NAME}" || true

rm -f .last-suffix create_function.zip redirect_function.zip

echo "✅ Cleanup complete."
