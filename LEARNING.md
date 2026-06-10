# Cloud Resume Challenge — Learning Notes

A running record of concepts learned, with explanations in plain language.

---

## Contents

- [Session 1 — 2026-06-08](#session-1--2026-06-08) — static site live over HTTPS on a custom domain
  (S3 · CloudFront/OAC · ACM · Cloudflare DNS · IAM/CLI basics · budgets)
- [Session 2 — 2026-06-09](#session-2--2026-06-09) — serverless visitor counter + alerting
  (DynamoDB · Lambda · API Gateway · CORS · CloudWatch→SNS→PagerDuty)
- [Session 3 — 2026-06-10](#session-3--2026-06-10) — security audit, Slack alerts, tests, IaC
  (Access Analyzer · policy validation · PagerDuty→Slack · pytest/moto ·
   smoke tests · throttling · Git/GitHub · Terraform · commit signing)

### Concepts index (for review)

| Topic | Where |
|---|---|
| IAM: users/MFA/keys · least privilege · Access Analyzer | S1 · S2 · S3 |
| S3: hosting, bucket policies, Block Public Access | S1 |
| CloudFront, OAC, TLS/ACM, cache invalidation | S1 · S2 (deploy) |
| DNS: registrar, CNAME flattening, proxied vs DNS-only | S1 |
| DynamoDB: items, partition key, on-demand, atomic ADD, Decimal | S2 · S3 (tests) |
| Lambda: handler/event/context, exec role, packaging | S2 · S3 (Terraform) |
| API Gateway: routes, AWS_PROXY, stages, throttling | S2 · S3 |
| CORS: preflight, gateway vs Lambda duties | S2 · S3 (smoke) |
| Monitoring: CloudWatch alarms, SNS, PagerDuty, Slack | S2 · S3 |
| Testing: pytest, fixtures/markers, moto, smoke vs unit | S3 |
| Git/GitHub: monorepo, secrets vs identifiers | S3 |
| Terraform: state, plan/apply, drift, import, variables | S3 |
| Commit signing: SSH keys, Verified badge, rulesets | S3 |

---

## Session 1 — 2026-06-08

**What we built:** a résumé website, live and global over HTTPS on a custom
domain — `https://abhijitraj.me` — backed by AWS S3 + CloudFront, with the
domain on Cloudflare.

### Architecture so far

```
        ┌───────────────────────────┐
        │          Visitor          │
        │      (browser anywhere)    │
        └─────────────┬─────────────┘
                      │  asks DNS: where is abhijitraj.me?
                      ▼
        ┌───────────────────────────┐
        │      Cloudflare DNS        │   apex + www, "DNS only" (grey cloud)
        │  abhijitraj.me / www.*     │   apex works via CNAME flattening
        └─────────────┬─────────────┘
                      │  → points to the CloudFront distribution
                      │  HTTPS  (TLS cert issued by AWS ACM in us-east-1)
                      ▼
        ┌───────────────────────────┐
        │        CloudFront          │   global CDN, 600+ edge locations
        │  dist E2N3X21KFIF3UP       │   • HTTP → HTTPS redirect
        │  d2g5lzoyakz4an.cf.net     │   • default root object = index.html
        └─────────────┬─────────────┘   • TLS policy TLSv1.2_2021
                      │  OAC: signed request, ONLY this distribution may read
                      ▼
        ┌───────────────────────────┐
        │         S3 bucket          │   PRIVATE — Block Public Access ON
        │   abhijitraj-resume-crc    │   region: ap-south-1 (Mumbai)
        │   index.html · css/ · js/  │   no public access at all
        └───────────────────────────┘

Before CloudFront (earlier in the session): visitor → public S3 website
endpoint over plain HTTP. CloudFront added HTTPS + global caching AND let us
lock the bucket back to private.
```

---

### Concepts

#### Identity & access
- **Root account vs IAM user** — the root account owns everything and can't be
  restricted; you almost never use it. Daily work uses an **IAM user**
  (`abhijit-admin`) with its own permissions. If an IAM user leaks, you revoke
  it without losing the whole account.
- **MFA (multi-factor auth)** — a second factor (a rotating 6-digit code) on top
  of the password. Our IAM user signs in with password **+** MFA.
- **Console credentials vs access keys** — *console login* = human types
  password + MFA in a browser. *Access key* (an `AKIA…` ID + a 40-char secret) =
  a machine credential the CLI/SDKs use, no browser, no MFA prompt. That's why
  the secret is sensitive — guard it, one per machine, rotate it.
- **ARN (Amazon Resource Name)** — a globally unique ID for any AWS resource:
  `arn:partition:service:region:account-id:resource`. Used to reference
  resources exactly (e.g. in policies). Examples:
  `arn:aws:s3:::abhijitraj-resume-crc`,
  `arn:aws:cloudfront::695331051459:distribution/E2N3X21KFIF3UP`.

#### AWS CLI
- `~/.aws/credentials` holds the access key; `~/.aws/config` holds region +
  output format. `aws configure` writes them.
- `aws sts get-caller-identity` = "who am I?" — confirms the CLI is wired up.
- **`s3` vs `s3api`** — `aws s3` = friendly high-level commands (`mb`, `sync`,
  `website`). `aws s3api` = low-level, one-to-one with the raw API
  (`put-bucket-policy`, `put-public-access-block`). Use whichever fits.
- **Regions** — most resources live in one region (our bucket: `ap-south-1`).
  Some things are global or pinned: **CloudFront certs must be in `us-east-1`**.

#### S3 (storage + static hosting)
- **Bucket / object** — a bucket is a container; objects are the files. Bucket
  names are globally unique.
- **Static website hosting** — tells S3 to act like a web server and serve an
  **index document** (`index.html`).
- **Two independent switches for "public website":**
  1. **Block Public Access** (4 toggles) must be **off** to *allow* public rules.
  2. A **bucket policy** must actually *grant* public read.
  Hosting alone returns **403** until the policy grants read → then **200**.
- **Bucket policy anatomy** — JSON: `Effect` (Allow/Deny), `Principal` (who; `*`
  = everyone), `Action` (`s3:GetObject` = read an object), `Resource` (which
  objects; `arn:…:bucket/*` = everything inside).
- **Website endpoint vs REST endpoint** — `*.s3-website.*` is the public web
  endpoint (needs a public bucket). `*.s3.*` is the REST/API endpoint (works
  with CloudFront OAC + a **private** bucket). We chose REST + OAC.
- **Content-Type** — `aws s3 sync` auto-sets MIME types by extension so
  `.css`/`.js` are served correctly.

#### CloudFront (CDN + HTTPS)
- **CDN / edge locations** — caches your site at 600+ locations worldwide so
  visitors load it from nearby; also serves HTTPS.
- **Distribution / origin** — the distribution is the CDN config; the *origin*
  is where the real content lives (our S3 bucket).
- **OAC (Origin Access Control)** — lets CloudFront read a **private** bucket via
  signed requests, scoped to that one distribution. This let us delete the
  public bucket policy and turn Block Public Access back **on**.
- **Default root object** — what `/` serves (`index.html`); needed with the REST
  origin.
- **Viewer protocol policy** — set to redirect **HTTP → HTTPS**.
- **Security policy** — which TLS versions CloudFront accepts. Chose
  **TLSv1.2_2021** (supports TLS 1.2 *and* 1.3) for broad browser compatibility,
  over the TLS-1.3-only default.
- **Cost** — chose **Pay-as-you-go** (classic distribution, maps to IaC later;
  effectively free under the always-free 1 TB/10M-requests tier). Turned **WAF
  off** (it carries a ~$14/mo base cost). Distributions take ~5–15 min to deploy.

#### TLS / HTTPS / ACM
- **ACM = AWS Certificate Manager** — provisions and auto-renews free TLS certs.
- **Why us-east-1** — CloudFront only reads certs from ACM in `us-east-1`,
  regardless of where the origin is. (A regional service like an ALB would need
  the cert in its own region.)
- **DNS validation** — to prove you own the domain, ACM gives **CNAME records**
  you add to DNS; once it sees them, the cert flips to **Issued**.

#### DNS & domains
- **Registrar** — where you buy the domain. **Cloudflare** sells at-cost (~$10
  for `.com`, free WHOIS privacy); Route 53 is ~$14. We bought `abhijitraj.me`
  on Cloudflare.
- **Record types** — `A` (→ IP), `CNAME` (→ another hostname). The **apex** (root
  `abhijitraj.me`) can't normally be a CNAME, but Cloudflare's **CNAME
  flattening** makes it work by resolving the target to IPs.
- **Proxied (orange cloud) vs DNS only (grey cloud)** — proxied routes traffic
  *through* Cloudflare's CDN; DNS only just answers the lookup. We used **DNS
  only** so **CloudFront** does the CDN/TLS (avoids stacking two CDNs).
- **Alternate domain names (CNAMEs) on CloudFront** — you must list your custom
  domains on the distribution *and* attach a matching cert, or CloudFront won't
  answer for that hostname.
- **Cloudflare vs CloudFront for HTTPS** — Cloudflare could give free HTTPS by
  proxying, but it needs a *public* bucket and leaves the origin leg unencrypted.
  CloudFront + OAC keeps the bucket private end-to-end — and it's the skill the
  challenge teaches.

#### Ops & good habits
- **Billing budget + alert** — a near-zero-cost safety net: AWS Budgets emails
  you if monthly spend crosses a threshold (we set **$6 ≈ ₹500**). The account
  bills in **USD** (it's a global AWS account, not an India/AISPL INR one).
- **Multi-account (AWS Organizations)** — the "proper" way to isolate prod from
  experiments. We chose to stay **lean** (single account) for now since there
  are no other AWS workloads yet; adopt Organizations when real prod arrives.
- **Secret handling** — never paste secrets into logs/chat. Techniques used:
  copy from the vault → paste via clipboard; download the access-key **CSV** and
  let a script read it into config; only ever print *lengths*, not values.

---

### CLI commands used (quick reference)

```bash
# Identity
aws sts get-caller-identity

# S3 lifecycle (the CLI "redo" pass)
aws s3 mb s3://BUCKET --region ap-south-1
aws s3api put-public-access-block --bucket BUCKET \
  --public-access-block-configuration BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false
aws s3 website s3://BUCKET --index-document index.html
aws s3api put-bucket-policy --bucket BUCKET --policy file://aws/bucket-policy.json
aws s3 sync ./website s3://BUCKET
aws s3 rm s3://BUCKET --recursive   # teardown: empty
aws s3 rb s3://BUCKET               # teardown: remove bucket

# ACM certificate (DNS validation)
aws acm request-certificate --domain-name abhijitraj.me \
  --subject-alternative-names www.abhijitraj.me --validation-method DNS --region us-east-1
aws acm describe-certificate --certificate-arn ARN --region us-east-1
aws acm wait certificate-validated --certificate-arn ARN --region us-east-1

# CloudFront
aws cloudfront get-distribution --id DIST_ID
aws cloudfront wait distribution-deployed --id DIST_ID

# Budgets
aws budgets describe-budgets --account-id ACCOUNT_ID
```

---

### Gotchas worth remembering
- Static hosting **on** but objects still **403** → you forgot the bucket policy
  (two separate switches).
- CloudFront cert dropdown empty in ap-south-1 → certs must be in **us-east-1**.
- Apex domain won't take a CNAME on most DNS hosts → Cloudflare flattening (or
  Route 53 ALIAS) solves it.
- Custom domain returns CloudFront error → you didn't add it as an **alternate
  domain name** on the distribution.
- WAF and the "Legacy clients / dedicated IP" options carry real monthly costs —
  leave them off for a résumé.

---

## Session 2 — 2026-06-09

**What we built:** the visitor counter back end (database → function → API → JS),
turning the static résumé into a real serverless **application**, plus
**monitoring/alerting** to PagerDuty.

### Architecture now

```
   Visitor (browser)
        │  https://abhijitraj.me
        ▼
   Cloudflare DNS ─► CloudFront (HTTPS, CDN) ─► private S3 (HTML/CSS/JS)
        │
        │  js/counter.js  ──POST /count──►  API Gateway (HTTP API)
        │                                        │  AWS_PROXY
        │                                        ▼
        │                                   Lambda (Python, boto3)
        │                                        │  UpdateItem (atomic ADD)
        │                                        ▼
        │                                   DynamoDB  { id:"views", views:N }
        │                                        │
        ▼                                        ▼  count returned → JS shows it
   "viewed N times"

   Monitoring:
   Lambda error / API 5xx ─► CloudWatch Alarm ─► SNS topic ─► PagerDuty ─► incident
                                  (OK state) ───────────────► auto-resolves
```

*(Updated 2026-06-10: PagerDuty now fans out to Slack — see Session 3 diagram.)*

### Concepts

#### DynamoDB (NoSQL database)
- **NoSQL / serverless** — store **items** (JSON-like) retrieved by a **key**, not
  rows/SQL. No servers to manage; scales automatically.
- **Partition key** — the primary lookup key (`id`). Our whole "DB" is one item:
  `{ "id": "views", "views": N }`.
- **On-demand (PAY_PER_REQUEST)** capacity — no capacity planning, ~$0 at our
  scale; the sensible default for spiky/low traffic.
- **Typed attributes** — the API represents every value as a type pair:
  `{"S": "views"}` (String), `{"N": "0"}` (Number — numbers travel as strings).
- **Atomic increment** — `update_item` with `ADD` does read-increment-write in a
  single atomic op, so concurrent visitors can't clobber the count (vs a
  read-then-write race). `ExpressionAttributeNames`/`Values` (`#v`, `:inc`) are
  placeholders that dodge reserved words.

#### Lambda (serverless compute)
- A **function** that runs on demand — no server. Pick a **runtime** (Python
  3.14), write a **handler** (`lambda_function.lambda_handler`).
- **Execution role** — a Lambda runs **as an IAM role**, not as you. By default
  it can only write logs; it can't touch DynamoDB until you grant it. We saw the
  exact failure (`AccessDeniedException ... not authorized to perform
  dynamodb:UpdateItem`) then fixed it with a **least-privilege** inline policy
  (only `UpdateItem`/`GetItem`, only on our table).
- **boto3** — the AWS SDK for Python; `boto3.resource("dynamodb").Table(...)`.
- **Deploy** = zip the code + `update-function-code`. **Test** = `lambda invoke`
  (or the console "Test" button) — invoke in isolation before adding the API.

#### IAM, again — least privilege in practice
- "Nothing can touch anything unless explicitly allowed." The Lambda's role is a
  separate identity; the policy scopes it to one action on one resource.

#### API Gateway (the public front door)
- **HTTP API vs REST API** — HTTP API (v2) is newer, ~70% cheaper, lower latency,
  built-in CORS; REST API (v1) has more features (API keys, usage plans, request
  validation). We used **HTTP API**. *"HTTP API vs REST API" is the product tier,
  not whether the API is RESTful* — ours still serves a REST-style `POST /count`.
- **Integration** (`AWS_PROXY`) — the link from the API to the Lambda; API Gateway
  passes the request through and returns the function's response.
- **Route** — method + path (`POST /count`) → the integration.
- **Stage** — a deployment (`$default` with auto-deploy = live on every change).
- **Invoke permission** — the API needs `lambda:InvokeFunction` permission on the
  function (the console adds it automatically; via CLI you add it yourself).

#### GET vs POST (REST semantics)
- **GET should be *safe*** (no side effects); anything that **mutates** state
  should be **POST/PUT/PATCH**. Our call increments the counter → **POST**.
- Two real downsides of GET-for-a-counter: **caching** (a cached GET means the
  increment never reaches the server / stale number) and **accidental triggers**
  (prefetchers, bots, scanners fire GETs → inflated count). POST avoids both.

#### CORS (Cross-Origin Resource Sharing)
- A browser security rule: a page on origin A (`abhijitraj.me`) calling a
  different origin B (the API) is blocked **unless B says it's allowed** via
  `Access-Control-Allow-Origin`. Also `-Allow-Methods` / `-Allow-Headers`.
- For **preflight** (an `OPTIONS` request the browser sends first for non-simple
  requests), HTTP API answers automatically when CORS is configured — and it
  **overrides** any CORS headers the Lambda returns, so configure it in *one*
  place (the API).

#### Front-end integration + deploy
- `fetch(url, { method: "POST" })` → `res.json()` → render. `toLocaleString()`
  formats with commas; graceful `—` fallback on failure.
- **Deploy = `s3 sync` + a CloudFront invalidation.** Without invalidating,
  CloudFront keeps serving the **cached old** `counter.js` at the edge.

#### CloudWatch (observability)
- Metrics are **auto-collected** for Lambda/API Gateway/DynamoDB (invocations,
  errors, 4xx/5xx, latency, throttles) — nothing to set up.
- An **Alarm** watches a metric (namespace + metric + dimensions, e.g.
  `AWS/Lambda Errors` for `FunctionName=...`, `AWS/ApiGateway 5xx` for `ApiId=...`)
  and fires an **action** when a threshold is crossed. `treat-missing-data` =
  what to do with no data; **alarm-actions / ok-actions** = where to notify on
  fire / clear. `set-alarm-state` force-triggers an alarm for testing.

#### SNS (Simple Notification Service)
- **Pub/sub**: a **topic** is a broadcast channel; publishers send to it, it fans
  out to **subscribers** (HTTPS webhook, email, SMS, Lambda, SQS…). **Decouples**
  sender from receivers.
- A CloudWatch alarm's only notify action is "publish to an SNS topic," so the
  topic is the required middleman between the alarm and PagerDuty.

#### PagerDuty (incident alerting) + the integration
- Flow: `CloudWatch Alarm → SNS topic → HTTPS subscription → PagerDuty Integration
  URL → incident`. PagerDuty's **Amazon CloudWatch** integration auto-parses the
  SNS message and **auto-confirms** the HTTPS subscription. Keep SNS **raw message
  delivery OFF** (PagerDuty wants the full SNS envelope).
- A PagerDuty **Service** ties an **integration** (alert source) to an
  **escalation policy** (who gets paged). **ALARM** state triggers an incident;
  **OK** state auto-resolves it (verified both).
- **CloudWatch vs Sentry** — different jobs: CloudWatch = *infra health* (metrics,
  alarms, throttles); Sentry = *application errors* (grouped exceptions, stack
  traces, releases). Complementary; for a tiny counter, CloudWatch is enough.

#### Ops gotchas
- A Lambda that "doesn't work" but reaches the AWS call and gets **AccessDenied**
  = the **execution role** is missing a permission (the code is fine).
- Deployed JS not updating in the browser = **CloudFront cache** → invalidate.
- **SMS to Indian (+91) numbers** is blocked for most SaaS by India's **TRAI/DLT**
  A2P rules — use the **app + email** instead of SMS for PagerDuty.

### CLI commands used (quick reference)

```bash
# DynamoDB
aws dynamodb create-table --table-name cloud-resume-visitors \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH --billing-mode PAY_PER_REQUEST
aws dynamodb put-item --table-name cloud-resume-visitors \
  --item '{"id":{"S":"views"},"views":{"N":"0"}}'
aws dynamodb get-item --table-name cloud-resume-visitors --key '{"id":{"S":"views"}}'

# Lambda
zip -j lambda.zip lambda_function.py
aws lambda update-function-code --function-name cloud-resume-visitor-counter --zip-file fileb://lambda.zip
aws lambda invoke --function-name cloud-resume-visitor-counter out.json
aws iam put-role-policy --role-name <execution-role> --policy-name dynamodb-access \
  --policy-document file://aws/lambda-dynamodb-policy.json

# API Gateway (HTTP API) — what the console wizard does under the hood
aws apigatewayv2 create-api --name cloud-resume-api --protocol-type HTTP \
  --cors-configuration '{"AllowOrigins":["*"],"AllowMethods":["POST","OPTIONS"],"AllowHeaders":["content-type"]}'
aws apigatewayv2 create-integration --api-id ID --integration-type AWS_PROXY \
  --integration-uri <lambda-arn> --payload-format-version 2.0 --integration-method POST
aws apigatewayv2 create-route --api-id ID --route-key "POST /count" --target "integrations/INT_ID"
aws apigatewayv2 create-stage --api-id ID --stage-name '$default' --auto-deploy
aws lambda add-permission --function-name ... --principal apigateway.amazonaws.com \
  --action lambda:InvokeFunction --source-arn "arn:aws:execute-api:REGION:ACCT:ID/*/*/count"

# Monitoring: SNS + CloudWatch alarms + PagerDuty
aws sns create-topic --name cloud-resume-alarms
aws sns subscribe --topic-arn ARN --protocol https --notification-endpoint <pagerduty-url>
aws cloudwatch put-metric-alarm --alarm-name cloud-resume-lambda-errors \
  --namespace AWS/Lambda --metric-name Errors --dimensions Name=FunctionName,Value=... \
  --statistic Sum --period 300 --evaluation-periods 1 --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold --treat-missing-data notBreaching \
  --alarm-actions ARN --ok-actions ARN
aws cloudwatch set-alarm-state --alarm-name ... --state-value ALARM --state-reason "test"  # test-fire
```

---

## Session 3 — 2026-06-10

**What we built:** IAM Access Analyzer (free external-access type) + policy
validation, and PagerDuty → Slack so incidents land in chat with action buttons.

### Alerting architecture now

```
   Lambda error / API 5xx
        │
        ▼
   CloudWatch Alarm (ap-south-1)          alarms: cloud-resume-lambda-errors,
        │  ALARM / OK                             cloud-resume-api-5xx
        ▼
   SNS topic cloud-resume-alarms
        │  HTTPS subscription
        ▼
   PagerDuty service "Cloud Resume API"   ← routing brain: decides who/how
        ├──► mobile app push + email      (the page — wakes you up)
        └──► Slack #aws-alerts            (interactive card: ack/resolve buttons,
                                           threaded updates, auto-resolve)
```

### Concepts

#### IAM Access Analyzer
- Three finding types: **external access** (FREE — who *outside* the account can
  reach your resources), **internal access** ($9/resource/mo), **unused access**
  ($0.20/identity/mo). We created only the free one:
  `realsem-external-access-analyzer` (ap-south-1, analyzers are per-region).
- **Zone of trust** — the boundary considered "yours"; anything reachable from
  outside it becomes a finding. Ours is the org `o-7vaeoztr8s`, which contains
  only account 695331051459, so org ≡ account here.
- **Zero findings = good** — independently confirms the S3 bucket really is
  CloudFront-only (the Step-5 OAC lockdown). It keeps watching; a future policy
  mistake that exposes a bucket shows up as a finding (can wire to EventBridge).

#### Policy validation
- `aws accessanalyzer validate-policy --policy-document file://... --policy-type
  IDENTITY_POLICY|RESOURCE_POLICY` — a linter for IAM JSON (~100 checks:
  ERROR / SECURITY_WARNING / WARNING / SUGGESTION, with line/column).
- Killer catch: **typo'd actions** (`dynamodb:GetItme`) — IAM saves them happily,
  they just never match, and you debug AccessDenied forever. The validator flags
  INVALID_ACTION instantly. Same checks run live in the console policy editor.
- Both our saved policies (`aws/lambda-dynamodb-policy.json`,
  `aws/bucket-policy.json`) validate clean — least privilege held up.

#### PagerDuty → Slack
- PagerDuty **Extensions → Slack** → OAuth the workspace (`realsemedtech.slack.com`,
  Google SSO) → **channel connection**: service "Cloud Resume API" → `#aws-alerts`.
- **Responder vs Stakeholder** connection types: Responder = for fixers —
  interactive card (Acknowledge/Resolve buttons work from Slack, acks stop
  re-paging), full event firehose. Stakeholder = read-only status broadcasts
  (triggered/resolved only) for watch-only channels. One-person team → Responder.
- Free on PagerDuty Free plan + free Slack. Slack is the visibility layer;
  the PagerDuty app still does the actual 3am paging.
- Tested end-to-end with `set-alarm-state` → card in ~30s, threaded auto-resolve
  when the alarm re-evaluated to OK.

### Gotchas
- Debug-Chrome had a stale session cookie for a DIFFERENT (suspended!) AWS
  account — console said "account suspended" while the CLI worked fine. Logged
  out, signed in fresh as abhijit-admin. Lesson: console auth ≠ account state;
  check `aws sts get-caller-identity` before panicking.
- Console "Create analyser" radio click for zone-of-trust didn't register before
  submit → created with org scope. Harmless here (org = 1 account), and zone of
  trust can't be edited after creation — delete + recreate if it ever matters.

### Step 11.5 — Smoke tests (same session)

Two test layers, one tool (pytest), separated by a marker (`pytest.ini`:
`addopts = -m "not smoke"` → plain `pytest` = unit only; `pytest -m smoke` =
live checks):

```
  LAYER 1 — UNIT (default `pytest`, ~0.4s, offline, runs anywhere)

      pytest ──calls function directly──► lambda_handler()
                                               │ boto3
                                               ▼
                                        moto fake DynamoDB (in-process)

      proves LOGIC: increment math, response contract (200/CORS/JSON),
      first-ever-invocation upsert, Decimal→int serialization.
      Cannot prove the deployment works.


  LAYER 2 — SMOKE (`pytest -m smoke`, ~2s, needs network + AWS creds)

      pytest ──real HTTPS──► API Gateway z8v6craitg          (the internet path)
         │                        │  only route: POST /count
         │                        │  (GET → 404, /other → 404, OPTIONS → CORS)
         │                        ▼
         │                   Lambda cloud-resume-visitor-counter
         │                        │  real IAM role, real region
         │                        ▼
         └──boto3 get_item──► DynamoDB cloud-resume-visitors
            (verification        proves the write PERSISTED — API's answer
             side-channel)       cross-checked against the table itself

      proves the DEPLOYMENT: routing, CORS preflight, IAM permissions,
      end-to-end wiring, no side effects from rejected requests.


  WHERE THEY RUN (step 14 CI/CD, planned):
      git push ─► unit tests ─► deploy ─► smoke tests ─► done
                  (gate: bad logic        (gate: bad deploy
                   never deploys)          gets caught in ~2s)
```

Concepts:
- **Smoke test** = post-deploy sanity check against the real stack. Unit = "is
  the code right?"; smoke = "is the *deployment* right?" Different failure
  classes: IAM, routing, CORS config, region mix-ups live only in layer 2.
- **pytest markers** — labels on tests; `-m` selects by label. File-wide via
  `pytestmark = pytest.mark.smoke`.
- **Verify side effects through a second path** — don't trust the API's return
  value; read the table directly with boto3 and compare.
- **No-side-effect asserts** — rejected requests (wrong method/path) must not
  move the counter: read-before / bad call / read-after sandwich.
- **Live-test trade-offs**: the increment test is strict (`n2 == n1+1`) and can
  flake if a real visitor lands mid-test — chosen over a weak `>=`. Each smoke
  run adds ~3 real views — accepted for a vanity counter.
- **First-invocation edge case** stays in the unit layer (recreating it live
  would mean deleting the prod item). A disposable staging stack (step 12 IaC)
  is where destructive smoke tests belong.

### Step 11 — Unit tests (same session)

- **pytest** — Python's standard test runner: files `test_*.py`, plain `assert`,
  **fixtures** (reusable setup injected by parameter name), **markers** (labels).
- **moto** — fakes AWS in-process; boto3 calls never leave the machine. Tests
  run with no creds, no cost, no network.
- **Import-order gotcha** — our Lambda creates `boto3.resource()` at module
  import time, so the mock must start *before* import; fixture does
  `importlib.reload`. (Testability cost of module-level clients.)
- **Decimal trap** — DynamoDB numbers come back as `decimal.Decimal`;
  `json.dumps(Decimal)` raises TypeError → handler needs `int(...)`. Assert the
  *type*, not just equality (Decimal(8) == 8 is True!).
- 5 tests: contract (200/CORS/JSON) · increment 41→42 · persistence 1→2→3 ·
  missing-item upsert → 1 · Decimal→int.

### API throttling (same session)

- HTTP API **stage-level throttling**: `rate` (steady req/s) + `burst` (spike
  allowance), token-bucket. Excess → **429** at the gateway, Lambda never
  invoked → $0. Ours: 5 rps / burst 10.
- Guards against **denial-of-wallet** (bot loop burning paid invocations), not
  per-IP abuse (that's WAF, ~$5/mo, skipped).
- Trade-off accepted: a capped flood makes the counter 429 for real visitors,
  but the résumé itself (CloudFront/S3) is unaffected.

### Step 13 — Git/GitHub (same session)

- Public **monorepo** (website/ + backend/ + infra/ + docs) over two repos:
  CI path-filters give separate pipelines anyway; one history.
- **Secrets vs identifiers**: keys/tokens NEVER in git (history is forever) →
  GitHub Secrets or OIDC (step 14). Account IDs, API IDs, bucket names are
  *identifiers* — fine in public (our API URL is already in counter.js).
- Commit email = GitHub **noreply** address; `gh auth setup-git` wires git
  pushes through the gh CLI's token.

### Step 12 — Terraform (IaC)

- **Declarative**: .tf files say what should EXIST; `terraform` makes reality
  match. Repo = source of truth; AWS = a rendering of it.
- **Workflow**: `init` (download providers, connect backend) → `plan` (3-way
  diff: config vs state vs refreshed reality — read it EVERY time) → `apply`.
  Re-running is always safe (convergence) — the crash-recovery story too.
- **State** (`terraform.tfstate`): maps config names → real AWS IDs. Ours is
  remote: `s3://abhijitraj-crc-tfstate` (versioned, private, lockfile). State
  bucket ≠ website bucket on purpose: CDN exposure, CI `sync --delete` would
  eat it, and TF must not manage the bucket holding its own state.
- **Drift**: manual change to a managed attr → next plan reverts it (config
  wins). Manual delete → plan recreates. Manual NEW resource → invisible.
- **Adoption via `import` blocks**: describe resource + point at real ID →
  plan shows "N to import" → iterate until ALSO "0 to change" → apply. All 15
  backend resources adopted with zero recreation (smoke tests confirmed).
  (Bulk alternative: `terraform plan -generate-config-out`.)
- **References** (`aws_dynamodb_table.visitors.arn`) replace pasted ARNs —
  Terraform derives the dependency graph and order.
- **Variables/outputs**: `var.pagerduty_endpoint` (sensitive) keeps the PD key
  out of the public repo via gitignored `terraform.tfvars`; `output
  api_endpoint` exposes the URL to humans/CI.
- **HCL** = HashiCorp Configuration Language. Registry docs are the reference
  (nobody memorizes arguments); `fmt`/`validate` keep it honest. Licensing:
  BUSL since 2023 (OpenTofu = OSS fork). CLI free; resources billed as normal.

#### Commit signing (SSH)

- Git authorship is **self-asserted** (`user.email` is just config) — anyone can
  impersonate anyone in commit metadata. Signing makes authorship *provable*.
- History is tamper-evident (hash chain) but not author-authenticated — signing
  adds the second property. GitHub shows verified signatures as **"Verified"**.
- **SSH signing** (git ≥2.34) over GPG: two config lines (`gpg.format ssh`,
  `user.signingkey`), no GPG toolchain; GPG only needed when signing beyond git
  (email, packages). `commit.gpgsign true` = sign by default.
- Adoption: optional in most teams, required in supply-chain-serious orgs
  (post-SolarWinds/xz; SLSA); branch protection can enforce it.
- Key: `~/.ssh/github_signing` (ed25519, no passphrase — relies on disk
  encryption; backup in 1Password), public half registered on GitHub as a
  *signing key*.
- **Enforcement**: a repository **ruleset** (`required_signatures` on the
  default branch) makes GitHub reject any unsigned push — verified by pushing
  an unsigned commit ("push declined due to repository rule violations").
  Rulesets are the modern successor to classic branch protection; "status
  checks" are a different rule type (CI results — coming in step 14).

### How code flows through the system (end of session 3)

```
 MacBook (dev)
 ────────────
   edit code: website/ · backend/ · infra/
        │
        ▼
   pytest  (unit: moto fake AWS, offline, 0.4s)        ← fast inner loop
        │
        ▼
   git commit  ──► auto-SIGNED (ssh key ~/.ssh/github_signing)
        │
        ▼
   git push ──────────────────► GitHub (public monorepo)
                                   │
                                   ▼
                          ruleset: required_signatures
                          unsigned? ──► REJECTED at the door
                                   │ signed ✓
                                   ▼
                              main branch
                                   ┊
                                   ┊  (step 14-15 will automate this leg:
                                   ┊   Actions → pytest gate → deploy → smoke)
        ┌──────────────────────────┴───── for now, deploys run from the laptop:
        │
        ├── backend/infra changes ──► terraform plan  (read the diff!)
        │                             terraform apply
        │                                │  state: s3://abhijitraj-crc-tfstate
        │                                ▼
        │                  Lambda · API GW · DynamoDB · IAM · alarms (ap-south-1)
        │
        └── website/ changes ──► aws s3 sync + CloudFront invalidation
                                         │
                                         ▼
                              S3 (private) ◄─OAC─ CloudFront ◄─ visitors
                                                      https://abhijitraj.me
        after either deploy:
   pytest -m smoke  ──► live checks (API increments, DB persisted, CORS, 404s)
```

Reading the diagram: signing + the ruleset guard WHAT enters main; tests guard
WHETHER it works (unit before commit, smoke after deploy); Terraform guards
HOW infra changes (plan before apply). Step 14-15 moves the dashed leg into
GitHub Actions so push = test + deploy + verify, with OIDC instead of keys.
