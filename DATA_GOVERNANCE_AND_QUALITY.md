# Data Governance and Quality Framework

## Overview

This document describes the comprehensive data governance and quality assurance framework implemented in the Research Data Platform V2. The framework ensures data accuracy, consistency, and temporal correctness throughout the entire data lifecycle.

---

## Table of Contents

1. [Governance Architecture](#governance-architecture)
2. [Data Quality Framework](#data-quality-framework)
3. [Validation Rules](#validation-rules)
4. [Temporal Governance](#temporal-governance)
5. [Monitoring and Alerting](#monitoring-and-alerting)
6. [Audit and Compliance](#audit-and-compliance)

---

## 1. Governance Architecture

### Multi-Layer Governance Model

```
┌─────────────────────────────────────────────────────────────┐
│ Layer 1: Ingestion Validation (Lambda)                     │
│ - Schema validation                                         │
│ - Data type checks                                          │
│ - Business rule validation                                  │
│ - Statistical outlier detection                             │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ Layer 2: ETL Quality Checks (Glue)                         │
│ - Referential integrity                                     │
│ - Duplicate detection                                       │
│ - Completeness checks                                       │
│ - Cross-table consistency                                   │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ Layer 3: Database Constraints (Redshift)                   │
│ - Primary keys                                              │
│ - Foreign keys                                              │
│ - Check constraints                                         │
│ - NOT NULL constraints                                      │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ Layer 4: Query-Time Validation (API)                       │
│ - Temporal correctness                                      │
│ - Look-ahead bias prevention                                │
│ - Performance estimation                                    │
│ - Access control                                            │
└─────────────────────────────────────────────────────────────┘
```

### Governance Principles

1. **Defense in Depth**: Multiple validation layers catch different types of issues
2. **Fail Fast**: Invalid data is rejected at the earliest possible stage
3. **Quarantine, Don't Delete**: Failed data is preserved for investigation
4. **Audit Everything**: All validation results are logged for compliance
5. **Alert Proactively**: Critical failures trigger immediate notifications

---

## 2. Data Quality Framework

### Data Quality Engine Architecture

**Location:** `lambda/validators/data_quality_engine.py`

The Data Quality Engine orchestrates validation across all data types:

```python
class DataQualityEngine:
    """
    Features:
    - Execute multiple validation rules
    - Quarantine failed data
    - Send SNS alerts for critical failures
    - Log results to control tables
    """
```

### Quality Dimensions

The framework validates six key quality dimensions:

| Dimension | Description | Implementation |
|-----------|-------------|----------------|
| **Completeness** | All required data is present | RequiredColumnsRule, NullCheckRule, RecordCountRule |
| **Accuracy** | Data values are correct | PositiveValueRule, RangeCheckRule, BalanceSheetBalanceRule |
| **Consistency** | Data is consistent across sources | DuplicateCheckRule, ReferentialIntegrityRule |
| **Timeliness** | Data is available when needed | DateGapRule, ETL job monitoring |
| **Validity** | Data conforms to business rules | ColumnTypeRule, StringLengthRule, PriceChangeRule |
| **Integrity** | Relationships are maintained | ReferentialIntegrityRule, Foreign key constraints |

---

## 3. Validation Rules

### Schema Validation Rules

#### RequiredColumnsRule
**Purpose:** Ensure all required columns are present in the dataset

**Example:**
```python
rule = RequiredColumnsRule(['security_id', 'price_date', 'close'])
result = rule.validate(df)
# FAIL if any column is missing
```

**When Applied:** First validation step for all data types

---

#### ColumnTypeRule
**Purpose:** Validate that columns have expected data types

**Example:**
```python
rule = ColumnTypeRule({
    'security_id': 'object',
    'price_date': 'datetime',
    'close': 'float'
})
```

**When Applied:** After schema validation

---

#### NullCheckRule
**Purpose:** Ensure critical fields have no null values

**Example:**
```python
rule = NullCheckRule(
    non_null_columns=['security_id', 'price_date', 'close'],
    threshold=0.0  # 0% nulls allowed
)
```

**When Applied:** All data types, especially primary keys

---

### Business Rules

#### PositiveValueRule
**Purpose:** Validate that numeric values are positive

**Example:**
```python
rule = PositiveValueRule(
    columns=['close', 'volume', 'market_cap'],
    allow_zero=False
)
```

**When Applied:** Price data, financial metrics

---

#### PriceChangeRule
**Purpose:** Detect abnormal price movements that may indicate data errors

**Example:**
```python
rule = PriceChangeRule(
    price_column='close',
    max_change_pct=50.0,  # Flag >50% changes
    security_id_column='security_id',
    date_column='price_date'
)
```

**How It Works:**
1. Calculate day-over-day price changes per security
2. Flag changes exceeding threshold
3. Check context for corporate actions (splits, dividends)
4. Report unexplained outliers

**When Applied:** Daily price data validation

---

#### BalanceSheetBalanceRule
**Purpose:** Ensure accounting equation holds (Assets = Liabilities + Equity)

**Example:**
```python
rule = BalanceSheetBalanceRule(
    assets_col='total_assets',
    liabilities_col='total_liabilities',
    equity_col='total_equity',
    tolerance_pct=1.0  # Allow 1% rounding difference
)
```

**When Applied:** Quarterly financial data

---

### Referential Integrity Rules

#### ReferentialIntegrityRule
**Purpose:** Validate foreign key relationships

**Example:**
```python
# Get valid security IDs from dimension table
valid_securities = get_valid_security_ids()

rule = ReferentialIntegrityRule(
    column='security_id',
    reference_values=valid_securities,
    reference_name='dim_security'
)
```

**When Applied:** All fact tables referencing dimensions

---

### Completeness Rules

#### RecordCountRule
**Purpose:** Validate expected number of records

**Example:**
```python
# NSE has ~2000 listed securities
rule = RecordCountRule(
    expected_count=2000,
    tolerance_pct=10.0  # Allow ±10%
)
```

**When Applied:** Daily price data (expect ~2000 securities/day)

---

#### DateGapRule
**Purpose:** Detect missing data for date ranges

**Example:**
```python
rule = DateGapRule(
    date_column='price_date',
    security_id_column='security_id',
    max_gap_days=5  # Flag gaps > 5 days (weekends + holidays)
)
```

**When Applied:** Time series data (prices, flows)

---

### Consistency Rules

#### DuplicateCheckRule
**Purpose:** Ensure no duplicate records exist

**Example:**
```python
rule = DuplicateCheckRule(
    key_columns=['security_id', 'price_date']
)
```

**When Applied:** All data types before loading

---

## 4. Temporal Governance

### Point-in-Time Correctness

**Critical Requirement:** Investment research must use only data that was available at the analysis date to prevent look-ahead bias.

### Temporal Validator

**Location:** `api/temporal_validator.py`

The Temporal Validator ensures queries maintain temporal correctness:

```python
validator = TemporalValidator()
result = validator.validate(
    query=user_query,
    as_of_date=date(2024, 1, 15)
)

if not result.is_valid:
    raise ValidationError(result.errors)
```

### Temporal Validation Rules

#### Rule 1: Temporal Tables Must Have Date Filters

**Temporal Tables:**
- `fact_quarterly_financials` → Must filter on `publication_date`
- `vault_financials` → Must filter on `publication_date` or `valid_from`/`valid_to`
- `dim_security` → Must filter on `valid_from`/`valid_to` (SCD Type 2)
- `dim_index_constituents` → Must filter on `effective_date`/`exit_date`

**Example Error:**
```
Temporal table 'fact_quarterly_financials' must include a filter on: publication_date
```

**Suggested Fix:**
```sql
WHERE publication_date <= '2024-01-15'
```

---

#### Rule 2: Joins Must Preserve Temporal Alignment

**Example: Joining Prices with Financials**

❌ **WRONG** (Look-ahead bias):
```sql
SELECT p.price_date, p.close, f.revenue
FROM fact_daily_prices p
JOIN fact_quarterly_financials f
  ON p.security_key = f.security_key
```

✅ **CORRECT** (Temporally aligned):
```sql
SELECT p.price_date, p.close, f.revenue
FROM fact_daily_prices p
JOIN fact_quarterly_financials f
  ON p.security_key = f.security_key
  AND f.publication_date <= p.price_date  -- CRITICAL
```

---

#### Rule 3: No Future Data References

**Example Error:**
```
Query references future date '2024-06-01' which is after as_of_date '2024-01-15'
```

**Validation:**
- Checks all date literals in query
- Flags dates after `as_of_date`
- Warns about `CURRENT_DATE` usage in historical analysis

---

#### Rule 4: Window Functions Must Not Look Forward

**Example Warning:**
```
LEAD window function detected - ensure it doesn't create look-ahead bias
```

**Risky Patterns:**
- `LEAD()` function
- `ROWS BETWEEN ... FOLLOWING`

**Safe Usage:**
```sql
-- Safe: Looking backward
LAG(close, 1) OVER (PARTITION BY security_id ORDER BY price_date)

-- Risky: Looking forward
LEAD(close, 1) OVER (PARTITION BY security_id ORDER BY price_date)
```

---

## 5. Monitoring and Alerting

### Control Tables

**Location:** `redshift/schemas/02_create_control_tables.sql`

#### ETL Job Log
```sql
CREATE TABLE control.etl_job_log (
    job_log_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    job_name VARCHAR(200),
    start_time TIMESTAMP,
    end_time TIMESTAMP,
    status VARCHAR(20),  -- RUNNING, SUCCESS, FAILED
    records_processed BIGINT,
    error_message VARCHAR(MAX)
);
```

**Purpose:** Track all ETL job executions

---

#### Data Quality Results
```sql
CREATE TABLE control.data_quality_results (
    check_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    check_name VARCHAR(200),
    table_name VARCHAR(200),
    check_timestamp TIMESTAMP,
    check_status VARCHAR(20),  -- PASS, FAIL, WARNING
    records_checked BIGINT,
    records_failed BIGINT,
    failure_details VARCHAR(MAX)
);
```

**Purpose:** Store all validation results for trending and analysis

---

#### Query Audit Log
```sql
CREATE TABLE control.query_audit_log (
    query_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    user_name VARCHAR(100),
    query_text VARCHAR(MAX),
    query_timestamp TIMESTAMP,
    execution_time_ms INTEGER,
    rows_returned BIGINT,
    query_status VARCHAR(20)
);
```

**Purpose:** Audit all queries for compliance and performance analysis

---

### Alerting Strategy

#### Alert Levels

| Level | Trigger | Action | Example |
|-------|---------|--------|---------|
| **CRITICAL** | Pass rate < 95% | Immediate SNS alert + PagerDuty | Schema validation failure |
| **HIGH** | Pass rate < 98% | SNS alert | >5% price outliers |
| **MEDIUM** | Warnings detected | Email notification | Date gaps detected |
| **LOW** | Informational | Log only | Successful validation |

#### Alert Workflow

```
Validation Failure
       ↓
Check Pass Rate
       ↓
< 95%? → CRITICAL → SNS + PagerDuty + Quarantine
< 98%? → HIGH → SNS + Quarantine
Warnings? → MEDIUM → Email
Pass → LOW → Log only
```

#### SNS Alert Example

```
Subject: Data Quality Alert: prices - Pass Rate 92%

File: nse_prices_20240115.csv
Timestamp: 2024-01-15 08:30:00

Summary:
- Pass Rate: 92%
- Total Rules: 10
- Passed: 9
- Failed: 1

Failed Rules:
- PriceChange: 150 price changes > 50%. Examples: RELIANCE on 2024-01-15: 75% change

Action Required: Review quarantined data and investigate failures.
```

---

### Quarantine Process

**Location:** `s3://itus-data-lake/quarantine/`

#### Quarantine Structure
```
quarantine/
├── prices/
│   ├── PriceChangeRule/
│   │   └── 20240115_083000_nse_prices.csv
│   └── NullCheckRule/
│       └── 20240115_083000_nse_prices.csv
├── financials/
│   └── BalanceSheetBalanceRule/
│       └── 20240115_090000_quarterly_financials.csv
```

#### Quarantine Metadata
```python
{
    'rule_name': 'PriceChangeRule',
    'failed_count': '150',
    'original_file': 'nse_prices_20240115.csv',
    'timestamp': '20240115_083000'
}
```

#### Quarantine Review Process
1. Data engineer receives alert
2. Downloads quarantined file from S3
3. Investigates root cause
4. Corrects source data or adjusts validation rules
5. Re-uploads corrected file
6. Marks quarantine record as resolved

---

## 6. Audit and Compliance

### Audit Trail

Every data operation is logged for compliance:

1. **Data Ingestion**
   - Source file name and location
   - Ingestion timestamp
   - Validation results
   - Records processed

2. **Data Transformation**
   - ETL job name and run ID
   - Start/end timestamps
   - Records inserted/updated
   - Error messages

3. **Data Access**
   - User name
   - Query text
   - Execution timestamp
   - Rows returned

### Compliance Features

#### Data Lineage
- Track data from source to consumption
- Identify upstream dependencies
- Impact analysis for schema changes

#### Data Retention
- Staging: 7 days
- Integration: 2 years
- Presentation: 5 years
- Audit logs: 7 years

#### Access Control
- Role-based access (RBAC)
- Query audit logging
- Sensitive data masking

---

## Implementation Example: Price Data Validation

### Complete Validation Flow

**File:** `lambda/validators/price_validator.py`

```python
def lambda_handler(event, context):
    # 1. Extract S3 info
    bucket = event['Records'][0]['s3']['bucket']['name']
    key = event['Records'][0]['s3']['object']['key']
    
    # 2. Download and parse
    df = download_and_parse(bucket, key)
    
    # 3. Define validation rules
    rules = [
        RequiredColumnsRule(['security_id', 'price_date', 'close']),
        NullCheckRule(['security_id', 'price_date', 'close']),
        PositiveValueRule(['close', 'volume']),
        PriceChangeRule('close', max_change_pct=50.0),
        DuplicateCheckRule(['security_id', 'price_date']),
        DateGapRule('price_date', max_gap_days=5)
    ]
    
    # 4. Execute validation
    engine = DataQualityEngine(
        s3_quarantine_bucket='itus-data-lake',
        sns_topic_arn='arn:aws:sns:...',
        redshift_conn=get_redshift_connection()
    )
    
    summary = engine.validate_and_process(
        df=df,
        rules=rules,
        data_source='prices',
        file_name=key
    )
    
    # 5. Handle results
    if summary['pass_rate'] >= 95:
        trigger_glue_etl(bucket, key)
        return {'statusCode': 200}
    else:
        # Already quarantined and alerted by engine
        return {'statusCode': 400}
```

---

## Summary

### Governance Layers
1. ✅ **Ingestion** - Lambda validators with 15+ validation rules
2. ✅ **ETL** - Glue jobs with referential integrity checks
3. ✅ **Database** - Redshift constraints and check rules
4. ✅ **Query** - API temporal validation and access control

### Quality Dimensions
1. ✅ **Completeness** - Required fields, record counts, date gaps
2. ✅ **Accuracy** - Business rules, range checks, balance validation
3. ✅ **Consistency** - Duplicates, referential integrity
4. ✅ **Timeliness** - ETL monitoring, SLA tracking
5. ✅ **Validity** - Schema, data types, string lengths
6. ✅ **Integrity** - Foreign keys, temporal alignment

### Key Features
- **15+ validation rule types** covering all quality dimensions
- **Multi-layer defense** catches issues at every stage
- **Automatic quarantine** preserves failed data for investigation
- **Proactive alerting** via SNS for critical failures
- **Complete audit trail** for compliance
- **Temporal correctness** prevents look-ahead bias
- **Point-in-time queries** ensure research integrity

### Files Reference
- Rules: `lambda/validators/data_quality_rules.py`
- Engine: `lambda/validators/data_quality_engine.py`
- Price Validator: `lambda/validators/price_validator.py`
- Temporal Validator: `api/temporal_validator.py`
- Control Tables: `redshift/schemas/02_create_control_tables.sql`
