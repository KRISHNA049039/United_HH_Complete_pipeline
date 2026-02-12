# Research Data Platform V2 - Deployment Guide

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Infrastructure Setup](#infrastructure-setup)
3. [Database Deployment](#database-deployment)
4. [ETL Pipeline Deployment](#etl-pipeline-deployment)
5. [API Service Deployment](#api-service-deployment)
6. [Monitoring Setup](#monitoring-setup)
7. [Validation & Testing](#validation--testing)
8. [Production Checklist](#production-checklist)

## Prerequisites

### Required Tools

```bash
# AWS CLI
aws --version  # Should be 2.x+

# Python
python --version  # Should be 3.9+

# Docker
docker --version  # Should be 20.x+

# Terraform (optional, for IaC)
terraform --version  # Should be 1.x+
```

### AWS Account Setup

1. **Create AWS Account** (if not exists)

2. **Configure AWS CLI**:
```bash
aws configure
# AWS Access Key ID: <your-key>
# AWS Secret Access Key: <your-secret>
# Default region: us-east-1
# Default output format: json
```

3. **Create IAM Roles**:

```bash
# Lambda execution role
aws iam create-role \
  --role-name ResearchPlatform-Lambda-Role \
  --assume-role-policy-document file://iam/lambda-trust-policy.json

aws iam attach-role-policy \
  --role-name ResearchPlatform-Lambda-Role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# Glue execution role
aws iam create-role \
  --role-name ResearchPlatform-Glue-Role \
  --assume-role-policy-document file://iam/glue-trust-policy.json

aws iam attach-role-policy \
  --role-name ResearchPlatform-Glue-Role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole
```

### Environment Variables

Create `.env` file:
```bash
# AWS Configuration
AWS_REGION=us-east-1
AWS_ACCOUNT_ID=123456789012

# Redshift Configuration
REDSHIFT_CLUSTER_ID=research-platform-cluster
REDSHIFT_DB=research_platform
REDSHIFT_USER=admin
REDSHIFT_PASSWORD=<secure-password>
REDSHIFT_HOST=<cluster-endpoint>
REDSHIFT_PORT=5439

# S3 Configuration
S3_DATA_LAKE_BUCKET=itus-data-lake
S3_QUARANTINE_BUCKET=itus-data-quarantine

# SNS Configuration
SNS_CRITICAL_ALERTS_TOPIC=arn:aws:sns:us-east-1:123456789012:research-platform-critical-alerts
SNS_DQ_ALERTS_TOPIC=arn:aws:sns:us-east-1:123456789012:research-platform-data-quality-alerts

# Redis Configuration
REDIS_HOST=research-platform-cache.abc123.0001.use1.cache.amazonaws.com
REDIS_PORT=6379

# API Configuration
API_PORT=8000
CACHE_TTL=86400
```

## Infrastructure Setup

### Step 1: Create S3 Data Lake

```bash
# Create main data lake bucket
aws s3 mb s3://itus-data-lake --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket itus-data-lake \
  --versioning-configuration Status=Enabled

# Create folder structure
aws s3api put-object --bucket itus-data-lake --key raw/prices/
aws s3api put-object --bucket itus-data-lake --key raw/financials/
aws s3api put-object --bucket itus-data-lake --key raw/flows/
aws s3api put-object --bucket itus-data-lake --key processed/
aws s3api put-object --bucket itus-data-lake --key archive/
aws s3api put-object --bucket itus-data-lake --key quarantine/

# Set up lifecycle policies
python infrastructure/cost_optimization.py
```

### Step 2: Create Redshift Cluster

```bash
# Create Redshift cluster
aws redshift create-cluster \
  --cluster-identifier research-platform-cluster \
  --node-type ra3.4xlarge \
  --number-of-nodes 2 \
  --master-username admin \
  --master-user-password <secure-password> \
  --db-name research_platform \
  --cluster-subnet-group-name default \
  --publicly-accessible false \
  --encrypted \
  --tags Key=Project,Value=ResearchDataPlatform

# Wait for cluster to be available
aws redshift wait cluster-available \
  --cluster-identifier research-platform-cluster

# Get cluster endpoint
aws redshift describe-clusters \
  --cluster-identifier research-platform-cluster \
  --query 'Clusters[0].Endpoint.Address' \
  --output text
```

### Step 3: Create Redis Cache

```bash
# Create ElastiCache Redis cluster
aws elasticache create-cache-cluster \
  --cache-cluster-id research-platform-cache \
  --cache-node-type cache.t3.medium \
  --engine redis \
  --num-cache-nodes 1 \
  --tags Key=Project,Value=ResearchDataPlatform

# Wait for cache to be available
aws elasticache wait cache-cluster-available \
  --cache-cluster-id research-platform-cache

# Get cache endpoint
aws elasticache describe-cache-clusters \
  --cache-cluster-id research-platform-cache \
  --show-cache-node-info \
  --query 'CacheClusters[0].CacheNodes[0].Endpoint.Address' \
  --output text
```

### Step 4: Set Up Networking

```bash
# Create security group for Redshift
aws ec2 create-security-group \
  --group-name research-platform-redshift-sg \
  --description "Security group for Research Platform Redshift cluster" \
  --vpc-id <vpc-id>

# Allow inbound from API service
aws ec2 authorize-security-group-ingress \
  --group-id <redshift-sg-id> \
  --protocol tcp \
  --port 5439 \
  --source-group <api-sg-id>

# Create security group for Redis
aws ec2 create-security-group \
  --group-name research-platform-redis-sg \
  --description "Security group for Research Platform Redis cache" \
  --vpc-id <vpc-id>

# Allow inbound from API service
aws ec2 authorize-security-group-ingress \
  --group-id <redis-sg-id> \
  --protocol tcp \
  --port 6379 \
  --source-group <api-sg-id>
```

## Database Deployment

### Step 1: Connect to Redshift

```bash
# Using psql
psql -h <redshift-endpoint> \
     -U admin \
     -d research_platform \
     -p 5439

# Or using Python
python
>>> import psycopg2
>>> conn = psycopg2.connect(
...     host='<redshift-endpoint>',
...     port=5439,
...     database='research_platform',
...     user='admin',
...     password='<password>'
... )
```

### Step 2: Create Schemas

```bash
cd redshift/schemas

# Execute schema creation scripts in order
psql -h <redshift-endpoint> -U admin -d research_platform -f 01_create_schemas.sql
psql -h <redshift-endpoint> -U admin -d research_platform -f 02_create_control_tables.sql
psql -h <redshift-endpoint> -U admin -d research_platform -f 03_create_dimension_tables.sql
psql -h <redshift-endpoint> -U admin -d research_platform -f 04_create_vault_tables.sql
psql -h <redshift-endpoint> -U admin -d research_platform -f 05_create_corporate_actions.sql
psql -h <redshift-endpoint> -U admin -d research_platform -f 06_create_fact_tables.sql
psql -h <redshift-endpoint> -U admin -d research_platform -f 07_create_materialized_views.sql
psql -h <redshift-endpoint> -U admin -d research_platform -f 08_create_udfs.sql
```

### Step 3: Populate Dimension Tables

```bash
# Populate dim_date
psql -h <redshift-endpoint> -U admin -d research_platform -f redshift/data/populate_dim_date.sql

# Load initial security master data
python scripts/load_security_master.py

# Load initial index constituents
python scripts/load_index_constituents.py
```

### Step 4: Configure WLM

```bash
# Update WLM configuration via AWS Console or CLI
aws redshift modify-cluster-parameter-group \
  --parameter-group-name research-platform-params \
  --parameters ParameterName=wlm_json_configuration,ParameterValue='[
    {
      "query_concurrency": 2,
      "memory_percent_to_use": 40,
      "query_group": ["etl"],
      "query_group_wild_card": 0,
      "user_group": ["etl_users"]
    },
    {
      "query_concurrency": 5,
      "memory_percent_to_use": 50,
      "query_group": ["analyst"],
      "query_group_wild_card": 0,
      "user_group": ["analyst_users"],
      "max_execution_time": 300000
    }
  ]'
```

## ETL Pipeline Deployment

### Step 1: Deploy Lambda Validators

```bash
cd lambda/validators

# Install dependencies
pip install -r requirements.txt -t package/

# Create deployment package
cd package
zip -r ../validator-deployment.zip .
cd ..
zip -g validator-deployment.zip price_validator.py financial_validator.py data_quality_rules.py

# Deploy price validator
aws lambda create-function \
  --function-name price-validator \
  --runtime python3.9 \
  --role arn:aws:iam::<account-id>:role/ResearchPlatform-Lambda-Role \
  --handler price_validator.lambda_handler \
  --zip-file fileb://validator-deployment.zip \
  --timeout 300 \
  --memory-size 512 \
  --environment Variables="{
    S3_QUARANTINE_BUCKET=itus-data-quarantine,
    SNS_TOPIC_ARN=<sns-topic-arn>
  }"

# Deploy financial validator
aws lambda create-function \
  --function-name financial-validator \
  --runtime python3.9 \
  --role arn:aws:iam::<account-id>:role/ResearchPlatform-Lambda-Role \
  --handler financial_validator.lambda_handler \
  --zip-file fileb://validator-deployment.zip \
  --timeout 300 \
  --memory-size 512

# Set up S3 event notifications
aws s3api put-bucket-notification-configuration \
  --bucket itus-data-lake \
  --notification-configuration file://s3-event-config.json
```

### Step 2: Deploy Glue ETL Jobs

```bash
cd glue

# Upload Glue scripts to S3
aws s3 cp daily_prices_etl.py s3://itus-data-lake/glue-scripts/
aws s3 cp quarterly_financials_etl.py s3://itus-data-lake/glue-scripts/
aws s3 cp daily_flows_etl.py s3://itus-data-lake/glue-scripts/

# Create Glue jobs
aws glue create-job \
  --name daily-prices-etl \
  --role arn:aws:iam::<account-id>:role/ResearchPlatform-Glue-Role \
  --command Name=glueetl,ScriptLocation=s3://itus-data-lake/glue-scripts/daily_prices_etl.py \
  --default-arguments '{
    "--job-bookmark-option": "job-bookmark-enable",
    "--TempDir": "s3://itus-data-lake/glue-temp/",
    "--enable-metrics": "",
    "--enable-continuous-cloudwatch-log": "true",
    "--REDSHIFT_CONNECTION": "research-platform-redshift"
  }' \
  --max-retries 2 \
  --timeout 60 \
  --glue-version "3.0"

# Create Glue triggers
aws glue create-trigger \
  --name daily-prices-trigger \
  --type SCHEDULED \
  --schedule "cron(0 2 * * ? *)" \
  --actions JobName=daily-prices-etl \
  --start-on-creation
```

## API Service Deployment

### Step 1: Build Docker Image

```bash
cd api

# Build image
docker build -t research-platform-api:latest .

# Test locally
docker run -p 8000:8000 \
  -e REDSHIFT_HOST=<endpoint> \
  -e REDSHIFT_USER=admin \
  -e REDSHIFT_PASSWORD=<password> \
  -e REDIS_HOST=<redis-endpoint> \
  research-platform-api:latest

# Test endpoint
curl http://localhost:8000/health
```

### Step 2: Push to ECR

```bash
# Create ECR repository
aws ecr create-repository \
  --repository-name research-platform-api \
  --region us-east-1

# Login to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com

# Tag image
docker tag research-platform-api:latest \
  <account-id>.dkr.ecr.us-east-1.amazonaws.com/research-platform-api:latest

# Push image
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/research-platform-api:latest
```

### Step 3: Deploy to ECS Fargate

```bash
# Create ECS cluster
aws ecs create-cluster \
  --cluster-name research-platform \
  --capacity-providers FARGATE \
  --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1

# Create task definition
aws ecs register-task-definition \
  --cli-input-json file://ecs/task-definition.json

# Create service
aws ecs create-service \
  --cluster research-platform \
  --service-name api-service \
  --task-definition research-platform-api:1 \
  --desired-count 2 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={
    subnets=[subnet-12345,subnet-67890],
    securityGroups=[sg-api],
    assignPublicIp=ENABLED
  }" \
  --load-balancers "targetGroupArn=<target-group-arn>,containerName=api,containerPort=8000"
```

## Monitoring Setup

### Step 1: Configure CloudWatch

```bash
cd infrastructure

# Set up log groups and metrics
python cloudwatch_config.py

# Set up alarms and SNS topics
python alerting_config.py \
  --operations-email ops@example.com \
  --redshift-cluster research-platform-cluster
```

### Step 2: Subscribe to Alerts

```bash
# Subscribe email to SNS topics
aws sns subscribe \
  --topic-arn <critical-alerts-topic-arn> \
  --protocol email \
  --notification-endpoint ops@example.com

# Confirm subscription via email
```

### Step 3: Set Up Cost Monitoring

```bash
# Set up cost optimization
python infrastructure/cost_optimization.py \
  --s3-bucket itus-data-lake \
  --monthly-budget 5000 \
  --sns-topic <cost-alerts-topic-arn>
```

## Validation & Testing

### Step 1: Test Data Ingestion

```bash
# Upload test data
aws s3 cp lambda/validators/test_data/valid_prices.csv \
  s3://itus-data-lake/raw/prices/2024/01/01/

# Check Lambda logs
aws logs tail /aws/lambda/price-validator --follow

# Check Glue job status
aws glue get-job-run \
  --job-name daily-prices-etl \
  --run-id <run-id>
```

### Step 2: Test API Endpoints

```bash
# Health check
curl https://api.research-platform.example.com/health

# Execute query
curl -X POST https://api.research-platform.example.com/api/v1/query/execute \
  -H "Content-Type: application/json" \
  -d '{
    "query": "SELECT COUNT(*) FROM fact_daily_prices",
    "timeout_seconds": 30
  }'

# Validate query
curl -X POST https://api.research-platform.example.com/api/v1/query/validate \
  -H "Content-Type: application/json" \
  -d '{
    "query": "SELECT * FROM fact_quarterly_financials WHERE publication_date <= '\''2024-01-01'\''",
    "as_of_date": "2024-01-01"
  }'
```

### Step 3: Test Data Quality

```bash
# Run data quality checks
python lambda/validators/data_quality_engine.py \
  --data-source prices \
  --file test_prices.csv

# Check quarantine bucket
aws s3 ls s3://itus-data-quarantine/quarantine/prices/
```

## Production Checklist

### Security

- [ ] Enable encryption at rest for S3, Redshift, Redis
- [ ] Enable encryption in transit (TLS 1.2+)
- [ ] Configure VPC security groups with least privilege
- [ ] Set up IAM roles with minimal permissions
- [ ] Enable MFA for AWS console access
- [ ] Rotate credentials regularly
- [ ] Enable CloudTrail for audit logging

### Performance

- [ ] Run ANALYZE on all tables
- [ ] Configure WLM queues
- [ ] Enable concurrency scaling
- [ ] Set up auto-scaling schedule
- [ ] Create materialized views
- [ ] Configure Redis cache
- [ ] Test query performance benchmarks

### Reliability

- [ ] Set up CloudWatch alarms
- [ ] Configure SNS notifications
- [ ] Test backup and restore procedures
- [ ] Document disaster recovery plan
- [ ] Set up cross-region replication (if needed)
- [ ] Test failover procedures

### Cost Optimization

- [ ] Set up S3 lifecycle policies
- [ ] Configure cluster pause schedule
- [ ] Enable cost allocation tags
- [ ] Set up budget alerts
- [ ] Review and optimize expensive queries
- [ ] Monitor concurrency scaling usage

### Documentation

- [ ] Document architecture
- [ ] Create runbooks for common operations
- [ ] Document troubleshooting procedures
- [ ] Create user guides for analysts
- [ ] Document API endpoints
- [ ] Create data dictionary

### Training

- [ ] Train operations team on monitoring
- [ ] Train analysts on query patterns
- [ ] Train developers on API usage
- [ ] Conduct disaster recovery drills

## Maintenance Procedures

### Daily

- Check CloudWatch dashboards
- Review data quality metrics
- Monitor query performance
- Check for failed ETL jobs

### Weekly

- Review cost reports
- Analyze slow queries
- Check storage growth
- Review security logs

### Monthly

- Run VACUUM on large tables
- Review and optimize WLM configuration
- Update documentation
- Review and update alarms

### Quarterly

- Review architecture for improvements
- Conduct disaster recovery test
- Review security policies
- Plan capacity upgrades
