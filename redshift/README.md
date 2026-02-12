# Redshift Database Schemas

This directory contains SQL scripts for creating and managing the Redshift database schemas for the Research Data Platform V2.

## Schema Architecture

The platform uses a layered architecture with four schemas:

### 1. Staging Schema
- **Purpose**: Temporary landing area for raw data from S3
- **Characteristics**: 
  - Data validated but not transformed
  - Short retention (cleared after successful processing)
  - DISTSTYLE EVEN for parallel loading

### 2. Integration Schema
- **Purpose**: Business logic, temporal versioning, historical vault
- **Characteristics**:
  - Bi-temporal data model (valid time + transaction time)
  - Immutable append-only tables
  - Full audit trail

### 3. Presentation Schema
- **Purpose**: Optimized star schema for analyst queries
- **Characteristics**:
  - Fact and dimension tables
  - Precomputed aggregations
  - Materialized views
  - Optimized for query performance

### 4. Control Schema
- **Purpose**: ETL metadata, job tracking, data quality
- **Characteristics**:
  - High-water marks for incremental loading
  - Job execution logs
  - Data quality check results
  - Query audit logs

## Dimension Tables

### dim_security
Master dimension of all securities with Type 2 SCD.

**Key Features:**
- Tracks security attribute changes over time
- Maintains delisted securities (no survivorship bias)
- DISTSTYLE ALL (replicated to all nodes)

**Columns:**
- `security_key`: Surrogate key
- `security_id`: Business key (ISIN, NSE symbol, etc.)
- `valid_from`, `valid_to`: SCD Type 2 tracking
- `is_current`: Flag for current version
- `delisting_date`, `delisting_reason`: Survivorship tracking

### dim_date
Date dimension with fiscal calendar and trading days.

**Key Features:**
- 20+ years of dates (2000-2030)
- Indian fiscal year (April-March)
- Trading day flags (excludes weekends and holidays)
- Previous/next trading day references

**Columns:**
- `date_key`: Primary key (DATE type)
- `fiscal_year`, `fiscal_quarter`, `fiscal_month`: Indian fiscal calendar
- `is_trading_day`: Excludes weekends and market holidays
- `is_month_end`, `is_quarter_end`, `is_year_end`: Period flags

### dim_index_constituents
Tracks index membership changes over time.

**Key Features:**
- Survivorship-free index history
- Effective and exit dates for each membership
- Supports multiple indices (NIFTY50, NIFTY500, etc.)

**Columns:**
- `index_name`: Index identifier
- `security_key`: Reference to dim_security
- `effective_date`: When security joined index
- `exit_date`: When security left index (NULL if still member)
- `is_current`: Flag for current members

### dim_sector
Sector and industry classification hierarchy.

**Key Features:**
- Multi-level hierarchy (sector → industry → sub-industry)
- Supports multiple classification systems (GICS, ICB)

## Control Tables

### etl_high_water_marks
Tracks last processed date for incremental ETL.

**Usage:**
```sql
-- Get high water mark
SELECT high_water_mark 
FROM control.etl_high_water_marks 
WHERE table_name = 'staging.stg_daily_prices';

-- Update high water mark
UPDATE control.etl_high_water_marks 
SET high_water_mark = '2024-01-15',
    last_updated = GETDATE()
WHERE table_name = 'staging.stg_daily_prices';
```

### etl_job_log
Comprehensive log of all ETL job executions.

**Tracked Metrics:**
- Start/end time, duration
- Records processed/inserted/updated/failed
- Error messages
- Source file

### data_quality_results
Results of data quality validation checks.

**Check Types:**
- Schema validation
- Null checks
- Referential integrity
- Business rules
- Statistical outliers

## Workload Management (WLM)

Three WLM queues configured:

### 1. ETL Queue
- **Memory**: 40%
- **Concurrency**: 2 slots
- **Timeout**: 1 hour
- **Use Case**: Data loading and transformation

### 2. Analyst Queue
- **Memory**: 50%
- **Concurrency**: 5 slots
- **Timeout**: 5 minutes
- **Use Case**: Interactive analyst queries
- **Concurrency Scaling**: Enabled (up to 10 clusters)

### 3. Admin Queue
- **Memory**: 10%
- **Concurrency**: 1 slot
- **Timeout**: None
- **Use Case**: Administrative operations

## Deployment

### Prerequisites

1. Redshift cluster running (Task 1 complete)
2. psql client installed
3. Network access to Redshift cluster

### Deploy All Schemas

```bash
cd redshift
chmod +x deploy_schemas.sh
./deploy_schemas.sh
```

You'll be prompted for:
- Redshift master username
- Redshift master password

### Deploy Individual Scripts

