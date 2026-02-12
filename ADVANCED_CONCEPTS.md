# Research Data Platform V2 - Advanced Concepts

## Table of Contents

1. [Glue Job Bookmarks](#glue-job-bookmarks)
2. [Idempotent Pipeline Design](#idempotent-pipeline-design)
3. [Metrics Monitoring Across Pipeline Stages](#metrics-monitoring-across-pipeline-stages)
4. [Advanced ETL Patterns](#advanced-etl-patterns)
5. [Performance Tuning](#performance-tuning)

## Glue Job Bookmarks

### What are Glue Job Bookmarks?

Glue Job Bookmarks track data that has already been processed during a previous run of an ETL job. This enables incremental data processing, where only new or changed data is processed in subsequent runs.

### How Bookmarks Work

1. **State Tracking**: Glue maintains state information about processed data
2. **Incremental Processing**: Only new data since last bookmark is processed
3. **Automatic Management**: Glue handles bookmark creation and updates
4. **Per-Job Storage**: Each job has its own bookmark state

### Bookmark Storage

Bookmarks store:
- **S3 Files**: Last modified timestamp and file path
- **JDBC Sources**: Primary key values or timestamp columns
- **DynamoDB**: Item keys processed

### Enabling Bookmarks

#### In Glue Job Definition

```python
# When creating Glue job via AWS CLI
aws glue create-job \
  --name daily-prices-etl \
  --role GlueServiceRole \
  --command Name=glueetl,ScriptLocation=s3://bucket/script.py \
  --default-arguments '{
    "--job-bookmark-option": "job-bookmark-enable"
  }'
```

#### In Glue Script

```python
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
import sys

# Get job parameters
args = getResolvedOptions(sys.argv, ['JOB_NAME'])

# Initialize Glue context
glueContext = GlueContext(SparkContext.getOrCreate())
job = Job(glueContext)

# Initialize job with bookmark support
job.init(args['JOB_NAME'], args)

# Read data with bookmark
datasource = glueContext.create_dynamic_frame.from_catalog(
    database="research_platform",
    table_name="raw_prices",
    transformation_ctx="datasource"  # Required for bookmarks
)

# Process data
# ... your transformations ...

# Write data
glueContext.write_dynamic_frame.from_options(
    frame=processed_data,
    connection_type="redshift",
    connection_options={
        "url": "jdbc:redshift://...",
        "dbtable": "staging.stg_prices",
        "user": "admin",
        "password": "password"
    },
    transformation_ctx="datasink"  # Required for bookmarks
)

# Commit job (updates bookmark)
job.commit()
```

### Bookmark Example: Daily Prices ETL

```python
"""
Daily Prices ETL with Job Bookmarks
Processes only new price files since last run
"""

import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from datetime import datetime

# Get job parameters
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'S3_BUCKET', 'REDSHIFT_CONNECTION'])

# Initialize
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Read from S3 with bookmark
# Bookmark tracks: s3://bucket/raw/prices/YYYY/MM/DD/*.csv
datasource = glueContext.create_dynamic_frame.from_options(
    connection_type="s3",
    connection_options={
        "paths": [f"s3://{args['S3_BUCKET']}/raw/prices/"],
        "recurse": True
    },
    format="csv",
    format_options={
        "withHeader": True,
        "separator": ","
    },
    transformation_ctx="datasource"  # CRITICAL: Enables bookmark tracking
)

print(f"Processing {datasource.count()} new records")

# Transform data
def transform_price_data(rec):
    """Transform price record"""
    return {
        'security_id': rec['symbol'],
        'price_date': rec['date'],
        'open_price': float(rec['open']),
        'high_price': float(rec['high']),
        'low_price': float(rec['low']),
        'close_price': float(rec['close']),
        'volume': int(rec['volume']),
        'load_timestamp': datetime.now().isoformat()
    }

transformed = Map.apply(
    frame=datasource,
    f=transform_price_data,
    transformation_ctx="transformed"
)

# Write to Redshift staging
glueContext.write_dynamic_frame.from_options(
    frame=transformed,
    connection_type="redshift",
    connection_options={
        "url": f"jdbc:redshift://{args['REDSHIFT_CONNECTION']}",
        "dbtable": "staging.stg_prices",
        "user": "etl_user",
        "password": "password",
        "preactions": "TRUNCATE TABLE staging.stg_prices"  # Clear staging
    },
    transformation_ctx="datasink"  # CRITICAL: Enables bookmark tracking
)

# Commit job - this updates the bookmark
job.commit()

print("Job completed successfully")
```

### Bookmark Management

#### Check Bookmark Status

```python
import boto3

glue = boto3.client('glue')

# Get job bookmark
response = glue.get_job_bookmark(
    JobName='daily-prices-etl'
)

print(f"Run: {response['JobBookmarkEntry']['Run']}")
print(f"Version: {response['JobBookmarkEntry']['Version']}")
print(f"Attempt: {response['JobBookmarkEntry']['Attempt']}")
```

#### Reset Bookmark

```bash
# Reset bookmark to reprocess all data
aws glue reset-job-bookmark --job-name daily-prices-etl

# Or via Python
glue.reset_job_bookmark(JobName='daily-prices-etl')
```

#### Pause Bookmark

```bash
# Run job without updating bookmark
aws glue start-job-run \
  --job-name daily-prices-etl \
  --arguments '{"--job-bookmark-option":"job-bookmark-pause"}'
```

### Bookmark Best Practices

1. **Always Use transformation_ctx**: Required for bookmark tracking
2. **Commit at End**: Call `job.commit()` to update bookmark
3. **Handle Failures**: Bookmark only updates on successful commit
4. **Test Incremental**: Verify only new data is processed
5. **Monitor State**: Check bookmark status regularly
6. **Reset When Needed**: Reset for full reprocessing

### Bookmark Limitations

- **S3 Only**: Works best with S3 sources
- **File-Based**: Tracks files, not individual records
- **No Deletes**: Doesn't track deleted files
- **State Size**: Large state can impact performance

## Idempotent Pipeline Design

### What is Idempotency?

An idempotent operation produces the same result regardless of how many times it's executed. For data pipelines, this means:

**Running the pipeline multiple times with the same input produces the same output**

### Why Idempotency Matters

1. **Retry Safety**: Can safely retry failed jobs
2. **Debugging**: Can rerun for troubleshooting
3. **Data Quality**: Prevents duplicate records
4. **Consistency**: Ensures data integrity

### Idempotent Design Patterns

#### Pattern 1: Truncate and Load (Staging)

```sql
-- Staging tables: Always truncate before load
BEGIN TRANSACTION;

-- Clear staging table
TRUNCATE TABLE staging.stg_prices;

-- Load new data
COPY staging.stg_prices
FROM 's3://bucket/raw/prices/2024/01/01/'
IAM_ROLE 'arn:aws:iam::123456789012:role/RedshiftRole'
CSV
IGNOREHEADER 1;

COMMIT;
```

**Idempotency**: Multiple runs produce same result (staging always has latest data)

#### Pattern 2: Merge/Upsert (Integration)

```sql
-- Integration tables: Merge based on business key
BEGIN TRANSACTION;

-- Create temp table with new data
CREATE TEMP TABLE temp_prices AS
SELECT * FROM staging.stg_prices;

-- Delete existing records for same date range
DELETE FROM integration.prices
WHERE price_date IN (
    SELECT DISTINCT price_date FROM temp_prices
);

-- Insert new records
INSERT INTO integration.prices
SELECT * FROM temp_prices;

COMMIT;
```

**Idempotency**: Rerunning with same data replaces existing records

#### Pattern 3: Insert with Deduplication

```sql
-- Presentation tables: Insert only if not exists
BEGIN TRANSACTION;

-- Insert new records, skip duplicates
INSERT INTO fact_daily_prices (
    price_date,
    security_key,
    close_price,
    volume
)
SELECT 
    s.price_date,
    d.security_key,
    s.close_price,
    s.volume
FROM staging.stg_prices s
JOIN dim_security d ON s.security_id = d.security_id
WHERE NOT EXISTS (
    SELECT 1 FROM fact_daily_prices f
    WHERE f.price_date = s.price_date
      AND f.security_key = d.security_key
);

COMMIT;
```

**Idempotency**: Duplicate records are skipped

#### Pattern 4: Temporal Versioning (Vault)

```sql
-- Vault tables: Append-only with versioning
BEGIN TRANSACTION;

-- Close out old versions
UPDATE vault_financials
SET valid_to = CURRENT_TIMESTAMP,
    is_current = FALSE
WHERE security_id IN (
    SELECT DISTINCT security_id FROM staging.stg_financials
)
AND reporting_period_end IN (
    SELECT DISTINCT reporting_period_end FROM staging.stg_financials
)
AND is_current = TRUE;

-- Insert new versions
INSERT INTO vault_financials (
    security_id,
    reporting_period_end,
    metric_name,
    metric_value,
    publication_date,
    valid_from,
    valid_to,
    is_current,
    hash_diff
)
SELECT 
    security_id,
    reporting_period_end,
    metric_name,
    metric_value,
    publication_date,
    CURRENT_TIMESTAMP as valid_from,
    NULL as valid_to,
    TRUE as is_current,
    MD5(metric_value::TEXT) as hash_diff
FROM staging.stg_financials;

COMMIT;
```

**Idempotency**: Each run creates new version, old versions preserved

### Idempotent Glue Job Example

```python
"""
Idempotent Daily Prices ETL
Can be safely rerun for any date range
"""

import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from datetime import datetime, timedelta
import hashlib

args = getResolvedOptions(sys.argv, [
    'JOB_NAME',
    'PROCESS_DATE',  # Date to process (YYYY-MM-DD)
    'REDSHIFT_CONNECTION'
])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

process_date = args['PROCESS_DATE']

print(f"Processing data for date: {process_date}")

# Step 1: Read data for specific date (idempotent input)
datasource = glueContext.create_dynamic_frame.from_options(
    connection_type="s3",
    connection_options={
        "paths": [f"s3://bucket/raw/prices/{process_date.replace('-', '/')}/"]
    },
    format="csv",
    format_options={"withHeader": True}
)

# Step 2: Transform with deterministic logic
def transform_with_hash(rec):
    """Add hash for deduplication"""
    # Create deterministic hash
    hash_input = f"{rec['symbol']}|{rec['date']}|{rec['close']}"
    record_hash = hashlib.md5(hash_input.encode()).hexdigest()
    
    return {
        'security_id': rec['symbol'],
        'price_date': rec['date'],
        'close_price': float(rec['close']),
        'volume': int(rec['volume']),
        'record_hash': record_hash,
        'load_timestamp': datetime.now().isoformat()
    }

transformed = Map.apply(frame=datasource, f=transform_with_hash)

# Step 3: Write to staging (truncate first - idempotent)
# Execute pre-action to clear staging for this date
preactions = f"""
    DELETE FROM staging.stg_prices 
    WHERE price_date = '{process_date}';
"""

glueContext.write_dynamic_frame.from_options(
    frame=transformed,
    connection_type="redshift",
    connection_options={
        "url": f"jdbc:redshift://{args['REDSHIFT_CONNECTION']}",
        "dbtable": "staging.stg_prices",
        "user": "etl_user",
        "password": "password",
        "preactions": preactions
    }
)

# Step 4: Merge to integration (idempotent)
merge_sql = f"""
    BEGIN TRANSACTION;
    
    -- Delete existing records for this date
    DELETE FROM integration.prices
    WHERE price_date = '{process_date}';
    
    -- Insert new records
    INSERT INTO integration.prices
    SELECT 
        security_id,
        price_date,
        close_price,
        volume,
        record_hash,
        load_timestamp
    FROM staging.stg_prices
    WHERE price_date = '{process_date}';
    
    COMMIT;
"""

# Execute merge
spark.read \
    .format("jdbc") \
    .option("url", f"jdbc:redshift://{args['REDSHIFT_CONNECTION']}") \
    .option("query", merge_sql) \
    .option("user", "etl_user") \
    .option("password", "password") \
    .load()

# Step 5: Update presentation (idempotent with dedup)
presentation_sql = f"""
    BEGIN TRANSACTION;
    
    -- Delete existing records for this date
    DELETE FROM fact_daily_prices
    WHERE price_date = '{process_date}';
    
    -- Insert with corporate action adjustments
    INSERT INTO fact_daily_prices (
        price_date,
        security_key,
        close_price,
        adjusted_close,
        volume
    )
    SELECT 
        p.price_date,
        s.security_key,
        p.close_price,
        p.close_price * COALESCE(a.cumulative_factor, 1.0) as adjusted_close,
        p.volume
    FROM integration.prices p
    JOIN dim_security s ON p.security_id = s.security_id
    LEFT JOIN price_adjustments a ON p.security_id = a.security_id 
        AND p.price_date = a.price_date
    WHERE p.price_date = '{process_date}';
    
    COMMIT;
"""

spark.read \
    .format("jdbc") \
    .option("url", f"jdbc:redshift://{args['REDSHIFT_CONNECTION']}") \
    .option("query", presentation_sql) \
    .option("user", "etl_user") \
    .option("password", "password") \
    .load()

job.commit()

print(f"Successfully processed {process_date} - Idempotent execution complete")
```

### Testing Idempotency

```python
"""
Test script to verify idempotency
"""

import boto3
from datetime import datetime

glue = boto3.client('glue')
redshift_data = boto3.client('redshift-data')

def run_job_and_check(process_date):
    """Run job and return record count"""
    
    # Run Glue job
    response = glue.start_job_run(
        JobName='daily-prices-etl',
        Arguments={
            '--PROCESS_DATE': process_date
        }
    )
    
    job_run_id = response['JobRunId']
    
    # Wait for completion
    waiter = glue.get_waiter('job_run_complete')
    waiter.wait(JobName='daily-prices-etl', RunId=job_run_id)
    
    # Query record count
    result = redshift_data.execute_statement(
        ClusterIdentifier='research-platform-cluster',
        Database='research_platform',
        DbUser='admin',
        Sql=f"SELECT COUNT(*) FROM fact_daily_prices WHERE price_date = '{process_date}'"
    )
    
    # Get result
    query_id = result['Id']
    # ... wait and fetch result ...
    
    return record_count

# Test idempotency
test_date = '2024-01-01'

print("Run 1...")
count1 = run_job_and_check(test_date)
print(f"Record count: {count1}")

print("Run 2 (should be identical)...")
count2 = run_job_and_check(test_date)
print(f"Record count: {count2}")

assert count1 == count2, "Idempotency test FAILED!"
print("✓ Idempotency test PASSED!")
```

### Idempotency Checklist

- [ ] Pipeline can be rerun with same input
- [ ] No duplicate records created
- [ ] Results are deterministic
- [ ] Timestamps use fixed values (not CURRENT_TIMESTAMP in business logic)
- [ ] Deletes before inserts (or upserts)
- [ ] Hash-based deduplication
- [ ] Transaction boundaries clear
- [ ] Tested with multiple runs


## Metrics Monitoring Across Pipeline Stages

### Overview

Comprehensive metrics monitoring tracks data quality, performance, and reliability across all pipeline stages:

1. **Ingestion Stage**: S3 → Lambda → Glue
2. **Transformation Stage**: Staging → Integration → Presentation
3. **Query Stage**: API → Redshift → Cache
4. **Data Quality Stage**: Validation → Quarantine → Alerting

### Metrics Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Metrics Collection                        │
├─────────────────────────────────────────────────────────────┤
│  Lambda → CloudWatch Logs → Custom Metrics                  │
│  Glue → CloudWatch Logs → Custom Metrics                    │
│  API → CloudWatch Logs → Custom Metrics                     │
│  Redshift → System Tables → Custom Metrics                  │
├─────────────────────────────────────────────────────────────┤
│                    Metrics Storage                           │
├─────────────────────────────────────────────────────────────┤
│  CloudWatch Metrics (15 months retention)                   │
│  Redshift Control Tables (indefinite)                       │
│  S3 Metrics Archive (long-term)                             │
├─────────────────────────────────────────────────────────────┤
│                    Metrics Visualization                     │
├─────────────────────────────────────────────────────────────┤
│  CloudWatch Dashboards                                       │
│  Grafana Dashboards                                          │
│  Custom Reports                                              │
└─────────────────────────────────────────────────────────────┘
```

### Stage 1: Ingestion Metrics

#### Lambda Validator Metrics

```python
"""
Lambda validator with metrics publishing
"""

import boto3
import json
from datetime import datetime

cloudwatch = boto3.client('cloudwatch')

def publish_metric(metric_name, value, unit='Count', dimensions=None):
    """Publish custom metric to CloudWatch"""
    
    metric_data = {
        'MetricName': metric_name,
        'Value': value,
        'Unit': unit,
        'Timestamp': datetime.now(),
        'Dimensions': dimensions or []
    }
    
    cloudwatch.put_metric_data(
        Namespace='ResearchDataPlatform/Ingestion',
        MetricData=[metric_data]
    )

def lambda_handler(event, context):
    """Price validator with metrics"""
    
    start_time = datetime.now()
    
    # Get S3 object
    bucket = event['Records'][0]['s3']['bucket']['name']
    key = event['Records'][0]['s3']['object']['key']
    
    # Extract data source from key
    data_source = key.split('/')[1]  # e.g., 'prices'
    
    dimensions = [
        {'Name': 'DataSource', 'Value': data_source},
        {'Name': 'Stage', 'Value': 'Validation'}
    ]
    
    try:
        # Download and validate file
        s3 = boto3.client('s3')
        obj = s3.get_object(Bucket=bucket, Key=key)
        data = obj['Body'].read().decode('utf-8')
        
        # Parse CSV
        lines = data.split('\n')
        record_count = len(lines) - 1  # Exclude header
        
        # Publish record count
        publish_metric(
            'RecordsReceived',
            record_count,
            'Count',
            dimensions
        )
        
        # Validate records
        validation_results = validate_data(data)
        
        # Publish validation metrics
        publish_metric(
            'ValidationPassRate',
            validation_results['pass_rate'],
            'Percent',
            dimensions
        )
        
        publish_metric(
            'ValidationFailures',
            validation_results['failed_count'],
            'Count',
            dimensions
        )
        
        # Calculate processing time
        duration_ms = (datetime.now() - start_time).total_seconds() * 1000
        
        publish_metric(
            'ValidationDuration',
            duration_ms,
            'Milliseconds',
            dimensions
        )
        
        # Publish success/failure
        if validation_results['pass_rate'] >= 95:
            publish_metric('ValidationSuccess', 1, 'Count', dimensions)
            return {'statusCode': 200, 'body': 'Validation passed'}
        else:
            publish_metric('ValidationFailure', 1, 'Count', dimensions)
            raise Exception(f"Validation failed: {validation_results['pass_rate']}% pass rate")
            
    except Exception as e:
        # Publish error metric
        publish_metric('ValidationError', 1, 'Count', dimensions)
        raise

def validate_data(data):
    """Validate data and return results"""
    # ... validation logic ...
    return {
        'pass_rate': 98.5,
        'failed_count': 15,
        'total_count': 1000
    }
```

#### Glue ETL Metrics

```python
"""
Glue ETL job with comprehensive metrics
"""

import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
import boto3
from datetime import datetime

args = getResolvedOptions(sys.argv, ['JOB_NAME'])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

cloudwatch = boto3.client('cloudwatch')

class MetricsPublisher:
    """Publish metrics to CloudWatch"""
    
    def __init__(self, job_name, data_source):
        self.job_name = job_name
        self.data_source = data_source
        self.namespace = 'ResearchDataPlatform/ETL'
        self.start_time = datetime.now()
    
    def publish(self, metric_name, value, unit='Count'):
        """Publish metric"""
        cloudwatch.put_metric_data(
            Namespace=self.namespace,
            MetricData=[{
                'MetricName': metric_name,
                'Value': value,
                'Unit': unit,
                'Timestamp': datetime.now(),
                'Dimensions': [
                    {'Name': 'JobName', 'Value': self.job_name},
                    {'Name': 'DataSource', 'Value': self.data_source},
                    {'Name': 'Stage', 'Value': 'ETL'}
                ]
            }]
        )
    
    def publish_duration(self, stage_name):
        """Publish stage duration"""
        duration_ms = (datetime.now() - self.start_time).total_seconds() * 1000
        self.publish(f'{stage_name}Duration', duration_ms, 'Milliseconds')
        self.start_time = datetime.now()  # Reset for next stage

# Initialize metrics
metrics = MetricsPublisher(args['JOB_NAME'], 'prices')

# Stage 1: Read from S3
print("Stage 1: Reading from S3...")
datasource = glueContext.create_dynamic_frame.from_options(
    connection_type="s3",
    connection_options={"paths": ["s3://bucket/raw/prices/"]},
    format="csv",
    format_options={"withHeader": True},
    transformation_ctx="datasource"
)

input_count = datasource.count()
metrics.publish('InputRecords', input_count)
metrics.publish_duration('Read')

# Stage 2: Transform
print("Stage 2: Transforming data...")
transformed = Map.apply(frame=datasource, f=transform_function)

transform_count = transformed.count()
metrics.publish('TransformedRecords', transform_count)
metrics.publish_duration('Transform')

# Stage 3: Data Quality Checks
print("Stage 3: Data quality checks...")
quality_results = run_quality_checks(transformed)

metrics.publish('QualityPassRate', quality_results['pass_rate'], 'Percent')
metrics.publish('QualityFailures', quality_results['failed_count'])
metrics.publish_duration('QualityCheck')

# Stage 4: Write to Redshift
print("Stage 4: Writing to Redshift...")
glueContext.write_dynamic_frame.from_options(
    frame=transformed,
    connection_type="redshift",
    connection_options={
        "url": "jdbc:redshift://...",
        "dbtable": "staging.stg_prices",
        "user": "etl_user",
        "password": "password"
    },
    transformation_ctx="datasink"
)

output_count = transform_count
metrics.publish('OutputRecords', output_count)
metrics.publish_duration('Write')

# Stage 5: Post-processing
print("Stage 5: Post-processing...")
# Run SQL transformations in Redshift
# ... staging to integration to presentation ...

metrics.publish('PostProcessingComplete', 1)
metrics.publish_duration('PostProcess')

# Publish overall metrics
total_duration = (datetime.now() - metrics.start_time).total_seconds()
metrics.publish('TotalJobDuration', total_duration * 1000, 'Milliseconds')
metrics.publish('JobSuccess', 1)

# Calculate throughput
throughput = input_count / total_duration if total_duration > 0 else 0
metrics.publish('RecordsPerSecond', throughput, 'Count/Second')

job.commit()

print(f"Job completed: {input_count} records processed in {total_duration:.2f} seconds")
```

### Stage 2: Transformation Metrics

#### Redshift Control Tables

```sql
-- Create control tables for metrics
CREATE TABLE control.etl_job_metrics (
    job_run_id VARCHAR(100),
    job_name VARCHAR(100),
    data_source VARCHAR(50),
    stage_name VARCHAR(50),
    start_time TIMESTAMP,
    end_time TIMESTAMP,
    duration_seconds INTEGER,
    input_records BIGINT,
    output_records BIGINT,
    failed_records BIGINT,
    status VARCHAR(20),
    error_message VARCHAR(MAX)
);

CREATE TABLE control.data_quality_metrics (
    check_id BIGINT IDENTITY(1,1),
    data_source VARCHAR(50),
    check_timestamp TIMESTAMP,
    rule_name VARCHAR(100),
    total_records BIGINT,
    passed_records BIGINT,
    failed_records BIGINT,
    pass_rate DECIMAL(5,2),
    status VARCHAR(20)
);

CREATE TABLE control.query_performance_metrics (
    query_id BIGINT,
    user_name VARCHAR(100),
    query_text VARCHAR(MAX),
    start_time TIMESTAMP,
    end_time TIMESTAMP,
    duration_seconds INTEGER,
    rows_returned BIGINT,
    rows_scanned BIGINT,
    queue_time_seconds INTEGER,
    execution_time_seconds INTEGER
);
```

#### Logging Metrics from Glue

```python
"""
Log metrics to Redshift control tables
"""

def log_etl_metrics(redshift_conn, metrics_data):
    """Log ETL metrics to control table"""
    
    cursor = redshift_conn.cursor()
    
    sql = """
        INSERT INTO control.etl_job_metrics (
            job_run_id,
            job_name,
            data_source,
            stage_name,
            start_time,
            end_time,
            duration_seconds,
            input_records,
            output_records,
            failed_records,
            status
        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
    """
    
    cursor.execute(sql, (
        metrics_data['job_run_id'],
        metrics_data['job_name'],
        metrics_data['data_source'],
        metrics_data['stage_name'],
        metrics_data['start_time'],
        metrics_data['end_time'],
        metrics_data['duration_seconds'],
        metrics_data['input_records'],
        metrics_data['output_records'],
        metrics_data['failed_records'],
        metrics_data['status']
    ))
    
    redshift_conn.commit()

# Usage in Glue job
import psycopg2

redshift_conn = psycopg2.connect(
    host='redshift-endpoint',
    port=5439,
    database='research_platform',
    user='etl_user',
    password='password'
)

log_etl_metrics(redshift_conn, {
    'job_run_id': context.aws_request_id,
    'job_name': 'daily-prices-etl',
    'data_source': 'prices',
    'stage_name': 'transform',
    'start_time': start_time,
    'end_time': datetime.now(),
    'duration_seconds': 120,
    'input_records': 10000,
    'output_records': 9950,
    'failed_records': 50,
    'status': 'SUCCESS'
})
```

### Stage 3: Query Metrics

#### API Service Metrics

```python
"""
FastAPI service with comprehensive metrics
"""

from fastapi import FastAPI
import time
from datetime import datetime
import boto3

app = FastAPI()
cloudwatch = boto3.client('cloudwatch')

class QueryMetrics:
    """Track query metrics"""
    
    @staticmethod
    def publish(metric_name, value, unit='Count', dimensions=None):
        """Publish metric to CloudWatch"""
        cloudwatch.put_metric_data(
            Namespace='ResearchDataPlatform/Query',
            MetricData=[{
                'MetricName': metric_name,
                'Value': value,
                'Unit': unit,
                'Timestamp': datetime.now(),
                'Dimensions': dimensions or []
            }]
        )
    
    @staticmethod
    def log_to_redshift(conn, query_data):
        """Log query to Redshift"""
        cursor = conn.cursor()
        cursor.execute("""
            INSERT INTO control.query_performance_metrics (
                query_id, user_name, query_text, start_time, end_time,
                duration_seconds, rows_returned, rows_scanned
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        """, (
            query_data['query_id'],
            query_data['user'],
            query_data['query'][:5000],
            query_data['start_time'],
            query_data['end_time'],
            query_data['duration'],
            query_data['rows_returned'],
            query_data['rows_scanned']
        ))
        conn.commit()

@app.post("/api/v1/query/execute")
async def execute_query(request: QueryRequest):
    """Execute query with metrics"""
    
    start_time = time.time()
    cache_hit = False
    
    try:
        # Check cache
        cache_key = generate_cache_key(request.query)
        cached_result = get_cached_result(cache_key)
        
        if cached_result:
            cache_hit = True
            QueryMetrics.publish('CacheHit', 1)
            return cached_result
        
        QueryMetrics.publish('CacheMiss', 1)
        
        # Execute query
        results = execute_query_on_redshift(request.query)
        
        # Calculate metrics
        duration_ms = (time.time() - start_time) * 1000
        row_count = len(results)
        
        # Publish metrics
        QueryMetrics.publish('QueryExecutionTime', duration_ms, 'Milliseconds')
        QueryMetrics.publish('RowsReturned', row_count, 'Count')
        QueryMetrics.publish('QuerySuccess', 1)
        
        # Calculate cache hit rate
        cache_hit_rate = calculate_cache_hit_rate()
        QueryMetrics.publish('CacheHitRate', cache_hit_rate, 'Percent')
        
        # Log to Redshift
        QueryMetrics.log_to_redshift(get_redshift_conn(), {
            'query_id': cache_key,
            'user': 'api_user',
            'query': request.query,
            'start_time': datetime.fromtimestamp(start_time),
            'end_time': datetime.now(),
            'duration': duration_ms / 1000,
            'rows_returned': row_count,
            'rows_scanned': estimate_rows_scanned(request.query)
        })
        
        return {
            'data': results,
            'row_count': row_count,
            'execution_time_ms': duration_ms,
            'cached': cache_hit
        }
        
    except Exception as e:
        # Publish error metrics
        QueryMetrics.publish('QueryFailure', 1)
        QueryMetrics.publish('QueryError', 1, dimensions=[
            {'Name': 'ErrorType', 'Value': type(e).__name__}
        ])
        raise
```

### Stage 4: Data Quality Metrics

```python
"""
Data quality engine with metrics
"""

from lambda.validators.data_quality_engine import DataQualityEngine
from lambda.validators.data_quality_rules import *

def run_data_quality_with_metrics(df, data_source):
    """Run data quality checks with metrics"""
    
    # Initialize engine
    engine = DataQualityEngine(
        s3_quarantine_bucket='itus-data-quarantine',
        sns_topic_arn='arn:aws:sns:...',
        redshift_conn=get_redshift_conn()
    )
    
    # Define rules
    rules = [
        RequiredColumnsRule(['security_id', 'price_date', 'close_price']),
        NullCheckRule(['security_id', 'price_date', 'close_price']),
        PositiveValueRule(['close_price', 'volume']),
        PriceChangeRule('close_price', max_change_pct=50.0),
        DuplicateCheckRule(['security_id', 'price_date'])
    ]
    
    # Execute rules
    summary = engine.execute_rules(df, rules)
    
    # Publish metrics to CloudWatch
    cloudwatch = boto3.client('cloudwatch')
    
    dimensions = [
        {'Name': 'DataSource', 'Value': data_source},
        {'Name': 'Stage', 'Value': 'DataQuality'}
    ]
    
    cloudwatch.put_metric_data(
        Namespace='ResearchDataPlatform/DataQuality',
        MetricData=[
            {
                'MetricName': 'TotalRules',
                'Value': summary['total_rules'],
                'Unit': 'Count',
                'Dimensions': dimensions
            },
            {
                'MetricName': 'PassedRules',
                'Value': summary['passed'],
                'Unit': 'Count',
                'Dimensions': dimensions
            },
            {
                'MetricName': 'FailedRules',
                'Value': summary['failed'],
                'Unit': 'Count',
                'Dimensions': dimensions
            },
            {
                'MetricName': 'PassRate',
                'Value': summary['pass_rate'],
                'Unit': 'Percent',
                'Dimensions': dimensions
            }
        ]
    )
    
    # Quarantine failed data
    if summary['failed'] > 0:
        quarantined = engine.quarantine_failed_data(df, data_source, 'data.csv')
        
        cloudwatch.put_metric_data(
            Namespace='ResearchDataPlatform/DataQuality',
            MetricData=[{
                'MetricName': 'QuarantinedFiles',
                'Value': len(quarantined),
                'Unit': 'Count',
                'Dimensions': dimensions
            }]
        )
    
    # Send alerts if needed
    engine.send_alerts(data_source, 'data.csv', summary)
    
    # Log to Redshift
    engine.log_results_to_redshift(data_source, 'data.csv', summary)
    
    return summary
```

### Metrics Dashboard Queries

```sql
-- ETL Performance Dashboard
CREATE VIEW control.etl_performance_dashboard AS
SELECT 
    DATE_TRUNC('hour', start_time) as hour,
    job_name,
    data_source,
    COUNT(*) as job_runs,
    AVG(duration_seconds) as avg_duration_seconds,
    MAX(duration_seconds) as max_duration_seconds,
    SUM(input_records) as total_input_records,
    SUM(output_records) as total_output_records,
    SUM(failed_records) as total_failed_records,
    AVG(CASE WHEN output_records > 0 
        THEN (output_records::FLOAT / input_records) * 100 
        ELSE 0 END) as avg_success_rate,
    SUM(CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END) as successful_runs,
    SUM(CASE WHEN status = 'FAILED' THEN 1 ELSE 0 END) as failed_runs
FROM control.etl_job_metrics
WHERE start_time >= DATEADD(day, -7, CURRENT_DATE)
GROUP BY DATE_TRUNC('hour', start_time), job_name, data_source
ORDER BY hour DESC;

-- Data Quality Dashboard
CREATE VIEW control.data_quality_dashboard AS
SELECT 
    DATE_TRUNC('day', check_timestamp) as date,
    data_source,
    COUNT(DISTINCT rule_name) as rules_checked,
    AVG(pass_rate) as avg_pass_rate,
    SUM(failed_records) as total_failed_records,
    SUM(CASE WHEN status = 'PASS' THEN 1 ELSE 0 END) as passed_checks,
    SUM(CASE WHEN status = 'FAIL' THEN 1 ELSE 0 END) as failed_checks
FROM control.data_quality_metrics
WHERE check_timestamp >= DATEADD(day, -30, CURRENT_DATE)
GROUP BY DATE_TRUNC('day', check_timestamp), data_source
ORDER BY date DESC;

-- Query Performance Dashboard
CREATE VIEW control.query_performance_dashboard AS
SELECT 
    DATE_TRUNC('hour', start_time) as hour,
    COUNT(*) as query_count,
    AVG(duration_seconds) as avg_duration_seconds,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY duration_seconds) as median_duration,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration_seconds) as p95_duration,
    MAX(duration_seconds) as max_duration_seconds,
    AVG(rows_returned) as avg_rows_returned,
    SUM(rows_scanned) as total_rows_scanned
FROM control.query_performance_metrics
WHERE start_time >= DATEADD(day, -7, CURRENT_DATE)
GROUP BY DATE_TRUNC('hour', start_time)
ORDER BY hour DESC;
```

### Alerting Based on Metrics

```python
"""
CloudWatch alarms based on metrics
"""

import boto3

cloudwatch = boto3.client('cloudwatch')

def create_metric_alarms():
    """Create alarms for key metrics"""
    
    alarms = [
        {
            'name': 'etl-high-failure-rate',
            'metric': 'JobFailure',
            'namespace': 'ResearchDataPlatform/ETL',
            'threshold': 1,
            'comparison': 'GreaterThanOrEqualToThreshold',
            'description': 'Alert when ETL job fails'
        },
        {
            'name': 'data-quality-low-pass-rate',
            'metric': 'PassRate',
            'namespace': 'ResearchDataPlatform/DataQuality',
            'threshold': 95,
            'comparison': 'LessThanThreshold',
            'description': 'Alert when data quality pass rate < 95%'
        },
        {
            'name': 'query-high-latency',
            'metric': 'QueryExecutionTime',
            'namespace': 'ResearchDataPlatform/Query',
            'threshold': 5000,  # 5 seconds
            'comparison': 'GreaterThanThreshold',
            'description': 'Alert when query latency > 5 seconds'
        },
        {
            'name': 'cache-low-hit-rate',
            'metric': 'CacheHitRate',
            'namespace': 'ResearchDataPlatform/Query',
            'threshold': 40,
            'comparison': 'LessThanThreshold',
            'description': 'Alert when cache hit rate < 40%'
        }
    ]
    
    for alarm in alarms:
        cloudwatch.put_metric_alarm(
            AlarmName=alarm['name'],
            AlarmDescription=alarm['description'],
            ActionsEnabled=True,
            AlarmActions=['arn:aws:sns:us-east-1:123456789012:alerts'],
            MetricName=alarm['metric'],
            Namespace=alarm['namespace'],
            Statistic='Average',
            Period=300,
            EvaluationPeriods=2,
            Threshold=alarm['threshold'],
            ComparisonOperator=alarm['comparison']
        )
        
        print(f"Created alarm: {alarm['name']}")

if __name__ == '__main__':
    create_metric_alarms()
```

### Metrics Best Practices

1. **Consistent Naming**: Use hierarchical naming (Service/Component/Metric)
2. **Appropriate Units**: Use correct units (Count, Percent, Milliseconds, etc.)
3. **Dimensions**: Add dimensions for filtering (DataSource, Stage, JobName)
4. **Granularity**: Balance detail vs cost (don't over-instrument)
5. **Retention**: Store long-term metrics in Redshift, short-term in CloudWatch
6. **Alerting**: Set thresholds based on SLAs
7. **Dashboards**: Create role-specific dashboards (ops, analysts, executives)
8. **Documentation**: Document what each metric means and how to interpret it

### Metrics Summary

| Stage | Key Metrics | Purpose |
|-------|-------------|---------|
| Ingestion | RecordsReceived, ValidationPassRate, ValidationDuration | Track data arrival and quality |
| ETL | InputRecords, OutputRecords, JobDuration, FailureRate | Monitor pipeline health |
| Data Quality | PassRate, FailedRecords, QuarantinedFiles | Ensure data integrity |
| Query | ExecutionTime, CacheHitRate, RowsReturned | Optimize performance |
| System | CPUUtilization, DiskUsage, QueueTime | Monitor infrastructure |
| Cost | ConcurrencyScalingHours, StorageGB, QueryCost | Control spending |
