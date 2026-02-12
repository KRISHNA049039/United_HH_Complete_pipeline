# Complete AWS Architecture Diagram - Draw.io Guide

## How to Create the Detailed Diagram

### Step 1: Open Draw.io and Enable AWS Icons
1. Go to https://app.diagrams.net
2. Click "More Shapes" (bottom left)
3. Search for "AWS19" or "AWS Architecture 2019"
4. Enable the AWS icon library
5. Set canvas size: 2000 x 1600 pixels

### Step 2: Layout Structure (Top to Bottom)

```
┌─────────────────────────────────────────────────────────────────┐
│  Title: Research Data Platform V2 - Complete Architecture      │
└─────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────┐
│  Layer 1: External Data Sources (Height: 140px)                │
└─────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────┐
│  Layer 2: Ingestion Layer - S3, Lambda, Glue (Height: 380px)   │
└─────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────┐
│  Layer 3: Redshift Data Warehouse (Height: 520px)              │
│    - Staging Zone (Bronze)                                      │
│    - Integration Zone (Silver)                                  │
│    - Presentation Zone (Gold)                                   │
└─────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────┐
│  Layer 4: Query & Consumption Layer (Height: 280px)            │
└─────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────┐
│  Layer 5: Monitoring & Governance (Right Side: 720px height)   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Detailed Component Specifications

### LAYER 1: EXTERNAL DATA SOURCES

**Container**: AWS Region shape (dashed border, light blue fill)
- Title: "External Data Sources"
- Color: #E6F6F7, Border: #00A4A6

**Components** (4 boxes, side by side):

#### 1. Market Data Provider
- **Icon**: AWS Generic Database (green)
- **Box**: White background, green border
- **Text**:
  ```
  Market Data Provider
  • Daily OHLCV data
  • 3000+ securities
  • 20 years historical
  • NSE/BSE exchanges
  ```

#### 2. Financial Statements
- **Icon**: AWS Generic Database (green)
- **Box**: White background, green border
- **Text**:
  ```
  Financial Statements
  • Quarterly reports
  • Income, Balance Sheet, Cash Flow
  • Restatements tracked
  • Publication dates preserved
  ```

#### 3. FII/DII Flows
- **Icon**: AWS Generic Database (green)
- **Box**: White background, green border
- **Text**:
  ```
  FII/DII Institutional Flows
  • Daily buy/sell values
  • Net flow calculations
  • Institutional tracking
  ```

#### 4. Corporate Actions
- **Icon**: AWS Generic Database (green)
- **Box**: White background, green border
- **Text**:
  ```
  Corporate Actions
  • Splits, dividends, bonuses
  • Mergers, rights issues
  • Adjustment factors
  • Ex-dates tracked
  ```

---

### LAYER 2: INGESTION LAYER

**Container**: AWS VPC shape (green border)
- Title: "Ingestion Layer - VPC"
- Color: #E9F3E6, Border: #248814

#### Section A: S3 Data Lake (Top, full width)

**Main Container**: Orange background (#7AA116)
- Title: "S3 Data Lake"

**Sub-components** (3 buckets, horizontal):

1. **Raw Zone**
   - Icon: S3 Bucket (large, orange)
   - Text:
     ```
     Raw Zone
     Paths: raw/prices/ | raw/financials/ | raw/flows/ | raw/corporate_actions/
     Features:
     • S3 Event notifications enabled
     • Versioning ON
     • Lifecycle: Archive to Glacier after 90 days
     • Retention: Indefinite
     ```

2. **Processed Zone**
   - Icon: S3 Bucket (medium, orange)
   - Text:
     ```
     Processed Zone
     Path: processed/validated/
     • Validated data ready for ETL
     • Retention: 180 days
     • Auto-delete after processing
     ```

3. **Quarantine Zone**
   - Icon: S3 Bucket with objects (red)
   - Text:
     ```
     Quarantine Zone
     Path: quarantine/failed_validation/
     • Failed validation records
     • Manual review required
     • SNS alerts triggered
     • Retention: 30 days
     ```

#### Section B: Lambda Validators (Middle, left side)

**Container**: Orange background (#ED7100)
- Title: "Lambda Validators (Event-Driven)"

**Components** (4 Lambda functions, horizontal):

1. **Price Validator**
   - Icon: AWS Lambda Function
   - Text:
     ```
     Price Validator
     Validations:
     • Schema compliance
     • Null checks (required fields)
     • Price range validation (>0)
     • Outlier detection (±50% change)
     • Duplicate detection
     • Statistical checks
     
     Config:
     • Memory: 512 MB
     • Timeout: 5 minutes
     • Trigger: S3 Event (raw/prices/)
     ```

2. **Financial Validator**
   - Icon: AWS Lambda Function
   - Text:
     ```
     Financial Validator
     Validations:
     • Required fields present
     • Balance sheet balancing
     • Referential integrity
     • Metric range checks
     • Restatement detection
     • Cross-field validation
     
     Config:
     • Memory: 512 MB
     • Timeout: 5 minutes
     • Trigger: S3 Event (raw/financials/)
     ```

3. **Flow Validator**
   - Icon: AWS Lambda Function
   - Text:
     ```
     Flow Validator
     Validations:
     • FII/DII data checks
     • Value reconciliation
     • Date validation
     • Sum checks (buy + sell)
     • Completeness checks
     
     Config:
     • Memory: 512 MB
     • Timeout: 5 minutes
     • Trigger: S3 Event (raw/flows/)
     ```

4. **Data Quality Engine**
   - Icon: AWS Lambda Function
   - Text:
     ```
     Data Quality Engine
     Features:
     • 20+ validation rules
     • Quarantine failed data
     • SNS alert integration
     • Log to Redshift control tables
     • Metrics to CloudWatch
     
     Target: >99% pass rate
     ```

#### Section C: SQS Dead Letter Queue (Middle, right of Lambda)

- **Icon**: AWS SQS Queue (pink/magenta)
- **Text**:
  ```
  SQS Dead Letter Queue
  Purpose: Failed validation handling
  
  Features:
  • Retry logic (3 attempts)
  • Exponential backoff
  • Manual review queue
  • Retention: 14 days
  • SNS alerts on arrival
  ```

#### Section D: AWS Glue ETL Jobs (Bottom)

**Container**: Purple background (#8C4FFF)
- Title: "AWS Glue ETL (Incremental Processing)"

**Components** (3 Glue jobs, horizontal):

1. **Daily Prices ETL**
   - Icon: AWS Glue
   - Text:
     ```
     Daily Prices ETL
     Features:
     • Job bookmarks ENABLED
     • Incremental load only
     • Corporate action adjustments
     • Idempotent processing
     
     Performance:
     • 20M rows in 15 minutes
     • Throughput: 22K rows/sec
     
     Schedule: Daily 2:00 AM IST
     Retry: 3 attempts
     ```

2. **Quarterly Financials ETL**
   - Icon: AWS Glue
   - Text:
     ```
     Quarterly Financials ETL
     Features:
     • Bi-temporal data load
     • Restatement handling
     • Vault pattern implementation
     • Point-in-time preservation
     
     Performance:
     • 240K rows in 25 minutes
     • Handles multiple versions
     
     Schedule: Quarterly + Ad-hoc
     Retry: 3 attempts
     ```

3. **Flows ETL**
   - Icon: AWS Glue
   - Text:
     ```
     Flows ETL
     Features:
     • FII/DII aggregation
     • Net flow calculations
     • Idempotent processing
     • Incremental load
     
     Performance:
     • 15M rows in 20 minutes
     • Throughput: 12.5K rows/sec
     
     Schedule: Daily 3:00 AM IST
     Retry: 3 attempts
     ```

---

### LAYER 3: REDSHIFT DATA WAREHOUSE

**Container**: AWS VPC shape (blue border)
- Title: "Amazon Redshift - Data Warehouse (Medallion Architecture)"
- Color: #E6F2FF, Border: #3334B9

#### Cluster Information Box (Top Left)

- **Icon**: AWS Redshift (large, blue)
- **Text**:
  ```
  Redshift Cluster Configuration
  
  Hardware:
  • Node Type: RA3.4xlarge
  • Nodes: 2-4 (auto-scaling)
  • vCPU: 12 per node (24-48 total)
  • RAM: 96 GB per node (192-384 GB total)
  • Storage: Managed (RA3)
  
  Features:
  • Auto-scaling: Peak hours (8 AM - 6 PM IST)
  • Concurrency scaling: Up to 10 clusters
  • WLM Queues: ETL (40%), Analyst (50%), Admin (10%)
  • Pause schedule: Nights & weekends
  
  Cost: $3,000-4,500/month
  ```

#### Zone 1: STAGING (Bronze)

**Container**: Light blue background (#dae8fc)
- Title: "STAGING ZONE (Bronze)"
- Height: 120px

**Text**:
```
Purpose: Raw data landing area
Characteristics:
• Minimal transformation
• EVEN distribution for parallel loading
• No indexes or constraints
• 7-day retention
• Truncate before load (idempotent)

