"""
AWS Glue ETL Job: Daily Institutional Flows
Loads FII/DII institutional flow data from S3 to Redshift staging tables.
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


def load_flow_data():
    """Load institutional flow data from S3 to Redshift staging."""
    
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
    df = df.withColumn("flow_date", to_date(col("flow_date"))) \
           .withColumn("net_fii_flow", col("fii_buy_value") - col("fii_sell_value")) \
           .withColumn("net_dii_flow", col("dii_buy_value") - col("dii_sell_value")) \
           .withColumn("load_timestamp", current_timestamp()) \
           .withColumn("source_file", lit(S3_KEY))
    
    # Write to staging
    dynamic_frame = DynamicFrame.fromDF(df, glueContext, "flow_data")
    
    glueContext.write_dynamic_frame.from_options(
        frame=dynamic_frame,
        connection_type="redshift",
        connection_options={
            "url": REDSHIFT_CONNECTION,
            "dbtable": "staging.stg_institutional_flows",
            "redshiftTmpDir": REDSHIFT_TEMP_DIR,
            "preactions": """
                CREATE TABLE IF NOT EXISTS staging.stg_institutional_flows (
                    security_id VARCHAR(50),
                    flow_date DATE,
                    fii_buy_value DECIMAL(18,2),
                    fii_sell_value DECIMAL(18,2),
                    dii_buy_value DECIMAL(18,2),
                    dii_sell_value DECIMAL(18,2),
                    net_fii_flow DECIMAL(18,2),
                    net_dii_flow DECIMAL(18,2),
                    load_timestamp TIMESTAMP,
                    source_file VARCHAR(500)
                )
                DISTSTYLE EVEN
                SORTKEY(flow_date);
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
    load_flow_data()
    job.commit()
except Exception as e:
    print(f"ETL job failed: {str(e)}")
    raise
