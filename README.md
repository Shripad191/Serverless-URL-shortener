# Serverless URL Shortener — AWS (API Gateway + Lambda + DynamoDB)

A fully serverless URL shortener built on AWS, provisioned entirely through the AWS CLI, and designed to run at **$0.00 on an AWS Free Tier account**.

Given a long URL, this service generates a short, unique code and redirects anyone who visits it back to the original link — the same pattern used by services like bit.ly and TinyURL.

---

## Architecture

```
                POST /shorten
   Client ──────────────────────▶  API Gateway  ──────▶  Lambda: create_function  ──────▶  DynamoDB
                                                                                         (shortCode → originalUrl)
                GET /{shortCode}
   Client ──────────────────────▶  API Gateway  ──────▶  Lambda: redirect_function ──────▶  DynamoDB
```

| Component | Role |
|---|---|
| **API Gateway** | Public HTTPS entry point; routes requests to the correct Lambda function and handles CORS |
| **AWS Lambda (`create_function`)** | Validates the submitted URL, generates a collision-safe 6-character short code, writes the mapping to DynamoDB |
| **AWS Lambda (`redirect_function`)** | Looks up a short code in DynamoDB and returns an HTTP 302 redirect to the original URL |
| **DynamoDB** | Stores `{ shortCode → originalUrl }` as a single-item, key-value lookup table |
| **IAM** | A single least-privilege execution role scoped to only `GetItem`/`PutItem` on this one table |

**Proof this architecture is real, not just a diagram:**

**Screenshot:** `docs/screenshots/06-lambda-functions.png`
*Two separate Lambda functions — `create` and `redirect` — each with their own runtime and permissions, per the single-responsibility design decision below.*

**Screenshot:** `docs/screenshots/07-api-gateway-resources.png`
*The actual configured routes: `POST`/`OPTIONS` on `/shorten`, `GET` on `/{shortCode}`.*

---

## Prerequisites

- An AWS account (Free Tier is sufficient)
- AWS CLI v2 installed and configured (`aws configure`) — or use AWS CloudShell, which needs no local setup
- `zip` available on your system

---

## Deploy

```bash
chmod +x deploy.sh
./deploy.sh
```

This provisions, in order: a DynamoDB table (provisioned capacity, Free-Tier-safe), an IAM role and least-privilege policy, both Lambda functions, and a complete API Gateway REST API with a `prod` stage — then prints your live API URL.

**Screenshot:** `docs/screenshots/01-deploy-success.png`

---

## Test

**Create a short link:**
```bash
curl -X POST <API_URL>/shorten \
    -H "Content-Type: application/json" \
    -d '{"url": "https://aws.amazon.com"}'
```
Returns a JSON object containing the generated `shortCode`.

**Screenshot:** `docs/screenshots/02-create-shorturl.png`

**Follow the short link** — paste `<API_URL>/<shortCode>` into a browser, or:
```bash
curl -D - -o /dev/null -s <API_URL>/<shortCode>
```
Returns `HTTP/2 302` with a `location` header pointing back to the original URL.

**Screenshot:** `docs/screenshots/03-redirect-success.png`

**Verify the failure paths** (missing URL, malformed URL, unknown short code):
```bash
curl -X POST <API_URL>/shorten -H "Content-Type: application/json" -d '{}'
curl -X POST <API_URL>/shorten -H "Content-Type: application/json" -d '{"url":"not-a-url"}'
curl -D - -o /dev/null -s <API_URL>/zzzzzz
```

**Screenshot:** `docs/screenshots/04-error-handling.png`

**Confirm the data landed in DynamoDB:**
```bash
aws dynamodb scan --table-name <your-table-name>
```

**Screenshot:** `docs/screenshots/05-dynamodb-table.png`

---

## Tear Down

```bash
chmod +x cleanup.sh
./cleanup.sh
```
Deletes every resource created by `deploy.sh` (API Gateway, both Lambda functions, IAM role/policy, DynamoDB table), in the correct dependency order.

---

## AWS Free Tier Notes

| Service | Free Tier type | Allowance |
|---|---|---|
| **Lambda** | Always Free, forever | 1,000,000 requests + 400,000 GB-seconds/month |
| **DynamoDB** | Always Free, **but only in `PROVISIONED` mode** | 25 GB storage + 25 RCU + 25 WCU/month |
| **API Gateway** | 12 Months Free only | 1,000,000 REST API calls/month |

This project deliberately uses DynamoDB in `PROVISIONED` mode (5 RCU / 5 WCU) rather than on-demand billing, since on-demand tables are billed per request from the very first request and are **not** covered by DynamoDB's always-free allowance.

---

## Design Decisions

- **Two separate Lambda functions, not one** — the create and redirect paths have different permissions, triggers, and failure modes; keeping them separate follows the single-responsibility principle and lets each be tuned independently.
- **HTTP 302 (not 301) redirects** — avoids browsers permanently caching a mapping that could later change, and keeps the door open for click-tracking analytics.
- **Conditional writes on short-code creation** — `ConditionExpression='attribute_not_exists(shortCode)'` prevents a random short-code collision from silently overwriting an existing mapping.
- **Least-privilege IAM** — the execution role can only `GetItem`/`PutItem` on this one table, never `dynamodb:*` across the account.
- **CORS support via a MOCK integration on `OPTIONS`** — lets a browser-based frontend call this API directly without a proxy server.

---

## Possible Extensions

- Click-count analytics via `update_item` + a CloudWatch dashboard
- TTL-based link expiration
- Custom/vanity short codes
- API Gateway usage plan for rate limiting
- A static frontend (S3 + CloudFront) instead of raw `curl` calls

---

## Tech Stack

`AWS Lambda` · `Amazon API Gateway` · `Amazon DynamoDB` · `AWS IAM` · `Python 3.12` · `AWS CLI`

## License

MIT
