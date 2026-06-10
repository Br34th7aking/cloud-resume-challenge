# Cloud Resume Challenge — Progress

Living tracker for working through the Cloud Resume Challenge (and its follow-on
challenges) collaboratively. Updated as we go.

**Working method:** for each infrastructure step — (1) understand what & why,
(2) build it **console-first** (watch the clicks), (3) tear it down,
(4) rebuild via **AWS CLI** (learn the commands). Code steps (Python, tests,
IaC, CI/CD) are written directly.

**Legend:** `[x]` done · `[~]` in progress · `[ ]` to do

---

## Reference

| | |
|---|---|
| AWS account | `695331051459` (Realsem Edtech) |
| IAM user | `abhijit-admin` (MFA via 1Password) |
| Region | `ap-south-1` (Mumbai) |
| Project folder | `~/cloud-resume-challenge/` |
| **Live site** | **https://abhijitraj.me** (+ www) via CloudFront |
| Bucket | `abhijitraj-resume-crc` (private, CloudFront OAC) |
| CloudFront | dist `E2N3X21KFIF3UP` → `d2g5lzoyakz4an.cloudfront.net` |
| Domain | `abhijitraj.me` (Cloudflare registrar + DNS) |
| ACM cert | `e7a16a9a-…` (us-east-1) |

---

## Phase 0 — Foundations

- [x] AWS account access (console sign-in, IAM user, MFA)
- [x] AWS CLI v2 installed (no-sudo, `~/aws-cli` → `~/bin/aws`) + configured (`~/.aws`, ap-south-1)
- [x] Project folder created (`~/cloud-resume-challenge/`)
- [x] Billing budget alert ($6/mo ≈ ₹500; alerts 85/100% actual + 100% forecast → abhijit@realsem.app)
- [x] **Monitoring/alerting**: CloudWatch alarms (`cloud-resume-lambda-errors`, `cloud-resume-api-5xx`) → SNS `cloud-resume-alarms` → **PagerDuty** (service "Cloud Resume API"). Tested: ALARM→incident, OK→auto-resolve. (Install PagerDuty mobile app to receive pages; SMS to +91 blocked by India DLT rules — app+email instead.)
- [x] **PagerDuty → Slack** (2026-06-10): PagerDuty Slack extension connected to workspace `realsemedtech.slack.com`; connection "Cloud Resume API" → `#aws-alerts` (Responder, all events, any urgency). Tested end-to-end via `aws cloudwatch set-alarm-state` → incident card in Slack + threaded auto-resolve. Free on PagerDuty Free plan + free Slack.
- [x] **IAM Access Analyzer** (2026-06-10): free external-access analyzer `realsem-external-access-analyzer` (ap-south-1, org zone of trust ≡ account — org has only this account). Policy validation: `aws accessanalyzer validate-policy` → both saved policies clean. Paid analyzers (internal/unused) deliberately skipped.
- [ ] Git repo + push to personal GitHub
- [ ] **AWS Cloud Practitioner certification** *(your own study + exam)*

---

## Phase 1 — The Cloud Resume Challenge (core)

### 1. Certification
- [ ] Earn AWS Cloud Practitioner (or higher) — self-study

### 2–3. HTML & CSS résumé
- [x] Build `index.html` (semantic) from PDF
- [x] Build `css/style.css` (responsive + print)
- [x] Code review pass

### 4. Static website — S3 ✅
- [x] **Console pass:** create bucket → disable Block Public Access → upload files → enable static website hosting → public-read bucket policy → verified live (403 → 200)
- [x] **CLI redo:** teardown (`s3 rm --recursive` + `s3 rb`) → rebuild (`s3 mb` / `s3api put-public-access-block` / `s3 website` / `s3api put-bucket-policy --policy file://aws/bucket-policy.json` / `s3 sync`) → verified 200
- Policy saved at `aws/bucket-policy.json` (reuse for IaC)

### 5. HTTPS — CloudFront ✅
- [x] Created distribution (console) `E2N3X21KFIF3UP` → `https://d2g5lzoyakz4an.cloudfront.net`
- [x] OAC (Origin Access Control) → S3 bucket made PRIVATE again (Block Public Access ON, CloudFront-only policy at `aws/bucket-policy.json`)
- [x] Default root object `index.html`; HTTP→HTTPS redirect; Amazon TLS cert; WAF off (no cost); Pay-as-you-go ($0)
- (skipped raw-CLI redo by design — CloudFront is automated properly at Step 12 IaC)

### 6. DNS — custom domain ✅
- [x] Bought `abhijitraj.me` via Cloudflare Registrar (apex domain for résumé; future Next/React site too)
- [x] ACM cert (us-east-1) for `abhijitraj.me` + `www`, DNS-validated via Cloudflare CNAMEs
- [x] Attached cert + alternate domain names to CloudFront; TLS policy TLSv1.2_2021
- [x] Cloudflare DNS: apex + www → `d2g5lzoyakz4an.cloudfront.net` (DNS only / grey cloud; apex via CNAME flattening)
- [x] **LIVE: https://abhijitraj.me + https://www.abhijitraj.me (HTTP→HTTPS redirect working)**

