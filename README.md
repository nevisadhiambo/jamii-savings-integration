# Jamii Integration — WSO2 Micro Integrator

A WSO2 MI 4.6.0 integration project implementing three REST APIs that demonstrate the three core integration styles: database-backed queries, HTTP reverse-proxy/gateway, and SOAP-to-REST transformation.

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

## What I'd Do Differently With More Time

- **Externalise credentials** — DSS data source credentials and any API keys moved to `deployment.toml` / Secure Vault instead of inline XML.
- **Unit tests** — add MI unit tests with mock services for each API resource (SOAP backend mock + JSONPlaceholder mock) so CI can run without external network access.
- **Move eligibility rules out of Synapse XML** — externalise to a separate microservice or rules engine so business stakeholders can update thresholds without touching integration code.
- **Rate-limiting** — add a `throttle` mediator on the proxy API to prevent upstream quota exhaustion on the customer backend.
- **Schema validation** — replace the hand-written `filter` chain in `LoanEligibilityAPI` with a `<validate>` mediator backed by a JSON Schema file, which would give richer, field-level error detail automatically.
- **OpenAPI metadata** — populate `src/main/wso2mi/resources/metadata/` with Swagger specs so the APIs are immediately importable into WSO2 API Manager for managed access.

---

## Assumptions Made

- The `AccountDataService` DSS is deployed separately and accessible by service name on the same MI runtime. Its underlying database has columns `account_number`, `balance`, `currency`, and `status`.
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
git clone <repo-url> jamii-integration
cd jamii-integration
```

**2. Build the CApp**
```bash
mvn clean install
```
This produces `target/jamii-integration-1.0.0.car`.

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

> **Note:** `AccountBalanceAPI` requires the `AccountDataService` DSS to be deployed and a database pre-seeded with account rows. Without it, balance requests return `503 DB_ERROR`.
