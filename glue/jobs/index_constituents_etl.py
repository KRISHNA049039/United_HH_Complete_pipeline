"""
AWS Glue ETL Job: Index Constituents
Loads index membership changes from S3 to Redshift staging tables.
"""

import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import col, lit, current_timestamp, to_date
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


def load_index_constituents():
    """Load index constituent data from S3 to Redshift staging."""
    
    print(f"Processing file: s3://{S3_BUCKET}/{S3_KEY}")
    
    # Read CSV
    df = spark.read.format("csv") \
        .option("header", "true") \
        .option("inferSchema", "true") \
        .load(f"s3://{S3_BUCKET}/{S3_KEY}")
    
    print(f"Loaded {df.count()} records")
    
    if df.count() == 0:
        return
    
    # Transformations
    df = df.withColumn("effective_date", to_date(col("effective_date"))) \
           .withColumn("exit_date", to_date(col("exit_date"))) \
           .withColumn("load_timestamp", current_timestamp()) \
           .withColumn("source_file", lit(S3_KEY))
    
    # Write to staging
    dynamic_frame = DynamicFrame.fromDF(df, glueContext, "index_constituents")
    
    glueContext.write_dynamic_frame.from_options(
        frame=dynamic_frame,
        connection_type="redshift",
        connection_options={
            "url": REDSHIFT_CONNECTION,
            "dbtable": "staging.stg_index_constituents",
            "redshiftTmpDir": REDSHIFT_TEMP_DIR,
            "preactions": """
                CREATE TABLE IF NOT EXISTS staging.stg_index_constituents (
                    index_name VARCHAR(50),
                    security_id VARCHAR(50),
                    effective_date DATE,
                    exit_date DATE,
                    is_current BOOLEAN,
                    load_timestamp TIMESTAMP,
                    source_file VARCHAR(500)
                )
                DISTSTYLE EVEN
                SORTKEY(index_name, effective_date);
            """
        }
    )
    
    print(f"Successfully loaded {df.count()} records")
    
    # Move to processed
    s3_client = boto3.client('s3')
    processed_key = S3_KEY.replace('raw/', 'processed/')
    s3_client.copy_object(
        Bucket=S3_BUCKET,
        CopySource={'Bucket': S3_BUCKET, 'Key': S3_KEY},
        Key=processed_key
    )
    s3_client.delete_object(Bucket=S3_BUCKET, Key=S3_KEY)


try:
    load_index_constituents()
    job.commit()
except Exception as e:
    print(f"ETL job failed: {str(e)}")
    raise
