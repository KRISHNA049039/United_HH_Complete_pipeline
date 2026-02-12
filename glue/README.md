# Glue ETL Jobs

This directory contains AWS Glue ETL jobs for loading data from S3 to Redshift staging tables.

## ETL Jobs

### 1. Daily Prices ETL (`daily_prices_etl.py`)

Loads daily OHLCV price data from S3 to Redshift.

**Features:**
- Incremental loading using high-water marks
- Data quality validation (nulls, negative prices, price logic)
- Automatic file movement to processed folder
- High-water mark tracking in control table

**Staging Table:** `staging.stg_daily_prices`

### 2. Quarterly Financials ETL (`quarterly_financials_etl.py`)

Loads quarterly financial statements with temporal versioning.

**Features:**
- Hash-based change detection for restatements
- Temporal consistency validation
- Balance sheet equation validation
- Support for financial restatements

**Staging Table:** `staging.stg_quarterly_financials`

### 3. Daily Flows ETL (`daily_flows_etl.py`)

Loads FII/DII institutional flow data.

**Features:**
- Net flow calculation (buy - sell)
- Date validation
- Automatic aggregation

**Staging Table:** `staging.stg_institutional_flows`

### 4. Corporate Actions ETL (`corporate_actions_etl.py`)

Loads corporate action events (splits, dividends, mergers).

**Features:**
- Multiple action types support
- Adjustment factor storage
- Date validation

**Staging Table:** `staging.stg_corporate_actions`

### 5. Index Constituents ETL (`index_constituents_etl.py`)

Loads index membership changes.

**Features:**
- Temporal tracking (effective_date, exit_date)
- Current status flag
- Multiple index support

**Staging Table:** `staging.stg_index_constituents`

## Deployment

### Prerequisites

1. Infrastructure deployed (Task 1)
2. Redshift cluster running
3. IAM roles configured
4. S3 bucket created

### Deploy All Jobs

```bash
cd glue
chmod +x deploy_jobs.sh
./deploy_jobs.sh
```

This will:
1. Upload job scripts to S3
2. Create all 5 Glue jobs
3. Configure job parameters
4. Set up CloudWatch logging

### Deploy Individual Job

```bash
aws glue create-job \
    --name research-platform-daily-prices-etl \
    --role <GLUE_ROLE_ARN> \
    --command "Name=glueetl,ScriptLocation=s3://<bucket>/glue-scripts/daily_prices_etl.py" \
    --default-arguments '{"--S3_BUCKET":"<bucket>","--REDSHIFT_CONNECTION":"<connection>"}' \
    --glue-version "4.0"
```

## Job Configuration

All jobs use:
- **Glue Version:** 4.0
- **Worker Type:** G.1X (4 vCPU, 16 GB memory)
- **Number of Workers:** 2
- **Max Retries:** 3
- **Timeout:** 60 minutes
- **Python Version:** 3

## Running Jobs

### Manual Execution

```bash
# Run daily prices ETL
aws glue start-job-run \
    --job-name research-platform-daily-prices-etl \
    --arguments '{"--S3_KEY":"raw/prices/2024/01/15/prices.csv"}'

# Check job status
aws glue get-job-run \
    --job-name research-platform-daily-prices-etl \
    --run-id <run-id>
```

### Triggered by Lambda

Jobs are automatically triggered by Lambda validators when files pass validation:

1. File uploaded to S3 (`raw/prices/*.csv`)
2. Lambda validator validates file
3. If valid, Lambda triggers Glue job
4. Glue job loads data to Redshift
5. File moved to `processed/`

## Incremental Loading

### High-Water Mark Pattern

The daily prices ETL uses high-water marks for incremental loading:

```sql
-- Control table
CREATE TABLE control.etl_high_water_marks (
    table_name VARCHAR(200) PRIMARY KEY,
    high_water_mark DATE,
    last_updated TIMESTAMP,
    job_name VARCHAR(200)
);
```

**How it works:**
1. Job reads high-water mark from control table
2. Filters data to only new records (date > high_water_mark)
3. Loads new records to staging
4. Updates high-water mark to max date in batch

### Full Reload

To force a full reload, delete the high-water mark:

```sql
DELETE FROM control.etl_high_water_marks 
WHERE table_name = 'staging.stg_daily_prices';
```

## Data Quality Checks

Each ETL job performs validation:

### Price Data
- No null values in critical columns
- All prices > 0
- high >= low
- close within [low, high]

### Financial Data
- No null security_id, dates
- publication_date >= reporting_period_end
- Balance sheet equation (1% tolerance)
- Reasonable value ranges

### Failures

If validation fails:
- Job fails with error message
- CloudWatch logs contain details
- SNS alert sent (if configured)
- Data not loaded to staging

## Monitoring

### CloudWatch Logs

```bash
# View logs
aws logs tail /aws-glue/jobs/output --follow

# Filter by job
aws logs filter-log-events \
    --log-group-name /aws-glue/jobs/output \
    --filter-pattern "research-platform-daily-prices-etl"
```

### CloudWatch Metrics

- **JobRunTime:** Duration of job execution
- **JobSucceeded:** Number of successful runs
- **JobFailed:** Number of failed runs
- **RecordsProcessed:** Custom metric (if implemented)

### Job History

```bash
# List recent runs
aws glue get-job-runs \
    --job-name research-platform-daily-prices-etl \
    --max-results 10
```

## Troubleshooting

### Job Fails with "Connection Refused"

**Cause:** Glue cannot connect to Redshift

**Solution:**
1. Check Redshift security group allows Glue
2. Verify Redshift is in same VPC as Glue
3. Check Redshift endpoint is correct

### Job Fails with "Access Denied" to S3

**Cause:** Glue role lacks S3 permissions

**Solution:**
1. Check IAM role has S3 read/write permissions
2. Verify bucket policy allows Glue role
3. Check S3 bucket encryption settings

### High-Water Mark Not Updating

**Cause:** Control table doesn't exist or permissions issue

**Solution:**
1. Create control schema and table in Redshift
2. Grant Glue role permissions to control schema
3. Check job logs for specific error

### Job Times Out

**Cause:** Large file or slow Redshift

**Solution:**
1. Increase job timeout (default 60 min)
2. Increase number of workers
3. Optimize Redshift (VACUUM, ANALYZE)
4. Split large files into smaller batches

## Cost Optimization

### DPU Usage

- G.1X worker = 1 DPU = $0.44/hour
- 2 workers = 2 DPU = $0.88/hour
- Typical job: 5-10 minutes = ~$0.10-0.15

### Recommendations

1. **Right-size workers:** Start with 2, increase if needed
2. **Batch files:** Process multiple files in one job run
3. **Schedule wisely:** Run during off-peak hours
4. **Monitor duration:** Optimize slow jobs
5. **Use incremental loading:** Reduces data processed

### Monthly Cost Estimate

Assuming:
- Daily prices: 1 run/day × 5 min = $0.07/day = $2.10/month
- Quarterly financials: 4 runs/month × 10 min = $0.60/month
- Daily flows: 1 run/day × 3 min = $0.04/day = $1.20/month
- Corporate actions: 2 runs/month × 5 min = $0.15/month
- Index constituents: 2 runs/month × 5 min = $0.15/month

**Total:** ~$4-5/month

## Next Steps

After Glue jobs are deployed:
1. Create Redshift database schemas (Task 3)
2. Test end-to-end data flow
3. Set up scheduled job runs (if needed)
4. Implement monitoring dashboard
5. Create runbook for job failures
