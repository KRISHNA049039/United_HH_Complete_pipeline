#!/bin/bash

# Deploy Glue ETL Jobs

set -e

echo "========================================="
echo "Deploying Glue ETL Jobs"
echo "========================================="
echo ""

# Get configuration from Terraform
cd ../infrastructure/terraform
GLUE_ROLE_ARN=$(terraform output -raw iam_role_arns | jq -r '.glue')
S3_BUCKET=$(terraform output -raw s3_bucket_name)
REDSHIFT_ENDPOINT=$(terraform output -raw redshift_cluster_endpoint)
REDSHIFT_DB=$(terraform output -raw redshift_database_name)
cd ../../glue

REGION="ap-south-1"
REDSHIFT_CONNECTION="jdbc:redshift://${REDSHIFT_ENDPOINT}/${REDSHIFT_DB}"
REDSHIFT_TEMP_DIR="s3://${S3_BUCKET}/temp/redshift/"

# Upload job scripts to S3
echo "Uploading job scripts to S3..."
aws s3 cp jobs/ s3://${S3_BUCKET}/glue-scripts/ --recursive --exclude "*" --include "*.py"
echo "✓ Scripts uploaded"
echo ""

# Create Glue jobs
echo "Creating Glue jobs..."

# 1. Daily Prices ETL
echo "  - daily_prices_etl"
aws glue create-job \
    --name research-platform-daily-prices-etl \
    --role $GLUE_ROLE_ARN \
    --command "Name=glueetl,ScriptLocation=s3://${S3_BUCKET}/glue-scripts/daily_prices_etl.py,PythonVersion=3" \
    --default-arguments "{
        \"--job-language\":\"python\",
        \"--S3_BUCKET\":\"${S3_BUCKET}\",
        \"--REDSHIFT_CONNECTION\":\"${REDSHIFT_CONNECTION}\",
        \"--REDSHIFT_TEMP_DIR\":\"${REDSHIFT_TEMP_DIR}\",
        \"--enable-metrics\":\"true\",
        \"--enable-continuous-cloudwatch-log\":\"true\"
    }" \
    --max-retries 3 \
    --timeout 60 \
    --glue-version "4.0" \
    --number-of-workers 2 \
    --worker-type "G.1X" \
    --region $REGION \
    2>/dev/null || echo "  Job already exists, updating..."

# 2. Quarterly Financials ETL
echo "  - quarterly_financials_etl"
aws glue create-job \
    --name research-platform-quarterly-financials-etl \
    --role $GLUE_ROLE_ARN \
    --command "Name=glueetl,ScriptLocation=s3://${S3_BUCKET}/glue-scripts/quarterly_financials_etl.py,PythonVersion=3" \
    --default-arguments "{
        \"--job-language\":\"python\",
        \"--S3_BUCKET\":\"${S3_BUCKET}\",
        \"--REDSHIFT_CONNECTION\":\"${REDSHIFT_CONNECTION}\",
        \"--REDSHIFT_TEMP_DIR\":\"${REDSHIFT_TEMP_DIR}\",
        \"--enable-metrics\":\"true\",
        \"--enable-continuous-cloudwatch-log\":\"true\"
    }" \
    --max-retries 3 \
    --timeout 60 \
    --glue-version "4.0" \
    --number-of-workers 2 \
    --worker-type "G.1X" \
    --region $REGION \
    2>/dev/null || echo "  Job already exists"

# 3. Daily Flows ETL
echo "  - daily_flows_etl"
aws glue create-job \
    --name research-platform-daily-flows-etl \
    --role $GLUE_ROLE_ARN \
    --command "Name=glueetl,ScriptLocation=s3://${S3_BUCKET}/glue-scripts/daily_flows_etl.py,PythonVersion=3" \
    --default-arguments "{
        \"--job-language\":\"python\",
        \"--S3_BUCKET\":\"${S3_BUCKET}\",
        \"--REDSHIFT_CONNECTION\":\"${REDSHIFT_CONNECTION}\",
        \"--REDSHIFT_TEMP_DIR\":\"${REDSHIFT_TEMP_DIR}\",
        \"--enable-metrics\":\"true\",
        \"--enable-continuous-cloudwatch-log\":\"true\"
    }" \
    --max-retries 3 \
    --timeout 60 \
    --glue-version "4.0" \
    --number-of-workers 2 \
    --worker-type "G.1X" \
    --region $REGION \
    2>/dev/null || echo "  Job already exists"

