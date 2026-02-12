#!/bin/bash

# Lambda Validators Deployment Script

set -e

echo "========================================="
echo "Deploying Lambda Validators"
echo "========================================="
echo ""

# Configuration
LAMBDA_ROLE_ARN=$(cd ../../infrastructure/terraform && terraform output -raw iam_role_arns | jq -r '.lambda')
SNS_TOPIC_ARN=$(cd ../../infrastructure/terraform && terraform output -raw sns_topic_arn)
REGION="ap-south-1"

# Create deployment packages
echo "Creating deployment packages..."

# Price Validator
echo "  - price_validator"
mkdir -p build/price_validator
cp price_validator.py build/price_validator/
pip install -r requirements.txt -t build/price_validator/ --quiet
cd build/price_validator
zip -r ../price_validator.zip . > /dev/null
cd ../..

# Financial Validator
echo "  - financial_validator"
mkdir -p build/financial_validator
cp financial_validator.py build/financial_validator/
pip install -r requirements.txt -t build/financial_validator/ --quiet
cd build/financial_validator
zip -r ../financial_validator.zip . > /dev/null
cd ../..

echo "✓ Deployment packages created"
echo ""

# Deploy Lambda functions
echo "Deploying Lambda functions..."

# Price Validator
echo "  - Deploying price_validator..."
aws lambda create-function \
    --function-name research-platform-price-validator \
    --runtime python3.11 \
    --role $LAMBDA_ROLE_ARN \
    --handler price_validator.lambda_handler \
    --zip-file fileb://build/price_validator.zip \
    --timeout 300 \
    --memory-size 512 \
    --environment "Variables={SNS_TOPIC_ARN=$SNS_TOPIC_ARN}" \
    --region $REGION \
    2>/dev/null || \
aws lambda update-function-code \
    --function-name research-platform-price-validator \
    --zip-file fileb://build/price_validator.zip \
    --region $REGION > /dev/null

# Financial Validator
echo "  - Deploying financial_validator..."
aws lambda create-function \
    --function-name research-platform-financial-validator \
    --runtime python3.11 \
    --role $LAMBDA_ROLE_ARN \
    --handler financial_validator.lambda_handler \
    --zip-file fileb://build/financial_validator.zip \
    --timeout 300 \
    --memory-size 512 \
    --environment "Variables={SNS_TOPIC_ARN=$SNS_TOPIC_ARN}" \
    --region $REGION \
    2>/dev/null || \
aws lambda update-function-code \
    --function-name research-platform-financial-validator \
    --zip-file fileb://build/financial_validator.zip \
    --region $REGION > /dev/null

echo "✓ Lambda functions deployed"
echo ""

# Configure S3 event notifications
echo "Configuring S3 event notifications..."

BUCKET_NAME=$(cd ../../infrastructure/terraform && terraform output -raw s3_bucket_name)

# Get Lambda ARNs
PRICE_LAMBDA_ARN=$(aws lambda get-function --function-name research-platform-price-validator --region $REGION --query 'Configuration.FunctionArn' --output text)
FINANCIAL_LAMBDA_ARN=$(aws lambda get-function --function-name research-platform-financial-validator --region $REGION --query 'Configuration.FunctionArn' --output text)

# Grant S3 permission to invoke Lambda
aws lambda add-permission \
    --function-name research-platform-price-validator \
    --statement-id s3-invoke-price-validator \
    --action lambda:InvokeFunction \
    --principal s3.amazonaws.com \
    --source-arn arn:aws:s3:::$BUCKET_NAME \
    --region $REGION \
    2>/dev/null || echo "  Permission already exists for price_validator"

aws lambda add-permission \
    --function-name research-platform-financial-validator \
    --statement-id s3-invoke-financial-validator \
    --action lambda:InvokeFunction \
    --principal s3.amazonaws.com \
    --source-arn arn:aws:s3:::$BUCKET_NAME \
    --region $REGION \
    2>/dev/null || echo "  Permission already exists for financial_validator"

# Create S3 notification configuration
cat > /tmp/s3-notification.json <<EOF
{
  "LambdaFunctionConfigurations": [
    {
      "Id": "price-data-validation",
      "LambdaFunctionArn": "$PRICE_LAMBDA_ARN",
      "Events": ["s3:ObjectCreated:*"],
      "Filter": {
        "Key": {
          "FilterRules": [
            {
              "Name": "prefix",
              "Value": "raw/prices/"
            },
            {
              "Name": "suffix",
              "Value": ".csv"
            }
          ]
        }
      }
    },
    {
      "Id": "financial-data-validation",
      "LambdaFunctionArn": "$FINANCIAL_LAMBDA_ARN",
      "Events": ["s3:ObjectCreated:*"],
      "Filter": {
        "Key": {
          "FilterRules": [
            {
              "Name": "prefix",
              "Value": "raw/financials/"
            },
            {
              "Name": "suffix",
              "Value": ".csv"
            }
          ]
        }
      }
    }
  ]
}
EOF

aws s3api put-bucket-notification-configuration \
    --bucket $BUCKET_NAME \
    --notification-configuration file:///tmp/s3-notification.json

echo "✓ S3 event notifications configured"
echo ""

# Create SQS Dead Letter Queue
echo "Creating SQS Dead Letter Queue..."

DLQ_URL=$(aws sqs create-queue \
    --queue-name research-platform-validation-dlq \
    --region $REGION \
    --query 'QueueUrl' \
    --output text 2>/dev/null || \
aws sqs get-queue-url \
    --queue-name research-platform-validation-dlq \
    --region $REGION \
    --query 'QueueUrl' \
    --output text)

echo "✓ DLQ created: $DLQ_URL"
echo ""

# Update Lambda environment with DLQ URL
aws lambda update-function-configuration \
    --function-name research-platform-price-validator \
    --environment "Variables={SNS_TOPIC_ARN=$SNS_TOPIC_ARN,DLQ_URL=$DLQ_URL}" \
    --region $REGION > /dev/null

aws lambda update-function-configuration \
    --function-name research-platform-financial-validator \
    --environment "Variables={SNS_TOPIC_ARN=$SNS_TOPIC_ARN,DLQ_URL=$DLQ_URL}" \
    --region $REGION > /dev/null

# Cleanup
rm -rf build/
rm /tmp/s3-notification.json

echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo ""
echo "Lambda Functions:"
echo "  - research-platform-price-validator"
echo "  - research-platform-financial-validator"
echo ""
echo "S3 Triggers:"
echo "  - raw/prices/*.csv → price_validator"
echo "  - raw/financials/*.csv → financial_validator"
echo ""
echo "Dead Letter Queue:"
echo "  - $DLQ_URL"
echo ""
echo "Test by uploading a CSV file to S3:"
echo "  aws s3 cp test_prices.csv s3://$BUCKET_NAME/raw/prices/"
