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

<img width="1919" height="903" alt="06-lambda-functions" src="https://github.com/user-attachments/assets/c13d8ec8-fc51-49ef-bb28-3cc4ed29b680" />

*Two separate Lambda functions — `create` and `redirect` — each with their own runtime and permissions, per the single-responsibility design decision below.*

<img width="1919" height="908" alt="07-api-gateway-resources" src="https://github.com/user-attachments/assets/e62b127e-0035-4a84-b39f-74e1147e26fe" />

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

<img width="1475" height="755" alt="01-deploy sh-success" src="https://github.com/user-attachments/assets/3dad65a2-409f-4ab8-98ff-080171355f9d" />

---

## Test

**Create a short link:**
```bash
curl -X POST <API_URL>/shorten \
    -H "Content-Type: application/json" \
    -d '{"url": "https://aws.amazon.com"}'
```
Returns a JSON object containing the generated `shortCode`.

<img width="1472" height="755" alt="02-create-shorturl" src="https://github.com/user-attachments/assets/cb2227d5-5a6a-45f6-bea6-0e58b7138b4e" />


**Follow the short link** — paste `<API_URL>/<shortCode>` into a browser, or:
```bash
curl -D - -o /dev/null -s <API_URL>/<shortCode>
```
Returns `HTTP/2 302` with a `location` header pointing back to the original URL.

<img width="1919" height="966" alt="03-redirect-success" src="https://github.com/user-attachments/assets/e8ab01af-d90a-4f6b-a1c2-3a6a7afedcba" />

**Verify the failure paths** (missing URL, malformed URL, unknown short code):
```bash
curl -X POST <API_URL>/shorten -H "Content-Type: application/json" -d '{}'
curl -X POST <API_URL>/shorten -H "Content-Type: application/json" -d '{"url":"not-a-url"}'
curl -D - -o /dev/null -s <API_URL>/zzzzzz
```

<img width="1481" height="752" alt="04-error-handling" src="https://github.com/user-attachments/assets/7000f3d1-3a93-405a-b42e-b8d2327da77d" />

**Confirm the data landed in DynamoDB:**
```bash
aws dynamodb scan --table-name <your-table-name>
```

<img width="1919" height="905" alt="05-dynamodb-table" src="https://github.com/user-attachments/assets/38502be2-3426-415b-abe5-764292b5f6e8" />

---

## Tear Down

```bash
chmod +x cleanup.sh
./cleanup.sh
```
Deletes every resource created by `deploy.sh` (API Gateway, both Lambda functions, IAM role/policy, DynamoDB table), in the correct dependency order.

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
