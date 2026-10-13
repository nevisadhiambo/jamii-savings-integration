# Jamii Integration — WSO2 Micro Integrator + API Manager

A WSO2 MI 4.6.0 integration project implementing three REST APIs that demonstrate the three core integration styles: database-backed queries, HTTP reverse-proxy/gateway, and SOAP-to-REST transformation — all published as managed APIs through WSO2 API Manager 4.4.0.

---

## Architecture Decisions & Trade-offs

### Three APIs, three integration styles

| API | Context | Style | Backend |
|-----|---------|-------|---------|
| `AccountBalanceAPI` | `GET /accounts/{accountNumber}/balance` | DB-backed (DSS) | SQLite via Data Service |
| `CustomerProxyAPI` | `GET /customers/{customerId}` | HTTP reverse proxy | JSONPlaceholder (HTTPS) |
| `LoanEligibilityAPI` | `POST /loans/eligibility` | SOAP-to-REST | DataAccess NumberConversion WSDL |

**Shared `ErrorResponseSequence`** — Rather than duplicating error-response logic in every API, a single reusable sequence handles all error cases. Callers set `vars.errorCode`, `vars.errorMessage`, and `vars.httpStatus` before invoking it. This keeps fault-handling uniform and reduces drift.

**`variable` mediator over `property`** — The newer Synapse `variable` mediator is used for all application-level state. Legacy `property` mediator is only kept where the runtime strictly requires it: capturing `MessageID` via `get-property()` (no Synapse Expression equivalent) and setting axis2-scoped transport controls (`HTTP_SC`, `messageType`, `Accept-Encoding`).

**HTTP Connector for REST, `call` for SOAP** — `CustomerProxyAPI` uses the MI HTTP connector (`http.get`) with `responseVariable` / `overwriteBody=false`, which keeps the original request payload intact while the backend response is held in a named variable. `LoanEligibilityAPI` uses the `call` mediator with a named SOAP 1.1 endpoint — the HTTP connector does not support SOAP, so this is the correct approach.

**Trade-off — JSONPlaceholder as customer backend** — A real deployment would call an internal CRM. JSONPlaceholder was chosen because it requires no auth, returns semantically rich user objects (address, company, geo), and is reliably available. The normalisation step (selecting only certain fields in `payloadFactory`) demonstrates how a gateway shapes a third-party response.

**Trade-off — in-line eligibility rules** — The loan decision logic (amount ≤ 500 000 KES, purpose ≠ "gambling") lives directly in the Synapse expression inside `LoanEligibilityAPI`. For production this would be externalised to a rules engine or a dedicated microservice; embedding it keeps the demo self-contained with no extra dependencies.

**Correlation IDs** — Every API accepts `X-Request-ID` / `X-Correlation-ID` from the caller or falls back to the Synapse `MessageID`. The ID flows through every log line and into every response envelope, making distributed tracing straightforward without an external tracing infrastructure.

---

## Part 2 — API Manager Integration

All three MI APIs are published as managed APIs in WSO2 API Manager 4.4.0. The apictl project files live under `apim/`.

### Security schemes

| API | Scheme | Detail |
|-----|--------|--------|
| `AccountBalanceAPI` | **OAuth2** (Client Credentials) | Scope: `read:accounts`. Account balance data is financial PII; OAuth2 ensures auditable client identity and per-scope access control. |
| `CustomerProxyAPI` | **API Key** (`X-API-Key` header) | Customer lookup is lower-sensitivity. API Key enforces subscription identity without the token-exchange overhead of OAuth2. |
| `LoanEligibilityAPI` | **OAuth2** (Client Credentials) | Scope: `write:loans`. Loan decisions are financially consequential; OAuth2 enables per-client audit trails and immediate credential revocation. |

### Throttling tiers

| API | Tier | Reason |
|-----|------|--------|
| `AccountBalanceAPI` | **Gold** | High-frequency balance reads by authenticated banking clients need adequate throughput while still protecting the MI/DB layer. |
| `CustomerProxyAPI` | **Bronze** | This API proxies to the external JSONPlaceholder service which has no published SLA; Bronze limits Jamii-driven traffic to avoid triggering upstream IP rate-limits or bans. |
| `LoanEligibilityAPI` | **Silver** | Each request triggers a synchronous SOAP call to the DataAccess backend; Silver moderates load on that third-party service without being as restrictive as Bronze. |

### Custom gateway mediation policy — `JamiiHeaderInject` (AccountBalanceAPI)

A custom Synapse-based gateway policy applied at the API level to `AccountBalanceAPI`:

- **Request flow** → injects `X-Jamii-Validated: true` to signal to MI that the caller has cleared APIM OAuth2 security checks.
- **Response flow** → injects `X-Powered-By: Jamii-APIM-Gateway` and `X-Jamii-API-Version: AccountBalanceAPI/1.0.0` for consumer-side observability and version negotiation without URL parsing.

Policy files: `apim/apis/AccountBalanceAPI/Policies/JamiiHeaderInject.yaml` (descriptor) and `JamiiHeaderInject.j2` (Synapse sequence Jinja2 template, rendered by APIM at import time).

### API Product — `JamiiiBankingPlatform`

All three APIs are grouped under a single API Product (`apim/api-products/JamiiiBankingPlatform/api-product.yaml`), exposed at `/jamii/v1`. A consuming application subscribes once to the product and gains access to all three routes. Per-API throttle tiers (Gold / Bronze / Silver) still apply per route; the product-level tier is Unlimited.

**Why one product?** The three APIs together form a complete banking workflow (look up customer → check balance → apply for loan). Grouping them avoids forcing consuming apps to manage three separate subscriptions, credential pairs, and approval workflows.