### 7. JavaScript — visitor counter (front end) ✅
- [x] `js/counter.js` POSTs to the API on load, renders `{views}` into `#visit-count` (fallback `—`)
- [x] Deployed via `s3 sync` + CloudFront invalidation
- [x] **LIVE on https://abhijitraj.me — full stack verified end-to-end** (browser → API GW → Lambda → DynamoDB)

### 8. Database — DynamoDB ✅
- [x] Created table `cloud-resume-visitors` (ap-south-1, partition key `id`, On-demand/PAY_PER_REQUEST)
- [x] Seeded item `{ id: "views", views: 0 }` (via CLI put-item)
- ARN: `arn:aws:dynamodb:ap-south-1:695331051459:table/cloud-resume-visitors`

### 10. Python — Lambda code ✅
- [x] `backend/lambda_function.py` — boto3 `update_item` with atomic `ADD` increment, returns `{views}` with CORS headers
- [x] Deployed to Lambda `cloud-resume-visitor-counter` (Python 3.14, ap-south-1)
- [x] Least-privilege IAM: inline policy `dynamodb-visitor-counter-access` (UpdateItem/GetItem on the table) at `aws/lambda-dynamodb-policy.json`
- [x] Tested via `aws lambda invoke` → returns `{"views": 1}`, DynamoDB count incremented

### 9. API — API Gateway (HTTP API) ✅
- [x] HTTP API `cloud-resume-api` (id `z8v6craitg`, ap-south-1), Lambda proxy integration
- [x] Route **`POST /count`** (POST, not GET — increment mutates state; avoids cache/prefetch issues)
- [x] CORS: Allow-Origin `*`, Allow-Headers `content-type`, Allow-Methods `POST`/`OPTIONS`
- [x] Endpoint: `https://z8v6craitg.execute-api.ap-south-1.amazonaws.com/count` — tested `{"views": 2}`

### 11. Tests ✅
- [x] `backend/tests/test_lambda_function.py` — 5 pytest tests with **moto** (fake DynamoDB in-process; no creds/cost): response contract (200 + CORS + JSON), increment correctness (41→42), persistence across calls (1→2→3), missing-item upsert (first-ever visit → 1), Decimal→int serialization guard
- [x] Venv at `.venv/` (Python 3.14, matches Lambda runtime); deps in `backend/requirements-dev.txt`
- Run: `cd backend && ../.venv/bin/python -m pytest tests/ -v` (becomes the CI gate in step 14)
- Gotcha learned: module-level `boto3.resource()` must be imported *after* `mock_aws()` starts → fixture does `importlib.reload`
- [x] **Smoke tests** (`backend/tests/smoke/test_deployed_stack.py`, `pytest -m smoke`) — 5 tests vs the LIVE stack: increment + persisted-to-DynamoDB cross-check, GET→404 (no side effect), unknown path→404 (no side effect), CORS preflight, garbage body→200 not 500. Marker-separated via `pytest.ini` (plain `pytest` = unit only). `SMOKE_API_URL` env var re-aims at staging later. Caveat: each run adds ~3 real views; increment assert can flake if a real visitor lands mid-test.

### 12. Infrastructure as Code
- [ ] Define the back end (DynamoDB + Lambda + API GW) as code (AWS SAM or Terraform)
- [ ] `deploy` from the template instead of console

### 13. Source control — GitHub (back end)
- [ ] Back-end repo, committed

### 14. CI/CD — back end
- [ ] GitHub Actions: run tests + deploy SAM/Terraform on push

### 15. CI/CD — front end
- [ ] GitHub Actions: on push, `s3 sync` + CloudFront cache invalidation

### 16. Blog post
- [ ] Write up what was built and learned

---

## Phase 2 — Event-Driven Python on AWS *(follow-on challenge)*

Builds on the serverless/Python skills from Phase 1 — a real event-driven data
pipeline. Detail these when we reach them.

- [ ] Ingest/trigger source (e.g. scheduled EventBridge or S3 event)
- [ ] Decoupling with SQS / SNS
- [ ] Lambda processing + DynamoDB
- [ ] Orchestration (Step Functions) where it fits
- [ ] Tests, IaC, CI/CD for the pipeline

---

## Phase 3 — Improving Application Performance on AWS *(follow-on challenge)*

Optimize what we've built — latency, caching, cost. Detail later.

- [ ] Caching strategy (CloudFront tuning, cache headers)
- [ ] DynamoDB performance (indexes / DAX where warranted)
- [ ] Lambda cold-start / sizing improvements
- [ ] Load testing + before/after measurement

---

## Phase 4 — Machine Learning on AWS *(follow-on challenge)*

New domain — build & deploy an ML feature. Detail later.

- [ ] Problem + dataset
- [ ] Train (SageMaker or managed AI service)
- [ ] Deploy an inference endpoint
- [ ] Integrate into the app
- [ ] Tests, IaC, CI/CD

---

*Last updated: 2026-06-10 — Steps 1–11 DONE. Session 3 added: IAM Access Analyzer (free external) + policy validation, PagerDuty→Slack (#aws-alerts, e2e tested), pytest suite for the Lambda (5 tests, moto). **NEXT: Step 12 — IaC (SAM or Terraform).** Then 13 GitHub, 14–15 CI/CD, 16 blog. See LEARNING.md for concepts (sessions 1–3).*
