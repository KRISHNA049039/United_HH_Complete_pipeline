"""
AWS Glue ETL Job: Quarterly Financials
Loads quarterly financial statements from S3 to Redshift staging tables.
Handles temporal versioning and financial restatements.
"""

import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import col, lit, current_timestamp, to_date, max as spark_max, md5, concat_ws
from datetime import datetime
import boto3

args = getResolvedOptions(sys.argv, [
    'JOB_NAME',
    'S3_BUCKET',
    'S3_KEY',
    'REDSHIFT_CONNECTION',
    'REDSHIFT_TEMP_DIR'
])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

S3_BUCKET = args['S3_BUCKET']
S3_KEY = args['S3_KEY']
REDSHIFT_CONNECTION = args['REDSHIFT_CONNECTION']
REDSHIFT_TEMP_DIR = args['REDSHIFT_TEMP_DIR']

print(f"Processing file: s3://{S3_BUCKET}/{S3_KEY}")


def load_financial_data():
    """Load financial data from S3 to Redshift staging."""
    
    # Read CSV from S3
    print("Reading data from S3...")
    df = spark.read.format("csv") \
        .option("header", "true") \
        .option("inferSchema", "true") \
        .load(f"s3://{S3_BUCKET}/{S3_KEY}")
    
    print(f"Loaded {df.count()} records from S3")
    
    if df.count() == 0:
        print("No records to process")
        return
    
    # Data transformations
    print("Applying transformations...")
    
    # Convert date strings to date type
    df = df.withColumn("reporting_period_end", to_date(col("reporting_period_end"))) \
           .withColumn("publication_date", to_date(col("publication_date")))
    
    # Calculate hash for change detection (for restatements)
    df = df.withColumn(
        "hash_diff",
        md5(concat_ws("|",
            col("revenue"),
            col("ebitda"),
            col("net_income"),
            col("total_assets"),
            col("total_liabilities"),
            col("total_equity")
        ))
    )
    
    # Add metadata columns
    df = df.withColumn("load_timestamp", current_timestamp()) \
           .withColumn("source_file", lit(S3_KEY)) \
           .withColumn("job_name", lit(args['JOB_NAME'])) \
           .withColumn("is_current", lit(True))
    
    # Validate data quality
    print("Validating data quality...")
    
    # Check for nulls in critical columns
    null_counts = df.select([
        col(c).isNull().cast("int").alias(c) 
        for c in ['security_id', 'reporting_period_end', 'publication_date']
    ]).agg(*[spark_max(c).alias(c) for c in ['security_id', 'reporting_period_end', 'publication_date']])
    
    null_row = null_counts.first()
    if any(null_row[c] > 0 for c in ['security_id', 'reporting_period_end', 'publication_date']):
        raise ValueError("Found null values in critical columns")
    
    # Validate temporal consistency
    invalid_temporal = df.filter(
        col("publication_date") < col("reporting_period_end")
    ).count()
    
    if invalid_temporal > 0:
        raise ValueError(
            f"Found {invalid_temporal} records where publication_date < reporting_period_end"
        )
    
    # Validate balance sheet equation (if columns present)
    if all(c in df.columns for c in ['total_assets', 'total_liabilities', 'total_equity']):
        df_with_balance = df.withColumn(
            "balance_diff",
            col("total_assets") - (col("total_liabilities") + col("total_equity"))
        ).withColumn(
            "balance_diff_pct",
            col("balance_diff") / col("total_assets")
        )
        
        imbalanced = df_with_balance.filter(
            col("balance_diff_pct").cast("double") > 0.01
        ).count()
        
        if imbalanced > 0:
            print(f"Warning: Found {imbalanced} records with balance sheet imbalance > 1%")
    
    print("Data quality checks passed")
    
    # Write to Redshift staging table
    print("Writing to Redshift staging table...")
    
    dynamic_frame = DynamicFrame.fromDF(df, glueContext, "financial_data")
    
    glueContext.write_dynamic_frame.from_options(
        frame=dynamic_frame,
        connection_type="redshift",
        connection_options={
            "url": REDSHIFT_CONNECTION,
            "dbtable": "staging.stg_quarterly_financials",
            "redshiftTmpDir": REDSHIFT_TEMP_DIR,
            "preactions": """
                CREATE TABLE IF NOT EXISTS staging.stg_quarterly_financials (
                    security_id VARCHAR(50),
                    reporting_period_end DATE,
                    publication_date DATE,
                    revenue DECIMAL(18,2),
                    ebitda DECIMAL(18,2),
                    net_income DECIMAL(18,2),
                    total_assets DECIMAL(18,2),
                    total_liabilities DECIMAL(18,2),
                    total_equity DECIMAL(18,2),
                    hash_diff VARCHAR(64),
                    load_timestamp TIMESTAMP,
                    source_file VARCHAR(500),
                    job_name VARCHAR(200),
                    is_current BOOLEAN
                )
                DISTSTYLE EVEN
                SORTKEY(reporting_period_end, publication_date);
            """
        }
    )
    
    print(f"Successfully loaded {df.count()} records to staging table")
    
    # Move processed file
    move_to_processed()


def move_to_processed():
    """Move processed file from raw/ to processed/."""
    try:
        s3_client = boto3.client('s3')
        
        processed_key = S3_KEY.replace('raw/', 'processed/')
        s3_client.copy_object(
            Bucket=S3_BUCKET,
            CopySource={'Bucket': S3_BUCKET, 'Key': S3_KEY},
            Key=processed_key
        )
        
        s3_client.delete_object(Bucket=S3_BUCKET, Key=S3_KEY)
        
        print(f"Moved file to: s3://{S3_BUCKET}/{processed_key}")
    except Exception as e:
        print(f"Error moving file: {str(e)}")


# Main execution
try:
    load_financial_data()
    print("ETL job completed successfully")
    job.commit()
except Exception as e:
    print(f"ETL job failed: {str(e)}")
    raise
