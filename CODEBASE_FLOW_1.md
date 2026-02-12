# Research Data Platform V2 - Complete Codebase Flow (Part 1)

## Overview

This document provides a complete walkthrough of the codebase from entry point to exit, showing how data flows through the system and where critical data strategies are implemented.

---

## Table of Contents

1. [System Entry Points](#system-entry-points)
2. [Data Flow Through Components](#data-flow-through-components)

---

## 1. System Entry Points

### Entry Point 1: S3 Upload (Data Ingestion)

**Trigger:** File uploaded to S3
**Location:** `s3://itus-data-lake/raw/{data_type}/`
**Next Step:** Lambda Validator

```
File Upload → S3 Event Notification → Lambda Function
```

### Entry Point 2: API Request (Data Query)

**Trigger:** HTTP request to API
**Location:** `api/main.py`
**Endpoint:** `POST /api/v1/query/execute`

```
HTTP Request → FastAPI → Temporal Validator → Redshift → Response
```

### Entry Point 3: Scheduled Job (ETL)

**Trigger:** EventBridge schedule or Glue trigger
**Location:** `glue/daily_prices_etl.py`
**Schedule:** Daily 2:00 AM IST

```
EventBridge → Glue Job → Read S3 → Transform → Load Redshift
```

---

## 2. Data Flow Through Components

### Flow 1: Daily Price Data (End-to-End)

```
┌─────────────────────────────────────────────────────────────┐
│ STEP 1: Data Collection (Your Team)                        │
│ File: data-collection/collect_daily_prices.py              │
│ Action: Collect from NSE API → Upload to S3                │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ STEP 2: S3 Landing                                          │
│ Location: s3://itus-data-lake/raw/prices/2024/01/01/       │
│ File: nse_prices_20240101.csv                              │
│ Trigger: S3 Event Notification                             │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ STEP 3: Lambda Validation                                   │
│ File: lambda/validators/price_validator.py                 │
│ Critical Strategy: Data Quality Validation                  │
│ Actions:                                                     │
│   - Schema validation                                        │
│   - Null checks                                              │
│   - Price range validation (>0)                              │
│   - Outlier detection (±50%)                                 │
│   - Duplicate detection                                      │
│ Output: Valid → Trigger Glue | Invalid → Quarantine        │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ STEP 4: Glue ETL Job                                        │
│ File: glue/daily_prices_etl.py                             │
│ Critical Strategies:                                         │
│   - Job Bookmarks (Incremental Processing)                  │
│   - Idempotent Design                                        │
│ Actions:                                                     │
│   - Read from S3 (only new files via bookmarks)            │
│   - Transform data                                           │
│   - Load to staging.stg_prices                              │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ STEP 5: Redshift Staging Zone (Bronze)                     │
│ Location: staging.stg_prices                                │
│ Critical Strategy: Truncate and Load (Idempotent)          │
│ SQL: redshift/schemas/staging_to_integration.sql           │
│ Actions:                                                     │
│   - Temporary landing area                                   │
│   - Minimal transformation                                   │
│   - 7-day retention                                          │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ STEP 6: Integration Zone (Silver)                          │
│ Location: integration.prices                                │
│ Critical Strategies:                                         │
│   - Corporate Action Adjustments                             │
│   - Data Vault Pattern (vault_prices)                       │
│ SQL: redshift/schemas/integration_transformations.sql      │
│ Actions:                                                     │
│   - Apply corporate action adjustments                       │
│   - Calculate cumulative factors                             │
│   - Store in vault (append-only)                             │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ STEP 7: Presentation Zone (Gold)                           │
│ Location: fact_daily_prices                                │
│ Critical Strategies:                                         │
│   - Star Schema Design                                       │
│   - Optimized for Analytics                                  │
│ SQL: redshift/schemas/08_create_fact_tables.sql            │
│ Actions:                                                     │
│   - Join with dimensions                                     │
│   - Apply final transformations                              │
│   - Optimize with DISTKEY/SORTKEY                           │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ STEP 8: Materialized Views                                 │
│ Location: mv_rolling_returns                               │
│ Critical Strategy: Precomputation for Performance          │
│ SQL: redshift/schemas/07_create_materialized_views.sql     │
│ Actions:                                                     │
│   - Calculate rolling returns                                │
│   - Compute momentum indicators                              │
│   - Refresh daily at 7 AM                                    │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ STEP 9: Query via API                                      │
│ File: api/main.py                                           │
│ Critical Strategies:                                         │
│   - Temporal Validation (prevent look-ahead bias)           │
│   - Performance Estimation                                   │
│   - Result Caching                                           │
│ Actions:                                                     │
│   - Validate query for temporal correctness                  │
│   - Estimate cost                                            │
│   - Check cache                                              │
│   - Execute on Redshift                                      │
│   - Return results                                           │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ STEP 10: Analyst Consumption                               │
│ Tools: Python, Excel, Tableau, PowerBI                     │
│ Actions:                                                     │
│   - Run analysis                                             │
│   - Create visualizations                                    │
│   - Generate reports                                         │
└─────────────────────────────────────────────────────────────┘
```

---

**Continue to [Part 2](CODEBASE_FLOW_2.md) for Critical Data Strategies**
