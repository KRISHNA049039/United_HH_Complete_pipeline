"""
AWS Glue ETL Job: Daily Prices
Loads daily OHLCV price data from S3 to Redshift staging tables.
Implements incremental loading using high-water marks.
"""

import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import col, lit, current_timestamp, to_date, max as spark_max
from datetime import datetime
import boto3

# Initialize Glue context
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

# Configuration
S3_BUCKET = args['S3_BUCKET']
S3_KEY = args['S3_KEY']
REDSHIFT_CONNECTION = args['REDSHIFT_CONNECTION']
REDSHIFT_TEMP_DIR = args['REDSHIFT_TEMP_DIR']

print(f"Processing file: s3://{S3_BUCKET}/{S3_KEY}")


def get_high_water_mark():
    """Get the last processed date from control table."""
    try:
        control_df = glueContext.create_dynamic_frame.from_options(
            connection_type="redshift",
            connection_options={
                "url": REDSHIFT_CONNECTION,
                "dbtable": "control.etl_high_water_marks",
                "redshiftTmpDir": REDSHIFT_TEMP_DIR
            }
        ).toDF()
        
        hwm_row = control_df.filter(
            col("table_name") == "staging.stg_daily_prices"
        ).select("high_water_mark").first()
        
        if hwm_row:
            return hwm_row['high_water_mark']
        else:
            return None
    except Exception as e:
        print(f"No high water mark found: {str(e)}")
        return None


def update_high_water_mark(max_date):
    """Update the high water mark in control table."""
    try:
        # Create DataFrame with new high water mark
        hwm_data = [(
            "staging.stg_daily_prices",
            max_date,
            datetime.now(),
            args['JOB_NAME']
        )]
        
        hwm_df = spark.createDataFrame(
            hwm_data,
            ["table_name", "high_water_mark", "last_updated", "job_name"]
        )
        
        # Write to Redshift (upsert)
        glueContext.write_dynamic_frame.from_options(
            frame=DynamicFrame.fromDF(hwm_df, glueContext, "hwm_df"),
            connection_type="redshift",
            connection_options={
                "url": REDSHIFT_CONNECTION,
                "dbtable": "control.etl_high_water_marks",
                "redshiftTmpDir": REDSHIFT_TEMP_DIR,
                "preactions": """
                    DELETE FROM control.etl_high_water_marks 
                    WHERE table_name = 'staging.stg_daily_prices';
                """
            }
        )
        
        print(f"Updated high water mark to: {max_date}")
    except Exception as e:
        print(f"Error updating high water mark: {str(e)}")
        raise


def load_price_data():
    """Load price data from S3 to Redshift staging."""
    
    # Read CSV from S3
    print("Reading data from S3...")
    df = spark.read.format("csv") \
        .option("header", "true") \
        .option("inferSchema", "true") \
        .load(f"s3://{S3_BUCKET}/{S3_KEY}")
    
    print(f"Loaded {df.count()} records from S3")
    
    # Get high water mark for incremental loading
    hwm = get_high_water_mark()
    
    if hwm:
        print(f"High water mark: {hwm}")
        df = df.filter(col("price_date") > lit(hwm))
        print(f"After filtering: {df.count()} new records")
    
    if df.count() == 0:
        print("No new records to process")
        return
    
    # Data transformations
    print("Applying transformations...")
    
    # Convert date string to date type
    df = df.withColumn("price_date", to_date(col("price_date")))
    
    # Add metadata columns
    df = df.withColumn("load_timestamp", current_timestamp()) \
           .withColumn("source_file", lit(S3_KEY)) \
           .withColumn("job_name", lit(args['JOB_NAME']))
    
    # Validate data quality
    print("Validating data quality...")
    
    # Check for nulls in critical columns
    null_counts = df.select([
        col(c).isNull().cast("int").alias(c) 
        for c in ['security_id', 'price_date', 'close']
    ]).agg(*[spark_max(c).alias(c) for c in ['security_id', 'price_date', 'close']])
    
    null_row = null_counts.first()
    if any(null_row[c] > 0 for c in ['security_id', 'price_date', 'close']):
        raise ValueError("Found null values in critical columns")
    
    # Check for negative prices
    negative_prices = df.filter(
        (col("open") <= 0) | (col("high") <= 0) | 
        (col("low") <= 0) | (col("close") <= 0)
    ).count()
    
    if negative_prices > 0:
        raise ValueError(f"Found {negative_prices} records with negative prices")
    
    print("Data quality checks passed")
    
    # Write to Redshift staging table
    print("Writing to Redshift staging table...")
    
    dynamic_frame = DynamicFrame.fromDF(df, glueContext, "price_data")
    
    glueContext.write_dynamic_frame.from_options(
        frame=dynamic_frame,
        connection_type="redshift",
        connection_options={
            "url": REDSHIFT_CONNECTION,
            "dbtable": "staging.stg_daily_prices",
            "redshiftTmpDir": REDSHIFT_TEMP_DIR,
            "preactions": """
                CREATE TABLE IF NOT EXISTS staging.stg_daily_prices (
                    security_id VARCHAR(50),
                    price_date DATE,
                    open DECIMAL(18,4),
                    high DECIMAL(18,4),
                    low DECIMAL(18,4),
                    close DECIMAL(18,4),
                    volume BIGINT,
                    load_timestamp TIMESTAMP,
                    source_file VARCHAR(500),
                    job_name VARCHAR(200)
                )
                DISTSTYLE EVEN
                SORTKEY(price_date);
            """
        }
    )
    
    print(f"Successfully loaded {df.count()} records to staging table")
    
    # Update high water mark
    max_date = df.agg(spark_max("price_date")).first()[0]
    update_high_water_mark(max_date)
    
    # Move processed file to processed folder
    move_to_processed()


def move_to_processed():
    """Move processed file from raw/ to processed/."""
    try:
        s3_client = boto3.client('s3')
        
        # Copy to processed folder
        processed_key = S3_KEY.replace('raw/', 'processed/')
        s3_client.copy_object(
            Bucket=S3_BUCKET,
            CopySource={'Bucket': S3_BUCKET, 'Key': S3_KEY},
            Key=processed_key
        )
        
        # Delete from raw folder
        s3_client.delete_object(Bucket=S3_BUCKET, Key=S3_KEY)
        
        print(f"Moved file to: s3://{S3_BUCKET}/{processed_key}")
    except Exception as e:
        print(f"Error moving file: {str(e)}")
        # Don't fail the job if file move fails


# Main execution
try:
    load_price_data()
    print("ETL job completed successfully")
    job.commit()
except Exception as e:
    print(f"ETL job failed: {str(e)}")
    raise