Tables:
• stg_prices
• stg_financials
• stg_flows
• stg_corporate_actions
• stg_index_constituents

Performance:
• Load speed: 100K rows/second
• Parallel loading across all nodes
```

#### Zone 2: INTEGRATION (Silver)

**Container**: Light green background (#d5e8d4)
- Title: "INTEGRATION ZONE (Silver)"
- Height: 150px

**Sub-sections** (4 boxes, horizontal):

1. **Vault Tables (Bi-temporal)**
   - Text:
     ```
     Vault Tables
     Purpose: Immutable historical storage
     
     Tables:
     • vault_financials
       - valid_from, valid_to
       - publication_date
       - Append-only, never update
     • vault_prices
       - Unadjusted price history
     
     Features:
     • Hash diff for change detection
     • Complete audit trail
     • Restatement tracking
     ```

2. **Corporate Actions Engine**
   - Text:
     ```
     Corporate Actions
     Purpose: Price adjustment calculations
     
     Tables:
     • corporate_actions
       - Splits, dividends, mergers
       - Ex-dates, adjustment factors
     • price_adjustments
       - Cumulative adjustment factors
       - Both adjusted & unadjusted
     
     Logic:
     • Cascading adjustments
     • Factor multiplication
     ```

3. **Type 2 SCDs**
   - Text:
     ```
     Slowly Changing Dimensions
     Purpose: Track attribute changes
     
     Tables:
     • dim_security
       - Track sector changes
       - Listing/delisting dates
     • dim_index_constituents
       - Membership history
       - effective_date, exit_date
     
     Features:
     • Surrogate keys (IDENTITY)
     • valid_from, valid_to
     • is_current flag
     ```

4. **Control & Audit**
   - Text:
     ```
     Control Tables
     Purpose: ETL tracking & audit
     
     Tables:
     • etl_job_metrics
       - Job execution tracking
       - Duration, row counts
     • data_quality_results
       - Validation results
       - Pass rates, failures
     • query_audit_log
       - All query history
       - User, timestamp, duration
     
     Features:
     • High-water marks
     • Incremental tracking
     ```

#### Zone 3: PRESENTATION (Gold)

**Container**: Light yellow background (#fff2cc)
- Title: "PRESENTATION ZONE (Gold) - Star Schema"
- Height: 150px

**Sub-sections** (3 boxes, horizontal):

1. **Fact Tables**
   - Text:
     ```
     Fact Tables
     Distribution: DISTKEY(security_key)
     
     • fact_daily_prices
       - 20M rows
       - SORTKEY: (price_date, security_key)
       - Compression: 3.2x
       - Query time: <3 seconds
     
     • fact_quarterly_financials
       - 240K rows
       - Point-in-time columns
       - 50+ financial metrics
       - Query time: <2 seconds
     
     • fact_institutional_flows
       - 15M rows
       - FII/DII buy/sell data
       - Net flow calculations
     ```

2. **Dimension Tables**
   - Text:
     ```
     Dimension Tables
     Distribution: DISTSTYLE ALL (replicated)
     
     • dim_security
       - 5K securities
       - Type 2 SCD
       - Sector, industry, market cap
     
     • dim_date
       - 10K dates (30 years)
       - Fiscal calendar
       - Trading day flags
     
     • dim_index_constituents
       - 50K records
       - Temporal membership
       - Survivorship-bias-free
     
     Features:
     • Replicated to all nodes
     • Fast joins (no shuffle)
     ```

3. **Materialized Views**
   - Text:
     ```
     Materialized Views
     Purpose: Precomputed aggregations
     
     • mv_precomputed_ratios
       - 20+ financial ratios
       - EBITDA margin, ROE, ROA
       - 5-10x faster queries
     
     • mv_rolling_returns
       - 1M, 3M, 6M, 1Y, 3Y returns
       - Momentum indicators
       - Percentile rankings
     
     • mv_current_index_constituents
       - Current snapshot
       - Daily refresh
     
     Refresh: Daily 7:00 AM IST
     Storage: +300 GB
     Benefit: 5-10x query speedup
     ```

---

### LAYER 4: QUERY & CONSUMPTION LAYER

#### Section A: Query Layer (Left side)

**Container**: Orange background (#ED7100)
- Title: "Query Layer"

**Components** (2 boxes, horizontal):

1. **FastAPI Service (ECS Fargate)**
   - Icon: AWS ECS Service
   - Text:
     ```
     FastAPI Query Service
     Deployment: ECS Fargate
     
     Features:
     • Temporal validation (prevent look-ahead bias)
     • Performance estimation (cost control)
     • Natural language query engine
     • Query result caching
     • Audit logging
     
     Endpoints:
     • POST /api/v1/query/execute
     • POST /api/v1/query/validate
     • POST /api/v1/query/estimate
     • POST /api/v1/nl/translate
     
     Config:
     • Containers: 2-4 (auto-scaling)
     • CPU: 2 vCPU per container
     • Memory: 4 GB per container
     • Cost: $200/month
     ```

2. **ElastiCache Redis**
   - Icon: AWS ElastiCache for Redis
   - Text:
     ```
     Redis Cache
     Purpose: Query result caching
     
     Configuration:
     • Node: cache.t3.medium
     • Memory: 3.09 GB
     • TTL: 24 hours
     
     Performance:
     • Cache hit rate: 40-50%
     • Latency: <5ms
     • 100x speedup for cached queries
     
     Invalidation:
     • Time-based (24h TTL)
     • Manual via API
     
     Cost: $50/month
     ```

#### Section B: Consumption Layer (Bottom)

**Container**: Light gray background
- Title: "Consumption Layer"

**Components** (5 icons, horizontal):

1. **Python/Jupyter**
   - Icon: Generic SAML token
   - Text: "Jupyter Notebooks\nPython Scripts\nPandas/NumPy"

2. **Excel**
   - Icon: Generic SAML token
   - Text: "Excel Add-in\nDirect SQL\nPivot Tables"

3. **Tableau**
   - Icon: Generic SAML token
   - Text: "Tableau Desktop\nDashboards\nVisualizations"

4. **PowerBI**
   - Icon: Generic SAML token
   - Text: "PowerBI Desktop\nReports\nAnalytics"

5. **Custom Apps**
   - Icon: Generic SAML token
   - Text: "Custom Applications\nAPI Integration\nAutomated Reports"

---

### LAYER 5: MONITORING & GOVERNANCE (Right Side Panel)

**Container**: Green background (#759C3E)
- Title: "Monitoring & Governance"
- Position: Right side, spans multiple layers

**Components** (vertical stack):

1. **CloudWatch**
   - Icon: AWS CloudWatch
   - Text:
     ```
     CloudWatch Monitoring
     
     Log Groups:
     • /aws/lambda/validators
     • /aws/glue/etl-jobs
     • /ecs/api-service
     
     Custom Metrics:
     • QueryExecutionTime
     • DataQualityPassRate
     • ETLJobDuration
     • CacheHitRate
     
     Retention: 30 days
     ```

2. **SNS**
   - Icon: AWS SNS
   - Text:
     ```
     SNS Alerting
     
     Topics:
     • critical-alerts
     • data-quality-alerts
     • etl-job-alerts
     • performance-alerts
     
     Subscribers:
     • Operations team email
     • Slack integration
     • PagerDuty (critical)
     ```

3. **EventBridge**
   - Icon: AWS EventBridge
   - Text:
     ```
     EventBridge Orchestration
     
     Rules:
     • S3 upload → Lambda trigger
     • Lambda success → Glue trigger
     • ETL completion → MV refresh
     • Daily schedule → Auto-scaling
     
     Features:
     • Event-driven architecture
     • Retry logic
     • Dead letter queues
     ```

4. **Cost Monitoring**
   - Icon: AWS Cost Explorer
   - Text:
     ```
     Cost Monitoring
     
     Tracking:
     • Redshift: $3,000-4,500/month
     • S3: $50/month
     • Lambda: $200/month
     • ECS: $200/month
     • Total: $3,500-5,000/month
     
     Alerts:
     • 80% budget threshold
     • Anomaly detection
     • Daily cost reports
     ```

---

## ARROWS AND DATA FLOW

### Arrow Specifications:

1. **Data Sources → S3**
   - Style: Solid, thick (3px)
   - Color: #545B64 (gray)
   - Label: "Upload"

2. **S3 → Lambda**
   - Style: Solid, thick (3px)
   - Color: #545B64
   - Label: "S3 Event Trigger"

3. **Lambda → SQS DLQ**
   - Style: Dashed, thick (3px)
   - Color: #D13212 (red)
   - Label: "Failed"

4. **Lambda → Glue**
   - Style: Solid, thick (3px)
   - Color: #1B660F (green)
   - Label: "Valid"

5. **Glue → Redshift Staging**
   - Style: Solid, thick (3px)
   - Color: #545B64
   - Label: "Load"

6. **Staging → Integration**
   - Style: Solid, thick (3px)
   - Color: #545B64
   - Label: "Transform"

7. **Integration → Presentation**
   - Style: Solid, thick (3px)
   - Color: #545B64
   - Label: "Aggregate"

8. **Presentation → API**
   - Style: Solid, thick (3px)
   - Color: #545B64
   - Label: "Query"

9. **API → Redis**
   - Style: Dashed, medium (2px)
   - Color: #C925D1 (purple)
   - Label: "Cache"

10. **API → Consumption**
    - Style: Solid, thick (3px)
    - Color: #545B64
    - Label: "Consume"

11. **All Components → Monitoring**
    - Style: Dashed, thin (1px)
    - Color: #759C3E (green)
    - Label: "Metrics/Logs"

---

## LEGEND BOX (Bottom Right)

**Container**: Light gray background
- Title: "Legend"

**Content**:
```
Data Flow:
━━━━━ Solid Arrow = Primary data flow
- - - - Dashed Arrow = Error/cache path

