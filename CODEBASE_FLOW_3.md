# Research Data Platform V2 - Complete Codebase Flow (Part 3)

## 4. Code Organization

### Project Structure

```
research-data-platform-v2/
├── data-collection/              # Data collection scripts
│   ├── collect_daily_prices.py
│   ├── collect_fii_dii_flows.py
│   ├── collect_macro_data.py
│   └── manual_upload.py
│
├── lambda/                       # Lambda validators
│   └── validators/
│       ├── price_validator.py
│       ├── financial_validator.py
│       ├── data_quality_rules.py
│       └── data_quality_engine.py
│
├── glue/                         # Glue ETL jobs
│   ├── daily_prices_etl.py
│   ├── quarterly_financials_etl.py
│   └── daily_flows_etl.py
│
├── redshift/                     # Redshift SQL scripts
│   └── schemas/
│       ├── 01_create_schemas.sql
│       ├── 02_create_control_tables.sql
│       ├── 03_create_dimension_tables.sql
│       ├── 04_create_vault_tables.sql
│       ├── 05_create_corporate_actions.sql
│       ├── 06_create_staging_tables.sql
│       ├── 07_create_materialized_views.sql
│       └── 08_create_fact_tables.sql
│
├── api/                          # FastAPI query service
│   ├── main.py
│   ├── temporal_validator.py
│   ├── performance_estimator.py
│   ├── Dockerfile
│   └── requirements.txt
│
├── infrastructure/               # Infrastructure code
│   ├── cloudwatch_config.py
│   ├── alerting_config.py
│   └── cost_optimization.py
│
└── docs/                         # Documentation
    ├── ARCHITECTURE_GUIDE.md
    ├── DEPLOYMENT_GUIDE.md
    ├── ADVANCED_CONCEPTS.md
    └── ARCHITECTURE_DECISIONS.md
```

---

## 5. Key Implementation Details

### Lambda Validator Flow

**File:** `lambda/validators/price_validator.py`

```python
def lambda_handler(event, context):
    """
    Entry point for Lambda validator
    Triggered by: S3 upload event
    """
    
    # 1. Extract S3 info from event
    bucket = event['Records'][0]['s3']['bucket']['name']
    key = event['Records'][0]['s3']['object']['key']
    
    # 2. Download file from S3
    s3 = boto3.client('s3')
    obj = s3.get_object(Bucket=bucket, Key=key)
    data = obj['Body'].read().decode('utf-8')
    
    # 3. Parse CSV
    df = pd.read_csv(io.StringIO(data))
    
    # 4. Run validation rules
    engine = DataQualityEngine()
    rules = [
        RequiredColumnsRule(['security_id', 'price_date', 'close']),
        NullCheckRule(['security_id', 'price_date', 'close']),
        PositiveValueRule(['close', 'volume']),
        PriceChangeRule('close', max_change_pct=50.0)
    ]
    
    summary = engine.execute_rules(df, rules)
    
    # 5. Handle results
    if summary['pass_rate'] >= 95:
        # Valid - trigger Glue ETL
        glue.start_job_run(JobName='daily-prices-etl')
        return {'statusCode': 200, 'body': 'Validation passed'}
    else:
        # Invalid - quarantine and alert
        quarantine_file(bucket, key)
        send_alert(summary)
        return {'statusCode': 400, 'body': 'Validation failed'}
```

---

### Glue ETL Flow

**File:** `glue/daily_prices_etl.py`

```python
# Initialize
glueContext = GlueContext(SparkContext.getOrCreate())
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Read from S3 with bookmark (CRITICAL)
datasource = glueContext.create_dynamic_frame.from_options(
    connection_type="s3",
    connection_options={"paths": ["s3://itus-data-lake/raw/prices/"]},
    format="csv",
    transformation_ctx="datasource"  # Enables bookmarks
)

# Transform
transformed = Map.apply(frame=datasource, f=transform_function)

# Write to Redshift staging
glueContext.write_dynamic_frame.from_options(
    frame=transformed,
    connection_type="redshift",
    connection_options={
        "url": "jdbc:redshift://...",
        "dbtable": "staging.stg_prices",
        "preactions": "DELETE FROM staging.stg_prices WHERE price_date = CURRENT_DATE"
    },
    transformation_ctx="datasink"
)

# Commit (updates bookmark)
job.commit()
```

---

### API Query Flow

**File:** `api/main.py`


```python
@app.post("/api/v1/query/execute")
async def execute_sql_query(request: QueryRequest):
    """
    Entry point for query execution
    """
    
    # 1. Temporal validation (CRITICAL)
    if not request.skip_validation:
        validation_result = validate_query(
            request.query, 
            request.as_of_date
        )
        if not validation_result.is_valid:
            raise HTTPException(400, detail=validation_result.errors)
    
    # 2. Performance estimation
    perf_estimate = estimate_query_performance(request.query)
    if perf_estimate.should_reject:
        raise HTTPException(400, detail="Query too expensive")
    
    # 3. Check cache
    cache_key = generate_cache_key(request.query)
    if request.cache_enabled:
        cached = get_cached_result(cache_key)
        if cached:
            return cached
    
    # 4. Execute on Redshift
    results = execute_query(request.query, timeout=request.timeout_seconds)
    
    # 5. Cache results
    if request.cache_enabled:
        set_cached_result(cache_key, results)
    
    # 6. Return
    return {
        "data": results,
        "row_count": len(results),
        "cached": False
    }
```

---

## Summary

**Complete Data Flow:**
```
Data Collection → S3 → Lambda Validator → Glue ETL → 
Redshift (Bronze → Silver → Gold) → API → Analysts
```

**Critical Strategies Implemented:**
1. ✅ Bi-temporal data model (point-in-time correctness)
2. ✅ Job bookmarks (incremental processing)
3. ✅ Idempotent design (safe retries)
4. ✅ Corporate action adjustments (accurate returns)
5. ✅ Temporal validation (prevent look-ahead bias)
6. ✅ Performance optimization (sub-5-second queries)

**Key Files:**
- Entry: `data-collection/collect_daily_prices.py`
- Validation: `lambda/validators/price_validator.py`
- ETL: `glue/daily_prices_etl.py`
- Schema: `redshift/schemas/*.sql`
- API: `api/main.py`
- Exit: Analyst tools (Python, Excel, Tableau)

---

**Navigation:**
- [Part 1: Entry Points & Data Flow](CODEBASE_FLOW_1.md)
- [Part 2: Critical Data Strategies](CODEBASE_FLOW_2.md)
- Part 3: Code Organization & Implementation (Current)
