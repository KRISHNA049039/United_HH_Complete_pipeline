# Research Data Platform V2 - Technical Documentation

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Data Model](#data-model)
3. [API Reference](#api-reference)
4. [UDF Usage Guide](#udf-usage-guide)
5. [Temporal Query Patterns](#temporal-query-patterns)
6. [Deployment Guide](#deployment-guide)
7. [Troubleshooting](#troubleshooting)

## Architecture Overview

### System Components

The Research Data Platform V2 consists of the following components:

1. **Data Ingestion Layer (AWS)**
   - S3 data lake for raw data storage
   - Lambda validators for data quality checks
   - Glue ETL jobs for data transformation

2. **Data Warehouse (Amazon Redshift)**
   - Staging zone for raw data landing
   - Integration zone with temporal versioning
   - Presentation zone with optimized star schema

3. **Query Layer**
   - FastAPI service for REST endpoints
   - Natural language query translation
   - Temporal validation and performance estimation

4. **Monitoring & Operations**
   - CloudWatch logging and metrics
   - SNS alerting for failures
   - Data quality dashboard

### Technology Stack

- **Cloud Platform**: AWS (S3, Lambda, Glue, Redshift, CloudWatch, SNS)
- **Data Warehouse**: Amazon Redshift (RA3.4xlarge, 2-4 nodes)
- **Query API**: Python FastAPI on ECS Fargate
- **Caching**: Redis for query result caching
- **Monitoring**: CloudWatch + Grafana

## Data Model

### Star Schema Design

The platform uses a star schema with fact and dimension tables:

#### Fact Tables

**fact_daily_prices**
- Contains daily OHLCV data for all securities
- Includes both adjusted and unadjusted prices
- DISTKEY: security_key
- SORTKEY: (price_date, security_key)

**fact_quarterly_financials**
- Contains quarterly financial statements
- Includes point-in-time versioning (publication_date, as_of_date)
- 50+ financial metrics (revenue, EBITDA, net income, etc.)
- DISTKEY: security_key
- SORTKEY: (security_key, reporting_period_end)

**fact_institutional_flows**
- Contains FII/DII buy/sell data
- Net flow calculations included
- DISTKEY: security_key
- SORTKEY: (flow_date, security_key)


#### Dimension Tables

**dim_security**
- Type 2 Slowly Changing Dimension
- Tracks security lifecycle (listing, delisting)
- Includes sector, industry, market cap classification
- DISTSTYLE: ALL (replicated to all nodes)

**dim_date**
- Date dimension with fiscal calendar
- Trading day flags
- DISTSTYLE: ALL

**dim_index_constituents**
- Temporal tracking of index membership
- effective_date and exit_date for point-in-time queries
- DISTSTYLE: ALL

### Temporal Data Model

The platform implements bi-temporal data modeling:

1. **Valid Time**: When the fact was true in reality (e.g., reporting period)
2. **Transaction Time**: When we learned about the fact (e.g., publication date)

This enables:
- Point-in-time correctness (no look-ahead bias)
- Handling of financial restatements
- Reproducible backtests

### Materialized Views

**mv_precomputed_ratios**
- 20+ financial ratios precomputed
- Refreshed daily at 7 AM IST
- Includes margins, returns, leverage ratios

**mv_rolling_returns**
- Rolling returns (1M, 3M, 6M, 1Y, 3Y)
- Momentum indicators
- Refreshed daily

**mv_current_index_constituents**
- Current snapshot of index constituents
- Refreshed daily

## API Reference

### Base URL

```
https://api.research-platform.example.com/api/v1
```

### Authentication

All API requests require JWT authentication (to be implemented).

### Endpoints

#### Execute SQL Query

```http
POST /query/execute
```

**Request Body:**
```json
{
  "query": "SELECT * FROM fact_daily_prices WHERE price_date = '2024-01-01' LIMIT 10",
  "as_of_date": "2024-01-01",
  "cache_enabled": true,
  "timeout_seconds": 60,
  "skip_validation": false
}
```

**Response:**
```json
{
  "data": [...],
  "row_count": 10,
  "execution_time_ms": 234,
  "cached": false,
  "query_id": "abc123"
}
```

#### Validate Query

```http
POST /query/validate
```

**Request Body:**
```json
{
  "query": "SELECT * FROM fact_quarterly_financials",
  "as_of_date": "2024-01-01"
}
```

**Response:**
```json
{
  "is_valid": false,
  "errors": [
    "Temporal table 'fact_quarterly_financials' must include a filter on one of: publication_date, as_of_date"
  ],
  "warnings": [],
  "suggestions": [
    "Add WHERE clause: publication_date <= '2024-01-01'"
  ]
}
```

#### Estimate Query Performance

```http
POST /query/estimate
```

**Request Body:**
```json
{
  "query": "SELECT * FROM fact_daily_prices"
}
```

**Response:**
```json
{
  "estimated_rows": 20000000,
  "estimated_cost_usd": 0.1,
  "should_reject": false,
  "warnings": [
    "Full table scan detected on large table 'fact_daily_prices'"
  ],
  "suggestions": [
    "Add date range filter to fact_daily_prices to reduce rows scanned"
  ]
}
```

#### Natural Language Query

```http
POST /nl/translate
```

**Request Body:**
```json
{
  "natural_language_query": "Show me NIFTY50 constituents as of January 1, 2024",
  "as_of_date": "2024-01-01",
  "execute": false
}
```

**Response:**
```json
{
  "natural_language_query": "Show me NIFTY50 constituents as of January 1, 2024",
  "generated_sql": "SELECT * FROM presentation.get_index_constituents('NIFTY50', '2024-01-01')",
  "validation_result": {
    "is_valid": true,
    "errors": [],
    "warnings": [],
    "suggestions": []
  },
  "performance_estimate": {
    "estimated_rows": 50,
    "estimated_cost_usd": 0.0001,
    "should_reject": false
  }
}
```


## UDF Usage Guide

### Available UDFs

#### get_index_constituents

Get index constituents as of a specific date (survivorship-bias-free).

**Signature:**
```sql
get_index_constituents(
    p_index_name VARCHAR,
    p_as_of_date DATE
) RETURNS TABLE (security_key NUMBER, security_id VARCHAR, security_name VARCHAR)
```

**Example:**
```sql
-- Get NIFTY50 constituents as of Jan 1, 2020
SELECT * FROM presentation.get_index_constituents('NIFTY50', '2020-01-01');
```

#### get_financial_metric_series

Get time series of a financial metric with point-in-time correctness.

**Signature:**
```sql
get_financial_metric_series(
    p_security_key NUMBER,
    p_metric_name VARCHAR,
    p_start_date DATE,
    p_end_date DATE,
    p_as_of_date DATE DEFAULT CURRENT_DATE
) RETURNS TABLE (reporting_period_end DATE, metric_value DECIMAL)
```

**Example:**
```sql
-- Get revenue time series for security 123
SELECT * FROM presentation.get_financial_metric_series(
    123,
    'revenue',
    '2020-01-01',
    '2023-12-31',
    '2024-01-01'
);
```

#### calculate_revenue_cagr

Calculate revenue CAGR over a specified period.

**Signature:**
```sql
calculate_revenue_cagr(
    p_security_key NUMBER,
    p_years NUMBER,
    p_as_of_date DATE DEFAULT CURRENT_DATE
) RETURNS DECIMAL
```

**Example:**
```sql
-- Calculate 10-year revenue CAGR
SELECT 
    s.security_name,
    presentation.calculate_revenue_cagr(s.security_key, 10, '2024-01-01') as cagr_10y
FROM dim_security s
WHERE s.is_current = TRUE
LIMIT 100;
```

## Temporal Query Patterns

### Pattern 1: Point-in-Time Query

Query data as it existed at a specific historical date.

```sql
-- Get financials as they were known on March 31, 2023
SELECT 
    s.security_name,
    f.reporting_period_end,
    f.revenue,
    f.net_income
FROM fact_quarterly_financials f
JOIN dim_security s ON f.security_key = s.security_key
WHERE f.publication_date <= '2023-03-31'
  AND f.reporting_period_end BETWEEN '2022-01-01' AND '2022-12-31'
  AND s.valid_from <= '2023-03-31'
  AND (s.valid_to IS NULL OR s.valid_to > '2023-03-31');
```

### Pattern 2: Survivorship-Bias-Free Analysis

Include delisted securities in historical analysis.

```sql
-- Get all securities that were in NIFTY500 on Jan 1, 2020
-- Including those that have since been delisted
SELECT 
    s.security_id,
    s.security_name,
    s.delisting_date,
    s.delisting_reason
FROM dim_index_constituents ic
JOIN dim_security s ON ic.security_key = s.security_key
WHERE ic.index_name = 'NIFTY500'
  AND ic.effective_date <= '2020-01-01'
  AND (ic.exit_date IS NULL OR ic.exit_date > '2020-01-01');
```

### Pattern 3: Handling Restatements

Query both original and restated financial values.

```sql
-- Get all versions of Q4 2022 revenue for a security
SELECT 
    reporting_period_end,
    publication_date,
    revenue,
    valid_from,
    valid_to,
    is_current
FROM vault_financials
WHERE security_id = 'INE123A01012'
  AND reporting_period_end = '2022-12-31'
  AND metric_name = 'revenue'
ORDER BY publication_date;
```

### Pattern 4: Corporate Action Adjusted Prices

Query adjusted vs unadjusted prices.

```sql
-- Get both adjusted and unadjusted prices
SELECT 
    price_date,
    security_id,
    close_price as unadjusted_close,
    adjusted_close,
    (adjusted_close / close_price) as adjustment_factor
FROM fact_daily_prices
WHERE security_id = 'RELIANCE'
  AND price_date BETWEEN '2020-01-01' AND '2020-12-31'
ORDER BY price_date;
```

## Deployment Guide

### Prerequisites

- AWS account with appropriate permissions
- Terraform installed (for infrastructure)
- Python 3.9+ (for API service)
- Docker (for containerization)

### Infrastructure Deployment

1. **Deploy Redshift Cluster**
```bash
cd infrastructure/terraform
terraform init
terraform plan
terraform apply
```

2. **Set up S3 Data Lake**
```bash
aws s3 mb s3://itus-data-lake
aws s3api put-bucket-versioning --bucket itus-data-lake --versioning-configuration Status=Enabled
```

3. **Deploy Lambda Validators**
```bash
cd lambda/validators
./deploy.sh
```

4. **Deploy Glue ETL Jobs**
```bash
cd glue
./deploy_jobs.sh
```

### Database Schema Deployment

```bash
cd redshift/schemas
./deploy_schemas.sh
```

### API Service Deployment

```bash
cd api
docker build -t research-platform-api .
docker push <ecr-repo>/research-platform-api:latest

# Deploy to ECS
aws ecs update-service --cluster research-platform --service api-service --force-new-deployment
```

### Monitoring Setup

```bash
cd infrastructure
python cloudwatch_config.py
python alerting_config.py
```

## Troubleshooting

### Common Issues

#### Query Timeout

**Symptom:** Query exceeds timeout limit

**Solutions:**
1. Add date range filters to reduce data scanned
2. Use materialized views instead of base tables
3. Increase timeout for long-running queries
4. Run as scheduled batch job during off-hours

#### Data Quality Failures

**Symptom:** Validation failures during data ingestion

**Solutions:**
1. Check quarantine bucket for failed records
2. Review validation error messages in CloudWatch logs
3. Verify source data format matches expected schema
4. Check for corporate actions that explain price outliers

#### High Costs

**Symptom:** AWS costs exceeding budget

**Solutions:**
1. Review concurrency scaling usage
2. Pause cluster during non-business hours
3. Optimize expensive queries (check query_performance_metrics view)
4. Review S3 storage growth and lifecycle policies

#### Temporal Query Errors

**Symptom:** Validation errors about missing temporal filters

**Solutions:**
1. Add publication_date or as_of_date filters to temporal tables
2. Use UDFs which handle temporal logic automatically
3. Review temporal query patterns in documentation

### Performance Optimization

#### Slow Queries

1. Run EXPLAIN to see query plan
2. Check if sort keys are being used (zone map pruning)
3. Verify distribution keys minimize data movement
4. Consider creating materialized view for common patterns

#### High Queue Wait Times

1. Check WLM queue configuration
2. Enable concurrency scaling for analyst queue
3. Review query priorities
4. Consider scaling cluster during peak hours

### Support

For technical support, contact:
- Email: data-platform-support@example.com
- Slack: #research-platform-support