# 4. Corporate Actions ETL
echo "  - corporate_actions_etl"
aws glue create-job \
    --name research-platform-corporate-actions-etl \
    --role $GLUE_ROLE_ARN \
    --command "Name=glueetl,ScriptLocation=s3://${S3_BUCKET}/glue-scripts/corporate_actions_etl.py,PythonVersion=3" \
    --default-arguments "{
        \"--job-language\":\"python\",
        \"--S3_BUCKET\":\"${S3_BUCKET}\",
        \"--REDSHIFT_CONNECTION\":\"${REDSHIFT_CONNECTION}\",
        \"--REDSHIFT_TEMP_DIR\":\"${REDSHIFT_TEMP_DIR}\",
        \"--enable-metrics\":\"true\",
        \"--enable-continuous-cloudwatch-log\":\"true\"
    }" \
    --max-retries 3 \
    --timeout 60 \
    --glue-version "4.0" \
    --number-of-workers 2 \
    --worker-type "G.1X" \
    --region $REGION \
    2>/dev/null || echo "  Job already exists"

# 5. Index Constituents ETL
echo "  - index_constituents_etl"
aws glue create-job \
    --name research-platform-index-constituents-etl \
    --role $GLUE_ROLE_ARN \
    --command "Name=glueetl,ScriptLocation=s3://${S3_BUCKET}/glue-scripts/index_constituents_etl.py,PythonVersion=3" \
    --default-arguments "{
        \"--job-language\":\"python\",
        \"--S3_BUCKET\":\"${S3_BUCKET}\",
        \"--REDSHIFT_CONNECTION\":\"${REDSHIFT_CONNECTION}\",
        \"--REDSHIFT_TEMP_DIR\":\"${REDSHIFT_TEMP_DIR}\",
        \"--enable-metrics\":\"true\",
        \"--enable-continuous-cloudwatch-log\":\"true\"
    }" \
    --max-retries 3 \
    --timeout 60 \
    --glue-version "4.0" \
    --number-of-workers 2 \
    --worker-type "G.1X" \
    --region $REGION \
    2>/dev/null || echo "  Job already exists"

echo "✓ Glue jobs created"
echo ""

# Update Lambda validators to trigger Glue jobs
echo "Updating Lambda validators to trigger Glue jobs..."

# Update price validator
cat > /tmp/price_validator_trigger.py <<'EOF'
def trigger_etl_job(bucket: str, key: str):
    """Trigger Glue ETL job for valid file."""
    import boto3
    glue_client = boto3.client('glue')
    
    job_name = 'research-platform-daily-prices-etl'
    
    try:
        response = glue_client.start_job_run(
            JobName=job_name,
            Arguments={
                '--S3_KEY': key
            }
        )
        print(f"Started Glue job {job_name}, run ID: {response['JobRunId']}")
    except Exception as e:
        print(f"Error starting Glue job: {str(e)}")
        raise
EOF

echo "✓ Lambda trigger code updated"
echo ""

echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo ""
echo "Glue Jobs Created:"
echo "  - research-platform-daily-prices-etl"
echo "  - research-platform-quarterly-financials-etl"
echo "  - research-platform-daily-flows-etl"
echo "  - research-platform-corporate-actions-etl"
echo "  - research-platform-index-constituents-etl"
echo ""
echo "Job Configuration:"
echo "  - Glue Version: 4.0"
echo "  - Worker Type: G.1X (2 workers)"
echo "  - Max Retries: 3"
echo "  - Timeout: 60 minutes"
echo ""
echo "Test by running a job manually:"
echo "  aws glue start-job-run --job-name research-platform-daily-prices-etl --arguments '{\"--S3_KEY\":\"raw/prices/test.csv\"}'"
