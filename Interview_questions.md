# Research Data Platform V2: Interview Questions, Follow-Ups, and Sample Answers

This guide is tailored to the architecture and implementation in this repository.

## 1) System Design and Architecture

### Q1. Walk me through the end-to-end architecture of this platform.
**Follow-up:** Where are the biggest reliability risks in this pipeline, and how would you mitigate them?

**Sample Answer:**
The platform is organized into four layers: (1) ingestion on AWS (S3 + Lambda validators + Glue ETL), (2) Redshift warehouse with staging/integration/presentation zones, (3) API query layer (FastAPI + Redis + validation/estimation), and (4) analyst consumption tools. Reliability risks are typically around bad upstream data, ETL job failures, and warehouse hotspots. Mitigations include validator gates, quarantine + alerting, idempotent ETL with high-water marks, and workload management separation in Redshift.

---

### Q2. Why is a multi-zone warehouse model (staging, integration, presentation) useful here?
**Follow-up:** What data governance rule would you enforce in each zone?

**Sample Answer:**
The zone pattern separates concerns. Staging is raw and short-lived, integration applies temporal/business logic, and presentation is optimized for analytics and self-service consumption. Governance rules: staging allows minimal transformation and short retention, integration enforces lineage/temporal correctness, and presentation enforces curated definitions with performance SLAs.

---

### Q3. What AWS services were selected and why?
**Follow-up:** If cost pressure increases by 30%, what would you optimize first?

**Sample Answer:**
S3 is used for low-cost durable lake storage, Lambda for event-driven data quality checks, Glue for scalable ETL, Redshift for analytical warehousing, and CloudWatch/SNS for monitoring and alerting. Under cost pressure, I would optimize Redshift compute first (scheduling pause/resume, workload tuning, better sort/dist strategy, materialized views), then tighten lifecycle and archival policies in S3.

## 2) Data Modeling and Temporal Correctness

### Q4. Explain bi-temporal modeling in this platform.
**Follow-up:** How does it prevent look-ahead bias in backtests?

**Sample Answer:**
Bi-temporal modeling stores both valid time (when something was true) and transaction/publication time (when we knew it). Queries constrained by as-of/publication logic reproduce what an analyst could have known at that historical point, preventing leakage of future restatements into historical models.

---

### Q5. How does this platform handle survivorship bias?
**Follow-up:** What tables/fields matter most to support delisted securities analysis?

**Sample Answer:**
It retains full security lifecycle information, including listing and delisting state, and models index membership with effective/exit dates. That allows analysts to query historical universes accurately rather than only currently listed securities.

---

### Q6. Why use Type 2 SCD for `dim_security`?
**Follow-up:** Give an example of business logic that depends on this.

**Sample Answer:**
Type 2 SCD preserves attribute history over time (sector changes, corporate identity changes). This is critical for historical factor research—for example, sector-neutral backtests should use the sector classification valid at that date, not today’s value.

## 3) ETL, Data Quality, and Operations

### Q7. Describe the validation strategy from ingestion to warehouse.
**Follow-up:** How would you reduce false positives in data quality checks?

**Sample Answer:**
Validation is layered: Lambda checks schema/range/required fields near ingestion; Glue jobs apply pipeline-level checks and reject or quarantine problematic records; warehouse controls/logging track quality outcomes over time. To reduce false positives, I’d calibrate thresholds by source/instrument class and use dynamic baselines plus exception workflows.

---

### Q8. What makes an ETL pipeline idempotent in this codebase?
**Follow-up:** How do high-water marks support correctness?

**Sample Answer:**
Idempotency means rerunning a batch does not duplicate or corrupt target state. This is achieved by deterministic keys, controlled merge/load patterns, and state tracking. High-water marks record the last fully processed boundary, so reruns can resume safely and incrementally.

---

### Q9. How are failed records handled operationally?
**Follow-up:** What is your on-call runbook for repeated validator failures?

**Sample Answer:**
Failed records are routed to quarantine/DLQ pathways and alerting is triggered via SNS/monitoring. On-call would verify source changes, inspect error patterns, compare against recent schema drift, decide rollback vs hotfix, and replay from a safe checkpoint once corrected.

## 4) Redshift Performance and Scalability

### Q10. What query performance features are implemented?
**Follow-up:** When would you choose a materialized view vs computing on the fly?

**Sample Answer:**
The platform uses curated fact/dim design, appropriate dist/sort keys, WLM queue separation, and materialized views for expensive repeated calculations. I’d choose materialized views when workloads are repetitive and freshness requirements tolerate scheduled refresh latency.

---

### Q11. Explain Redshift WLM strategy here.
**Follow-up:** What metric would tell you the queue split is wrong?

**Sample Answer:**
Workload groups are separated for ETL, analysts, and admin to avoid resource contention. If queue wait time, query spill, or SLA misses rise consistently in one class while others are underutilized, the allocation needs retuning.

---

### Q12. How would you diagnose a sudden 5x increase in query latency?
**Follow-up:** What are likely causes specific to this architecture?