```bash
# Connect to Redshift
psql -h <endpoint> -p 5439 -U <username> -d research_platform

# Execute scripts in order
\i schemas/01_create_schemas.sql
\i schemas/02_create_control_tables.sql
\i schemas/03_configure_wlm.sql
\i schemas/04_create_dimension_tables.sql
\i schemas/05_populate_dim_date.sql
```

## Verification

### Check Schemas

```sql
SELECT schemaname, COUNT(*) AS table_count
FROM pg_tables
WHERE schemaname IN ('staging', 'integration', 'presentation', 'control')
GROUP BY schemaname;
```

### Check Dimension Tables

```sql
-- dim_date should have ~11,000 rows (30 years)
SELECT COUNT(*) FROM presentation.dim_date;

-- Check fiscal year distribution
SELECT fiscal_year, COUNT(*) AS days
FROM presentation.dim_date
GROUP BY fiscal_year
ORDER BY fiscal_year;

-- Check trading days
SELECT 
    COUNT(*) AS total_days,
    SUM(CASE WHEN is_trading_day THEN 1 ELSE 0 END) AS trading_days,
    SUM(CASE WHEN is_weekend THEN 1 ELSE 0 END) AS weekend_days
FROM presentation.dim_date
WHERE year = 2024;
```

### Check Control Tables

```sql
-- Schema version
SELECT * FROM control.schema_versions;

-- ETL high water marks (will be empty initially)
SELECT * FROM control.etl_high_water_marks;
```

## User Management

### Create Users

```sql
-- ETL service user
CREATE USER etl_service PASSWORD 'STRONG_PASSWORD' IN GROUP etl_users;

-- Analyst users
CREATE USER analyst1 PASSWORD 'STRONG_PASSWORD' IN GROUP analyst_users;
CREATE USER analyst2 PASSWORD 'STRONG_PASSWORD' IN GROUP analyst_users;

-- Admin user
CREATE USER platform_admin PASSWORD 'STRONG_PASSWORD' IN GROUP admin_users;
```

### Set Query Group

Users should set their query group to route to appropriate WLM queue:

```sql
-- For ETL jobs
SET query_group TO 'etl';

-- For analyst queries
SET query_group TO 'analyst';

-- For admin tasks
SET query_group TO 'admin';
```

## Maintenance

### Update dim_date for New Year

```sql
-- Add dates for 2031
INSERT INTO presentation.dim_date (...)
SELECT ... FROM generate_series('2031-01-01'::date, '2031-12-31'::date, '1 day');

-- Update previous/next trading days
-- (Run update queries from 05_populate_dim_date.sql)
```

### Update Market Holidays

```sql
-- Mark specific date as non-trading day
UPDATE presentation.dim_date
SET is_trading_day = FALSE
WHERE date_key = '2024-11-01'; -- Diwali 2024
```

### Vacuum and Analyze

```sql
-- Vacuum tables to reclaim space
VACUUM presentation.dim_security;
VACUUM presentation.dim_date;

-- Analyze tables to update statistics
ANALYZE presentation.dim_security;
ANALYZE presentation.dim_date;
```

## Monitoring

### Table Sizes

```sql
SELECT 
    "table" AS table_name,
    size AS size_mb,
    tbl_rows AS row_count
FROM svv_table_info
WHERE "schema" IN ('staging', 'integration', 'presentation', 'control')
ORDER BY size DESC;
```

### WLM Queue Status

```sql
-- Current queue state
SELECT * FROM stv_wlm_service_class_state;

-- Queries in queues
SELECT * FROM stv_wlm_query_state;

-- Queue configuration
SELECT * FROM stv_wlm_service_class_config;
```

### Query Performance

```sql
-- Long-running queries
SELECT 
    query,
    user_name,
    starttime,
    DATEDIFF(seconds, starttime, GETDATE()) AS runtime_seconds,
    query_text
FROM stv_recents
WHERE status = 'Running'
ORDER BY runtime_seconds DESC;
```

## Troubleshooting

### Cannot Connect to Redshift

1. Check security group allows your IP on port 5439
2. Verify cluster is in available state
3. Check VPC routing and NAT gateway
4. Ensure you're connecting from within VPC or via VPN

### WLM Queue Full

1. Check queue depth: `SELECT * FROM stv_wlm_service_class_state;`
2. Kill long-running queries if needed
3. Enable concurrency scaling for analyst queue
4. Increase queue slots if consistently full

### Slow Queries

1. Run VACUUM and ANALYZE on tables
2. Check distribution keys and sort keys
3. Review query execution plan: `EXPLAIN <query>`
4. Consider materialized views for common patterns

## Next Steps

After schemas are deployed:
1. Load initial security master data to dim_security
2. Load index constituent history to dim_index_constituents
3. Proceed to Task 4: Implement temporal data model and historical vault
4. Create fact tables in presentation schema