### Developer Portal — how a consuming application subscribes

1. **Discover** — navigate to `https://<apim-host>:9443/devportal` and search for `JamiiiBankingPlatform`.
2. **Create Application** — go to **Applications → Add New Application**, name it (e.g. `MyFinTechApp`), and select a throttle tier.
3. **Subscribe** — open `JamiiiBankingPlatform` → **Subscribe** → select the application → **Subscribe**.
4. **Get credentials**
   - **OAuth2 APIs** (Account Balance + Loan Eligibility): **Production Keys → Generate Keys** → copy the Consumer Key/Secret → call `POST https://<apim>:8243/token` with `grant_type=client_credentials&scope=read:accounts` (or `write:loans`) → use the returned Bearer token.
   - **API Key API** (Customer Proxy): **API Keys → Generate** → copy the key → pass as `X-API-Key` request header.
5. **Try it out** — use the built-in **Try Out** console in the Developer Portal, or Postman with the HTTPS gateway base URL `https://<apim>:8243/jamii/v1/`.

---

## CI/CD Pipeline

A single declarative `Jenkinsfile` handles the full delivery lifecycle for all three APIs:

```
Checkout → Build MI CAR → Package APIM projects → Run Synapse unit tests
  → [DEV] Start docker-compose stack → Deploy MI CAR → Deploy all 3 APIM APIs
  → Deploy JamiiiBankingPlatform API Product → Smoke tests → Teardown
  → [PROD] Manual approval gate → Deploy MI + APIM to production
```

The pipeline fails cleanly if **any** of the three API deployments fails — there is no silent partial-deploy. The docker-compose stack (`docker-compose.yml`) spins up MySQL + WSO2 MI + WSO2 APIM as the local/CI target environment.

### Jenkins setup checklist

| Requirement | Detail |
|-------------|--------|
| Agent label | `docker` |
| Tools on agent | Docker, Docker Compose v2, Java 17, Maven 3.8+, `apictl` in PATH |
| Credentials | `jamii-dev-mi-creds`, `jamii-dev-apim-creds`, `jamii-prod-mi-creds`, `jamii-prod-apim-creds` (all username/password) |
| Global env vars | `PROD_MI_HOST`, `PROD_MI_MGMT_PORT`, `PROD_APIM_HOST`, `PROD_APIM_PORT` |

---

## What I'd Do Differently With More Time

- **Externalise credentials** — DSS data source credentials and any API keys moved to `deployment.toml` / Secure Vault instead of inline XML.
- **Unit tests** — add MI unit tests with mock services for each API resource (SOAP backend mock + JSONPlaceholder mock) so CI can run without external network access.
- **Move eligibility rules out of Synapse XML** — externalise to a separate microservice or rules engine so business stakeholders can update thresholds without touching integration code.
- **Schema validation** — replace the hand-written `filter` chain in `LoanEligibilityAPI` with a `<validate>` mediator backed by a JSON Schema file, which gives richer, field-level error detail automatically.
- **Observability** — wire the correlation IDs into a centralised log aggregator (e.g. ELK) and expose MI metrics to Prometheus so the Grafana dashboard shows per-API latency and error rates.

---

## Assumptions Made

- The `AccountDataService` DSS is deployed on the same MI runtime and its underlying database has columns `account_number`, `balance`, `currency`, and `status`.
- The DataAccess NumberConversion SOAP service (`https://www.dataaccess.com/webservicesserver/`) is publicly reachable at runtime; if not, the loan eligibility API returns `503 SERVICE_UNAVAILABLE`.
- `customerId` values 1–999 are accepted by the validator. JSONPlaceholder only has 10 real users (IDs 1–10); IDs outside that range return 404, which the API maps to a clean `NOT_FOUND` error.
- No authentication or TLS client certificates are required to call the MI runtime during local development (default MI out-of-the-box configuration).

---

## How to Run Locally

### Prerequisites

| Tool | Version |
|------|---------|
| Java (JDK) | 17 |
| Maven | 3.8+ |
| WSO2 MI | 4.6.0 |

### Steps

**1. Clone and open the project**
```bash
git clone https://github.com/nevisadhiambo/jamii-savings-integration.git jamii-integration
cd jamii-integration
```

**2. Build the CApp**
```bash
mvn clean install
```
This produces `target/jamii-integration_1.0.0.car`.

**3. Deploy**

Option A — VSCode extension: use the *Build & Deploy* button in the WSO2 MI panel.

Option B — manually: copy the `.car` into `$MI_HOME/repository/deployment/server/carbonapps/` and start the server:
```bash
# Linux/macOS
$MI_HOME/bin/micro-integrator.sh
# Windows
$MI_HOME\bin\micro-integrator.bat
```

**4. Verify deployment**
```
GET http://localhost:9164/management/apis
```

**5. Test the APIs**

```bash
# Account balance
curl http://localhost:8290/accounts/ACC001/balance

# Customer proxy
curl http://localhost:8290/customers/1

# Loan eligibility
curl -X POST http://localhost:8290/loans/eligibility \
  -H "Content-Type: application/json" \
  -d '{"customerId":"C001","loanAmount":50000,"termMonths":12,"purpose":"business"}'
```

### Via docker-compose (with APIM)

```bash
# Start the full stack (MI + APIM + MySQL)
docker compose up -d --wait

# Import all APIs and the API Product into APIM
APIM_ENV_NAME=dev bash scripts/deploy-apim.sh
```

> **Note:** `AccountBalanceAPI` requires the `AccountDataService` DSS to be deployed and the `accounts` table pre-seeded. The `docker/mysql/init.sql` seed script handles this automatically when using docker-compose.