**Sample Answer:**
I’d inspect recent deployment/config changes, table growth/skew, stale statistics, WLM queue pressure, materialized view freshness, and query plan regressions. In this architecture, likely causes include missing date filters on large facts, stale MVs, or spikes from concurrent ETL and analyst workloads.

## 5) API, Guardrails, and Research Safety

### Q13. Why include a temporal validator in the API layer?
**Follow-up:** Can validators be bypassed for expert users?

**Sample Answer:**
Temporal validation in the API provides a safety net before warehouse execution, preventing invalid historical logic at query time. Bypass may exist for privileged users in emergencies, but should be auditable and default-deny to protect research integrity.

---

### Q14. What does the query performance estimator protect against?
**Follow-up:** How would you tune reject thresholds over time?

**Sample Answer:**
It estimates rows/cost and flags potentially expensive or unsafe queries (e.g., full scans of very large tables) before execution. I’d tune thresholds using observed execution telemetry: tighten limits for noisy patterns and loosen for high-value workloads with acceptable cost.

---

### Q15. How would you design API authN/authZ for this platform?
**Follow-up:** What’s the minimum audit data you would log per query?

**Sample Answer:**
Use JWT/OIDC with role-based access (analyst, admin, service accounts), scoped permissions by schema/object, and environment isolation. Per query I’d log requester identity, timestamp, query hash/text (redacted policy-aware), as-of date, validation outcome, row count, duration, and query ID for traceability.

## 6) Financial Data Domain Questions

### Q16. How are corporate actions reflected in price analytics?
**Follow-up:** Why keep both adjusted and unadjusted series?

**Sample Answer:**
Corporate actions are modeled and adjustment factors are applied to build comparable historical series. Keeping adjusted and unadjusted series supports both return analytics (adjusted) and raw tape reconciliation/compliance scenarios (unadjusted).

---

### Q17. What challenges do financial restatements create?
**Follow-up:** How does the vault approach address those challenges?

**Sample Answer:**
Restatements can retroactively alter previously published values, which can silently contaminate model training if not tracked. Vault-style append-only temporal storage preserves all versions with publication context so analysts can reconstruct both “known-then” and “latest-known” views.

## 7) DevOps, Reliability, and Governance

### Q18. What monitoring and alerting signals are most important here?
**Follow-up:** Which would be paging alerts vs dashboard-only?

**Sample Answer:**
Critical signals: ingestion lag, validator failure rates, ETL success/failure, Redshift queue wait, API latency/error rate, and materialized view staleness. Paging should be reserved for data freshness breaches, pipeline failures, and severe API/warehouse outages; trend/optimization metrics can remain dashboard-level.

---

### Q19. How would you test this platform before a production release?
**Follow-up:** Name one contract test and one backfill test.

**Sample Answer:**
I’d run layered tests: validator unit tests, ETL integration tests, schema migration checks, temporal query correctness tests, and load/perf checks. A contract test could validate source CSV schema compatibility; a backfill test could replay a historical date range and verify deterministic row counts and key aggregates.

---

### Q20. If you inherited this platform tomorrow, what would you improve first?
**Follow-up:** Give a 30/60/90-day plan.

**Sample Answer:**
First priorities: harden auth, formalize SLAs/SLOs, and automate data quality regression checks. In 30 days: baseline observability and incident playbooks. In 60 days: tighten performance guardrails and governance controls. In 90 days: expand self-service semantic layer and optimize costs with usage-driven tuning.

## Bonus Behavioral + Scenario Questions

### Q21. Tell me about a time you had to balance data quality with delivery deadlines.
**Follow-up:** What trade-off did you make, and what safeguards did you keep?

**Sample Answer (framework):**
I prioritize irreversible risks first (incorrect data into production), ship a narrower validated slice, and communicate scope trade-offs transparently. Typical safeguards: quarantine unknown patterns, feature flags for partial release, and monitored rollback paths.

---

### Q22. Scenario: an analyst reports different results for the same backtest query run one week apart. How do you debug?
**Follow-up:** What evidence proves whether this is expected vs a bug?

**Sample Answer:**
I’d compare query text, as-of date, data version/publication windows, materialized view refresh timestamps, and underlying restatement activity. If as-of logic changed or was omitted, drift may be expected; if identical constraints produce divergent outputs without data/version explanation, that indicates a defect.

---

### Q23. Scenario: Glue job succeeds but downstream table is empty. What do you check first?
**Follow-up:** How would you prevent recurrence?

**Sample Answer:**
Check source partition discovery, bookmark/high-water state, filter predicates, and write-mode behavior. Prevent recurrence with row-count assertions, anomaly alerts for near-zero loads, and post-load data quality gates before marking pipeline success.

## How to Use This Interview Pack

- Use **Q + follow-up** to evaluate depth, not memorization.
- Ask candidates to map answers to **specific components** (validators, ETL jobs, schema layers, API guardrails).
- For senior roles, insist on **trade-off reasoning** (correctness vs cost vs latency).
