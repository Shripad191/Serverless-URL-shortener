#!/bin/bash
# deploy.sh — Provisions the full serverless URL shortener (Free-Tier-safe settings).
# Usage: ./deploy.sh
set -euo pipefail

export AWS_REGION=$(aws configure get region)
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword)

export TABLE_NAME="url-shortener-${RANDOM_SUFFIX}"
export ROLE_NAME="url-shortener-lambda-role-${RANDOM_SUFFIX}"
export CREATE_FN="url-shortener-create-${RANDOM_SUFFIX}"
export REDIRECT_FN="url-shortener-redirect-${RANDOM_SUFFIX}"
export API_NAME="url-shortener-api-${RANDOM_SUFFIX}"

echo "Resource suffix: ${RANDOM_SUFFIX}"
echo "${RANDOM_SUFFIX}" > .last-suffix   # saved so cleanup.sh can find these resources later

# --- DynamoDB (provisioned mode = always-free tier eligible) ---
aws dynamodb create-table \
    --table-name "${TABLE_NAME}" \
    --attribute-definitions AttributeName=shortCode,AttributeType=S \
    --key-schema AttributeName=shortCode,KeyType=HASH \
    --billing-mode PROVISIONED \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5
aws dynamodb wait table-exists --table-name "${TABLE_NAME}"

# --- IAM role + policies ---
cat > /tmp/trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "lambda.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
EOF

aws iam create-role \
    --role-name "${ROLE_NAME}" \
    --assume-role-policy-document file:///tmp/trust-policy.json

aws iam attach-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

cat > /tmp/dynamodb-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["dynamodb:GetItem", "dynamodb:PutItem"],
    "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${TABLE_NAME}"
  }]
}
EOF

aws iam create-policy \
    --policy-name "${ROLE_NAME}-ddb-policy" \
    --policy-document file:///tmp/dynamodb-policy.json

aws iam attach-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${ROLE_NAME}-ddb-policy"

echo "Waiting for IAM role propagation..."
sleep 10

# --- Lambda functions ---
(cd lambda && zip -q ../create_function.zip create_function.py)
(cd lambda && zip -q ../redirect_function.zip redirect_function.py)

aws lambda create-function \
    --function-name "${CREATE_FN}" \
    --runtime python3.12 \
    --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}" \
    --handler create_function.lambda_handler \
    --zip-file fileb://create_function.zip \
    --environment "Variables={TABLE_NAME=${TABLE_NAME}}" \
    --timeout 10

aws lambda create-function \
    --function-name "${REDIRECT_FN}" \
    --runtime python3.12 \
    --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}" \
    --handler redirect_function.lambda_handler \
    --zip-file fileb://redirect_function.zip \
    --environment "Variables={TABLE_NAME=${TABLE_NAME}}" \
    --timeout 10

# --- API Gateway ---
API_ID=$(aws apigateway create-rest-api \
    --name "${API_NAME}" \
    --description "Serverless URL Shortener" \
    --query 'id' --output text)
echo "${API_ID}" >> .last-suffix

ROOT_ID=$(aws apigateway get-resources \
    --rest-api-id "${API_ID}" --query 'items[0].id' --output text)

SHORTEN_ID=$(aws apigateway create-resource \
    --rest-api-id "${API_ID}" --parent-id "${ROOT_ID}" \
    --path-part shorten --query 'id' --output text)

aws apigateway put-method --rest-api-id "${API_ID}" --resource-id "${SHORTEN_ID}" \
    --http-method POST --authorization-type NONE
aws apigateway put-method --rest-api-id "${API_ID}" --resource-id "${SHORTEN_ID}" \
    --http-method OPTIONS --authorization-type NONE

CODE_ID=$(aws apigateway create-resource \
    --rest-api-id "${API_ID}" --parent-id "${ROOT_ID}" \
    --path-part '{shortCode}' --query 'id' --output text)

aws apigateway put-method --rest-api-id "${API_ID}" --resource-id "${CODE_ID}" \
    --http-method GET --authorization-type NONE \
    --request-parameters method.request.path.shortCode=true

aws apigateway put-integration \
    --rest-api-id "${API_ID}" --resource-id "${SHORTEN_ID}" --http-method POST \
    --type AWS_PROXY --integration-http-method POST \
    --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${CREATE_FN}/invocations"

aws apigateway put-integration \
    --rest-api-id "${API_ID}" --resource-id "${CODE_ID}" --http-method GET \
    --type AWS_PROXY --integration-http-method POST \
    --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${REDIRECT_FN}/invocations"

# --- CORS preflight (OPTIONS) mock integration for /shorten ---
# Written as single-line commands deliberately: no backslash continuations means
# nothing to break if a paste tool reflows or reindents this block.
aws apigateway put-integration --rest-api-id "${API_ID}" --resource-id "${SHORTEN_ID}" --http-method OPTIONS --type MOCK --request-templates '{"application/json":"{\"statusCode\": 200}"}'

aws apigateway put-method-response --rest-api-id "${API_ID}" --resource-id "${SHORTEN_ID}" --http-method OPTIONS --status-code 200 --response-parameters method.response.header.Access-Control-Allow-Headers=false,method.response.header.Access-Control-Allow-Methods=false,method.response.header.Access-Control-Allow-Origin=false

cat > /tmp/cors-response-params.json << 'EOF'
{
  "method.response.header.Access-Control-Allow-Headers": "'Content-Type'",
  "method.response.header.Access-Control-Allow-Methods": "'POST,OPTIONS'",
  "method.response.header.Access-Control-Allow-Origin": "'*'"
}
EOF

aws apigateway put-integration-response --rest-api-id "${API_ID}" --resource-id "${SHORTEN_ID}" --http-method OPTIONS --status-code 200 --response-parameters file:///tmp/cors-response-params.json

aws lambda add-permission \
    --function-name "${CREATE_FN}" --statement-id apigw-create \
    --action lambda:InvokeFunction --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*"

aws lambda add-permission \
    --function-name "${REDIRECT_FN}" --statement-id apigw-redirect \
    --action lambda:InvokeFunction --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*"

aws apigateway create-deployment \
    --rest-api-id "${API_ID}" --stage-name prod

API_URL="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod"
echo ""
echo "✅ Deployed. API is live at: ${API_URL}"
echo "   Try:  curl -X POST ${API_URL}/shorten -H 'Content-Type: application/json' -d '{\"url\": \"https://aws.amazon.com\"}'"