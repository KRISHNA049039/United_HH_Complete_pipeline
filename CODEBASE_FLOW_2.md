# Research Data Platform V2 - Complete Codebase Flow (Part 2)

## 3. Critical Data Strategies

### Strategy 1: Bi-Temporal Data Model

**Where Implemented:**
- `redshift/schemas/04_create_vault_tables.sql`
- `glue/quarterly_financials_etl.py`

**Purpose:** Track both valid time and transaction time

**Code Example:**
```sql
-- vault_financials table
CREATE TABLE integration.vault_financials (
    vault_key BIGINT IDENTITY(1,1),
    security_id VARCHAR(50),
    reporting_period_end DATE,        -- Valid time
    publication_date DATE,             -- Transaction time
    metric_value DECIMAL(18,4),
    valid_from TIMESTAMP,              -- System time start
    valid_to TIMESTAMP,                -- System time end
    is_current BOOLEAN,
    hash_diff VARCHAR(64)
);
```

**Why:** Enables point-in-time correctness and restatement handling

---

### Strategy 2: Job Bookmarks (Incremental Processing)

**Where Implemented:**
- All Glue ETL jobs
- `glue/daily_prices_etl.py`

**Purpose:** Process only new data, not full reload

**Code Example:**
```python
# Glue job with bookmarks
datasource = glueContext.create_dynamic_frame.from_options(
    connection_type="s3",
    connection_options={
        "paths": ["s3://itus-data-lake/raw/prices/"],
        "recurse": True
    },
    format="csv",
    transformation_ctx="datasource"  # CRITICAL: Enables bookmarks
)

# Process data...

# Commit job - updates bookmark
job.commit()  # CRITICAL: Updates bookmark state
```

**Why:** 90%+ cost reduction, faster processing

---

### Strategy 3: Idempotent Pipeline Design

**Where Implemented:**
- All ETL stages
- `redshift/schemas/staging_to_integration.sql`

**Purpose:** Safe retries, consistent results

**Code Example:**
```sql
-- Staging: Truncate and load
BEGIN TRANSACTION;
DELETE FROM staging.stg_prices WHERE price_date = '2024-01-01';
COPY staging.stg_prices FROM 's3://...';
COMMIT;

-- Integration: Merge/upsert
BEGIN TRANSACTION;
DELETE FROM integration.prices WHERE price_date = '2024-01-01';
INSERT INTO integration.prices SELECT * FROM staging.stg_prices;
COMMIT;

-- Presentation: Insert with dedup
INSERT INTO fact_daily_prices
SELECT * FROM integration.prices
WHERE NOT EXISTS (
    SELECT 1 FROM fact_daily_prices f
    WHERE f.price_date = p.price_date 
      AND f.security_key = p.security_key
);
```

**Why:** Can safely rerun jobs without duplicates

---

### Strategy 4: Corporate Action Adjustments

**Where Implemented:**
- `redshift/schemas/05_create_corporate_actions.sql`
- `glue/corporate_actions_etl.py`

**Purpose:** Adjust historical prices for splits, dividends

**Code Example:**
```sql
-- Calculate cumulative adjustment factors
WITH adjustments AS (
    SELECT 
        security_id,
        ex_date,
        adjustment_factor,
        EXP(SUM(LN(adjustment_factor)) OVER (
            PARTITION BY security_id 
            ORDER BY ex_date DESC
        )) as cumulative_factor
    FROM corporate_actions
)
SELECT 
    p.price_date,
    p.close_price as unadjusted,
    p.close_price * COALESCE(a.cumulative_factor, 1.0) as adjusted
FROM prices p
LEFT JOIN adjustments a 
    ON p.security_id = a.security_id 
    AND p.price_date < a.ex_date;
```

**Why:** Accurate return calculations across corporate actions

---

### Strategy 5: Temporal Validation

**Where Implemented:**
- `api/temporal_validator.py`
- `api/main.py`

**Purpose:** Prevent look-ahead bias in queries

**Code Example:**
```python
class TemporalValidator:
    def validate(self, query, as_of_date):
        # Check 1: Temporal tables have date filters
        if 'fact_quarterly_financials' in query:
            if 'publication_date' not in query:
                return ValidationError(
                    "Must filter on publication_date"
                )
        
        # Check 2: No future data references
        if self.contains_future_date(query, as_of_date):
            return ValidationError("Query references future data")
        
        # Check 3: Joins preserve temporal alignment
        if not self.validate_temporal_joins(query):
            return ValidationError("Join breaks temporal correctness")
        
        return ValidationSuccess()
```

**Why:** Critical for investment research integrity

---

### Strategy 6: Performance Optimization

**Where Implemented:**
- `redshift/optimize_tables.sql`
- `redshift/schemas/07_create_materialized_views.sql`

**Purpose:** Sub-5-second query performance

**Code Example:**
```sql
-- Sort keys for zone map pruning
CREATE TABLE fact_daily_prices (
    price_date DATE,
    security_key INTEGER,
    close_price DECIMAL(18,4)
)
DISTKEY(security_key)
COMPOUND SORTKEY(price_date, security_key);  -- CRITICAL

-- Materialized views for precomputation
CREATE MATERIALIZED VIEW mv_precomputed_ratios AS
SELECT
    security_key,
    reporting_period_end,
    ebitda / NULLIF(revenue, 0) AS ebitda_margin,
    net_income / NULLIF(revenue, 0) AS net_margin
FROM fact_quarterly_financials;

-- Refresh daily
REFRESH MATERIALIZED VIEW mv_precomputed_ratios;
```

**Why:** 5-10x query speedup

---

**Continue to [Part 3](CODEBASE_FLOW_3.md) for Code Organization and Implementation Details**
