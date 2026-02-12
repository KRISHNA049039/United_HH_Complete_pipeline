# Research Data Platform V2 - Complete Architecture Guide

## Table of Contents

1. [System Overview](#system-overview)
2. [Architecture Components](#architecture-components)
3. [Data Flow](#data-flow)
4. [Key Concepts](#key-concepts)
5. [Technology Stack](#technology-stack)
6. [Design Patterns](#design-patterns)

## System Overview

The Research Data Platform V2 is a temporal data warehouse built on AWS, designed to provide research-safe financial data for equity investment analysis. The platform ensures:

- **Point-in-Time Correctness**: No look-ahead bias in historical queries
- **Survivorship-Bias-Free**: Includes delisted securities in historical analysis
- **High Performance**: Sub-5-second query response for typical workloads
- **Data Quality**: Comprehensive validation at every stage
- **Cost Optimization**: Intelligent scaling and storage management

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Data Sources                              │
│  (Market Data Provider, Financial Statements, FII/DII Flows)    │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Ingestion Layer (AWS)                         │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐                 │
│  │ S3 Data  │───▶│  Lambda  │───▶│   Glue   │                 │
│  │   Lake   │    │Validators│    │ ETL Jobs │                 │
│  └──────────┘    └──────────┘    └──────────┘                 │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│              Amazon Redshift Data Warehouse                      │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐                 │
│  │ Staging  │───▶│Integration│───▶│Presentation│               │
│  │   Zone   │    │   Zone    │    │    Zone    │               │
│  └──────────┘    └──────────┘    └──────────┘                 │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Query Layer                                 │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐                 │
│  │ FastAPI  │───▶│  Redis   │    │    NL    │                 │
│  │ Service  │    │  Cache   │    │  Engine  │                 │
│  └──────────┘    └──────────┘    └──────────┘                 │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Analyst Tools                                  │
│         (Python/Jupyter, Excel, Tableau, PowerBI)               │
└─────────────────────────────────────────────────────────────────┘
```

## Architecture Components

### 1. Data Ingestion Layer

#### S3 Data Lake

**Purpose**: Centralized storage for all raw and processed data

**Structure**:
```
s3://itus-data-lake/
├── raw/                    # Raw data files from sources
│   ├── prices/YYYY/MM/DD/
│   ├── financials/YYYY/QQ/
│   ├── flows/YYYY/MM/DD/
│   └── macro/YYYY/MM/DD/
├── processed/              # Processed data ready for loading
├── archive/                # Archived data (Glacier storage)
└── quarantine/             # Failed validation data
```

**Features**:
- Versioning enabled for data lineage
- Lifecycle policies for cost optimization
- Event notifications trigger downstream processing

#### Lambda Validators

**Purpose**: Immediate validation of incoming data before processing

**Validators**:
1. **price_validator.py**: Validates OHLCV data
   - Schema compliance
   - Required fields present
   - Price ranges reasonable
   - Date formats correct

2. **financial_validator.py**: Validates financial statements
   - Null checks on required fields
   - Referential integrity (security IDs exist)
   - Balance sheet balancing
   - Reasonable metric ranges

**Flow**:
```
S3 Event → Lambda Validator → [Valid] → Trigger Glue ETL
                            → [Invalid] → SQS DLQ + SNS Alert
```

#### Glue ETL Jobs

**Purpose**: Transform and load data from S3 to Redshift

**Jobs**:
1. **daily_prices_etl**: Loads OHLCV data
2. **quarterly_financials_etl**: Loads financial statements
3. **daily_flows_etl**: Loads institutional flow data
4. **corporate_actions_etl**: Loads corporate action events
5. **index_constituents_etl**: Loads index membership changes

**Key Features**:
- Incremental loading using bookmarks
- Idempotent processing
- Error handling and retry logic
- Metrics publishing to CloudWatch


### 2. Data Warehouse (Amazon Redshift)

#### Staging Zone

**Purpose**: Temporary landing area for raw data

**Characteristics**:
- Minimal transformation
- EVEN distribution for parallel loading
- No indexes or constraints
- Data retained for 7 days

**Tables**:
- `staging.stg_prices`
- `staging.stg_financials`
- `staging.stg_flows`

#### Integration Zone

**Purpose**: Apply business logic and temporal versioning

**Key Tables**:

1. **vault_financials**: Bi-temporal storage
   - Stores all versions of financial data
   - Never updates, only inserts
   - Tracks valid_from, valid_to, publication_date

2. **corporate_actions**: Corporate action events
   - Splits, dividends, bonuses, mergers
   - Adjustment factors calculated

3. **price_adjustments**: Adjusted price history
   - Cumulative adjustment factors
   - Both adjusted and unadjusted prices

#### Presentation Zone

**Purpose**: Optimized star schema for analytics

**Fact Tables**:
- `fact_daily_prices`: Daily OHLCV data (20M rows)
- `fact_quarterly_financials`: Quarterly financials (240K rows)
- `fact_institutional_flows`: FII/DII flows (15M rows)

**Dimension Tables**:
- `dim_security`: Type 2 SCD for securities
- `dim_date`: Date dimension with fiscal calendar
- `dim_index_constituents`: Temporal index membership

**Materialized Views**:
- `mv_precomputed_ratios`: 20+ financial ratios
- `mv_rolling_returns`: Rolling returns and momentum
- `mv_current_index_constituents`: Current index snapshot

### 3. Query Layer

#### FastAPI Service

**Purpose**: REST API for data access with validation

**Endpoints**:
- `/api/v1/query/execute`: Execute SQL queries
- `/api/v1/query/validate`: Validate temporal correctness
- `/api/v1/query/estimate`: Estimate query cost
- `/api/v1/nl/translate`: Natural language to SQL

**Features**:
- Connection pooling to Redshift
- Query result caching (Redis, 24-hour TTL)
- Temporal validation
- Performance estimation
- Audit logging

#### Temporal Validator

**Purpose**: Ensure queries maintain point-in-time correctness

**Validation Rules**:
1. Temporal tables must include date filters
2. Joins must align temporal granularities
3. No future-dated data references
4. Window functions don't look forward

#### Performance Estimator

**Purpose**: Prevent expensive queries from executing

**Estimation Logic**:
- Estimates rows scanned based on table sizes
- Applies selectivity based on WHERE clauses
- Calculates cost per million rows
- Rejects queries exceeding 100M rows

### 4. Monitoring & Operations

#### CloudWatch

**Log Groups**:
- `/aws/lambda/price-validator`
- `/aws/glue/daily-prices-etl`
- `/ecs/research-platform-api`

**Custom Metrics**:
- QueryExecutionTime
- DataQualityPassRate
- ETLJobDuration
- CacheHitRate

#### SNS Alerting

**Topics**:
- `critical-alerts`: Platform failures
- `data-quality-alerts`: Validation failures
- `etl-job-alerts`: ETL failures
- `performance-alerts`: Performance issues

**Alarms**:
- ETL job failures
- Data quality pass rate < 95%
- Query timeout rate > 5%
- Redshift CPU > 80%

## Data Flow

### Daily Price Data Flow

```
1. Market Data Provider → S3 (raw/prices/YYYY/MM/DD/prices.csv)
2. S3 Event → Lambda Validator
3. Validator checks:
   - Schema compliance
   - Required fields
   - Price ranges
   - Statistical outliers
4. [Valid] → Trigger Glue ETL
5. Glue ETL:
   - Read from S3 with bookmark
   - Transform data
   - Load to staging.stg_prices
6. Staging → Integration:
   - Apply corporate action adjustments
   - Calculate cumulative factors
7. Integration → Presentation:
   - Load to fact_daily_prices
   - Update materialized views
8. Publish metrics to CloudWatch
9. Send success notification
```

### Quarterly Financial Data Flow

```
1. Financial Statements → S3 (raw/financials/YYYY/QQ/financials.csv)
2. S3 Event → Lambda Validator
3. Validator checks:
   - Null checks
   - Balance sheet balancing
   - Referential integrity
4. [Valid] → Trigger Glue ETL
5. Glue ETL:
   - Read from S3 with bookmark
   - Transform data
   - Load to staging.stg_financials
6. Staging → Integration:
   - Insert into vault_financials
   - Preserve temporal versions
   - Handle restatements
7. Integration → Presentation:
   - Load to fact_quarterly_financials
   - Update mv_precomputed_ratios
8. Publish metrics to CloudWatch
9. Send success notification
```

## Key Concepts

### 1. Bi-Temporal Data Modeling

**Definition**: Tracking two time dimensions for each fact

**Time Dimensions**:
1. **Valid Time (Business Time)**: When the fact was true in reality
   - Example: Reporting period end date (2022-12-31)

2. **Transaction Time (System Time)**: When we learned about the fact
   - Example: Publication date (2023-04-15)

**Benefits**:
- Point-in-time correctness
- Handle restatements
- Reproducible backtests
- Audit trail

**Example**:
```sql
-- Original financial statement
reporting_period_end: 2022-12-31
publication_date: 2023-04-15
revenue: 1000
valid_from: 2023-04-15
valid_to: NULL
is_current: TRUE

-- Restated financial statement
reporting_period_end: 2022-12-31
publication_date: 2023-07-20
revenue: 950
valid_from: 2023-07-20
valid_to: NULL
is_current: TRUE

-- Original record updated
valid_to: 2023-07-20
is_current: FALSE
```

### 2. Survivorship Bias Prevention

**Problem**: Analyzing only currently existing securities ignores those that ceased to exist

**Solution**: Maintain complete lifecycle for all securities

**Implementation**:
```sql
-- dim_security tracks lifecycle
CREATE TABLE dim_security (
    security_key INTEGER,
    security_id VARCHAR(50),
    listing_date DATE,
    delisting_date DATE,
    delisting_reason VARCHAR(200),
    is_current BOOLEAN
);

-- Query includes delisted securities
SELECT * FROM dim_security
WHERE listing_date <= '2020-01-01'
  AND (delisting_date IS NULL OR delisting_date > '2020-01-01');
```

### 3. Corporate Action Adjustments

**Purpose**: Adjust historical prices for splits, dividends, etc.

**Adjustment Logic**:
```
For stock split 1:2 on date D:
- All prices before D are multiplied by 0.5

For dividend of Rs 10 on stock trading at Rs 100:
- Adjustment factor = 90/100 = 0.9
- All prices before ex-date multiplied by 0.9

Multiple actions cascade:
- Cumulative factor = factor1 × factor2 × factor3
```

**Implementation**:
```sql
-- Calculate cumulative adjustment factor
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
    p.close_price * a.cumulative_factor as adjusted
FROM prices p
LEFT JOIN adjustments a ON p.security_id = a.security_id
    AND p.price_date < a.ex_date;
```


### 4. Slowly Changing Dimensions (Type 2)

**Purpose**: Track historical changes to dimension attributes

**Implementation**:
```sql
CREATE TABLE dim_security (
    security_key INTEGER IDENTITY(1,1),  -- Surrogate key
    security_id VARCHAR(50),              -- Natural key
    security_name VARCHAR(200),
    sector VARCHAR(100),
    valid_from DATE,                      -- Start of validity
    valid_to DATE,                        -- End of validity
    is_current BOOLEAN                    -- Current version flag
);

-- When sector changes, insert new row
INSERT INTO dim_security VALUES (
    'INE123A01012',
    'Reliance Industries',
    'Energy',  -- Changed from 'Oil & Gas'
    '2023-01-01',
    NULL,
    TRUE
);

-- Update old row
UPDATE dim_security
SET valid_to = '2023-01-01', is_current = FALSE
WHERE security_id = 'INE123A01012' AND is_current = TRUE;
```

### 5. Materialized Views

**Purpose**: Precompute expensive aggregations for fast queries

**Benefits**:
- 5-10x faster query performance
- Reduced compute costs
- Consistent calculations

**Trade-offs**:
- Additional storage (~300 GB)
- Refresh overhead (daily at 7 AM)
- Staleness (up to 24 hours)

**Example**:
```sql
CREATE MATERIALIZED VIEW mv_precomputed_ratios AS
SELECT
    security_key,
    reporting_period_end,
    revenue,
    ebitda,
    net_income,
    ebitda / NULLIF(revenue, 0) AS ebitda_margin,
    net_income / NULLIF(revenue, 0) AS net_margin,
    -- 20+ more ratios
FROM fact_quarterly_financials;

-- Refresh daily
REFRESH MATERIALIZED VIEW mv_precomputed_ratios;
```

## Technology Stack

### Cloud Platform: AWS

**Services Used**:
- **S3**: Data lake storage
- **Lambda**: Serverless validation functions
- **Glue**: ETL orchestration
- **Redshift**: Data warehouse
- **ECS Fargate**: API service hosting
- **CloudWatch**: Logging and monitoring
- **SNS**: Alerting
- **EventBridge**: Event-driven orchestration

### Data Warehouse: Amazon Redshift

**Cluster Configuration**:
- Node Type: RA3.4xlarge
- Initial Size: 2 nodes (192 GB RAM, 24 vCPU)
- Auto-scaling: Up to 4 nodes during peak hours
- Concurrency Scaling: Enabled (up to 10 clusters)

**Key Features**:
- Columnar storage with compression
- Massively parallel processing (MPP)
- Zone maps for partition pruning
- Result caching
- Automatic table optimization (ATO)

### Query API: Python FastAPI

**Framework**: FastAPI 0.100+
**Database Driver**: psycopg2
**Caching**: Redis
**Deployment**: Docker on ECS Fargate

**Dependencies**:
```
fastapi==0.100.0
uvicorn==0.23.0
psycopg2-binary==2.9.6
redis==4.6.0
pydantic==2.0.0
boto3==1.28.0
```

### Monitoring: CloudWatch + Grafana

**CloudWatch**:
- Log aggregation
- Custom metrics
- Alarms and notifications

**Grafana** (Optional):
- Visual dashboards
- Query performance trends
- Data quality metrics
- Cost tracking

## Design Patterns

### 1. Lambda Architecture

**Batch Layer**: Glue ETL jobs process historical data
**Speed Layer**: Lambda validators for real-time validation
**Serving Layer**: Redshift presentation zone for queries

### 2. Medallion Architecture

**Bronze (Staging)**: Raw data, minimal transformation
**Silver (Integration)**: Cleaned, validated, temporal versioning
**Gold (Presentation)**: Aggregated, optimized for analytics

### 3. Event-Driven Architecture

**Events**:
- S3 object created → Lambda validator
- Validation success → Glue ETL trigger
- ETL completion → Materialized view refresh
- Data quality failure → SNS alert

### 4. CQRS (Command Query Responsibility Segregation)

**Write Path**: Glue ETL → Staging → Integration → Presentation
**Read Path**: API → Redis Cache → Redshift Presentation

### 5. Circuit Breaker Pattern

**Implementation**: Retry logic with exponential backoff

```python
def execute_with_retry(func, max_retries=3):
    for attempt in range(max_retries):
        try:
            return func()
        except Exception as e:
            if attempt == max_retries - 1:
                raise
            wait_time = 2 ** attempt  # Exponential backoff
            time.sleep(wait_time)
```

### 6. Strangler Fig Pattern

**Purpose**: Gradually migrate from old system to new

**Phases**:
1. Build new system alongside old
2. Route some queries to new system
3. Gradually increase traffic to new system
4. Decommission old system

### 7. Data Vault Pattern

**Purpose**: Maintain complete audit trail of all data changes

**Implementation**:
- Hub tables: Business keys
- Link tables: Relationships
- Satellite tables: Descriptive attributes with history

**Example**:
```sql
-- Hub: Business entities
CREATE TABLE hub_security (
    security_hub_key BIGINT,
    security_id VARCHAR(50),
    load_timestamp TIMESTAMP
);

-- Satellite: Attributes with history
CREATE TABLE sat_security_details (
    security_hub_key BIGINT,
    security_name VARCHAR(200),
    sector VARCHAR(100),
    valid_from TIMESTAMP,
    valid_to TIMESTAMP,
    load_timestamp TIMESTAMP
);
```

## Performance Optimization Strategies

### 1. Distribution Keys (DISTKEY)

**Purpose**: Co-locate related data on same node

**Strategy**:
- Fact tables: DISTKEY on join key (security_key)
- Small dimensions: DISTSTYLE ALL (replicate)
- Large dimensions: DISTKEY on primary key

### 2. Sort Keys (SORTKEY)

**Purpose**: Enable zone map pruning

**Strategy**:
- Compound sort key for multiple columns
- First column: Most filtered (usually date)
- Second column: Join key

**Example**:
```sql
CREATE TABLE fact_daily_prices (
    price_date DATE,
    security_key INTEGER,
    close_price DECIMAL(18,4)
)
DISTKEY(security_key)
COMPOUND SORTKEY(price_date, security_key);
```

### 3. Compression

**Purpose**: Reduce storage and I/O

**Strategy**:
- Run ANALYZE COMPRESSION
- Apply recommended encodings
- Typical compression: 3-4x for numeric, 8-10x for varchar

### 4. Workload Management (WLM)

**Purpose**: Prioritize and isolate workloads

**Configuration**:
```
Queue 1 (ETL): 40% memory, 2 slots, 1 hour timeout
Queue 2 (Analyst): 50% memory, 5 slots, 5 min timeout, concurrency scaling
Queue 3 (Admin): 10% memory, 1 slot, no timeout
```

### 5. Result Caching

**Layers**:
1. **Redshift Result Cache**: Automatic, identical queries
2. **Redis Cache**: Application-level, 24-hour TTL
3. **Materialized Views**: Precomputed aggregations

### 6. Concurrency Scaling

**Purpose**: Handle query spikes without queueing

**Configuration**:
- Enabled for analyst queue
- Up to 10 additional clusters
- Free tier: 1 hour per day
- Cost: ~$5/hour beyond free tier

## Security & Compliance

### 1. Network Security

**VPC Configuration**:
- Redshift in private subnet
- API service in public subnet with ALB
- Security groups restrict access

### 2. Data Encryption

**At Rest**:
- S3: SSE-S3 or SSE-KMS
- Redshift: AES-256 encryption

**In Transit**:
- TLS 1.2+ for all connections
- SSL for Redshift connections

### 3. Access Control

**IAM Roles**:
- Lambda execution role (read S3, write CloudWatch)
- Glue execution role (read S3, write Redshift)
- API service role (read Redshift, write CloudWatch)

**Redshift Users**:
- ETL user: Write access to staging/integration
- Analyst user: Read access to presentation
- Admin user: Full access

### 4. Audit Logging

**Logged Events**:
- All queries (user, timestamp, duration)
- Data quality results
- ETL job executions
- API requests

**Retention**:
- CloudWatch logs: 30 days
- Redshift audit logs: 7 days
- Control table logs: Indefinite

## Cost Optimization

### 1. Compute Costs

**Strategies**:
- Pause cluster during off-hours (nights/weekends)
- Scale down to 2 nodes during low activity
- Use concurrency scaling free tier
- Optimize expensive queries

**Estimated Costs**:
- Redshift (2 nodes, RA3.4xlarge): ~$3,000/month
- Concurrency scaling: ~$500/month
- ECS Fargate: ~$200/month

### 2. Storage Costs

**Strategies**:
- S3 lifecycle policies (Glacier after 90 days)
- Compress historical data
- Delete processed files after 180 days
- Use RA3 nodes (managed storage)

**Estimated Costs**:
- S3 storage (2 TB): ~$50/month
- Redshift storage (included with RA3)

### 3. Data Transfer Costs

**Strategies**:
- Keep data in same region
- Use VPC endpoints for S3 access
- Compress data before transfer

**Estimated Costs**:
- Minimal (same region)

### Total Estimated Monthly Cost: $3,500 - $5,000