Architecture Pattern:
Bronze (Staging) → Silver (Integration) → Gold (Presentation)

Performance Targets:
• Query latency: <5 seconds (95th percentile)
• Data quality: >99% pass rate
• ETL duration: <30 minutes
• Cache hit rate: >40%
• Uptime: >99.5%

Cost Breakdown:
• Redshift: 70% ($3,000-4,500)
• Compute: 15% ($650)
• Storage: 10% ($450)
• Other: 5% ($250)
Total: $3,500-5,000/month
```

---

## COLOR PALETTE

### AWS Official Colors:
- **S3**: #7AA116 (green)
- **Lambda**: #ED7100 (orange)
- **Glue**: #8C4FFF (purple)
- **Redshift**: #3334B9 (blue)
- **ECS**: #ED7100 (orange)
- **ElastiCache**: #C925D1 (magenta)
- **SQS/SNS**: #E7157B (pink)
- **CloudWatch**: #759C3E (olive green)
- **EventBridge**: #E7157B (pink)

### Zone Colors:
- **Bronze (Staging)**: #dae8fc (light blue)
- **Silver (Integration)**: #d5e8d4 (light green)
- **Gold (Presentation)**: #fff2cc (light yellow)

### Status Colors:
- **Success**: #1B660F (green)
- **Error**: #D13212 (red)
- **Warning**: #FF9900 (orange)
- **Info**: #545B64 (gray)

---

## TIPS FOR AESTHETIC DESIGN

1. **Consistent Spacing**: 20px between components, 40px between sections
2. **Font Sizes**: Title (14pt bold), Subtitles (12pt bold), Body (9-10pt)
3. **Icon Sizes**: Large (60x60), Medium (48x48), Small (38x38)
4. **Border Widths**: Containers (2-3px), Components (1-2px)
5. **Shadows**: Add subtle shadows to containers for depth
6. **Alignment**: Use Draw.io's alignment tools for perfect positioning
7. **Groups**: Group related components for easy moving
8. **Layers**: Use layers for complex diagrams (Background, Components, Arrows, Labels)

---

This guide provides complete specifications for creating a professional, detailed AWS architecture diagram in Draw.io!
