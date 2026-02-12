# Lambda Validators

This directory contains Lambda functions for validating data files before they are processed by Glue ETL jobs.

## Validators

### 1. Price Validator (`price_validator.py`)

Validates daily price data files uploaded to `s3://bucket/raw/prices/`.

**Validations:**
- Schema validation (required columns present)
- Required fields non-null
- Date range validation (no future dates, no dates before 2000)
- Price validation (positive values, high >= low, close within [low, high])
- Statistical outlier detection (price changes > 50%)
- Duplicate detection

**Triggers:**
- S3 event: `ObjectCreated` on `raw/prices/*.csv`

### 2. Financial Validator (`financial_validator.py`)

Validates quarterly financial statement files uploaded to `s3://bucket/raw/financials/`.

**Validations:**
- Schema validation
- Required fields non-null
- Date validation
- Temporal consistency (publication_date >= reporting_period_end)
- Balance sheet equation (Assets = Liabilities + Equity, within 1% tolerance)
- Reasonable value ranges
- Duplicate detection

**Triggers:**
- S3 event: `ObjectCreated` on `raw/financials/*.csv`

## Deployment

### Prerequisites

1. Infrastructure deployed (Task 1 complete)
2. Python 3.11 installed
3. AWS CLI configured
4. pip installed

### Deploy

```bash
cd lambda/validators
chmod +x deploy.sh
./deploy.sh
```

This will:
1. Create deployment packages with dependencies
2. Deploy Lambda functions
3. Configure S3 event notifications
4. Create SQS Dead Letter Queue
5. Set up IAM permissions

### Verify Deployment

```bash
# List Lambda functions
aws lambda list-functions --query 'Functions[?contains(FunctionName, `research-platform`)].FunctionName'

# Check S3 notification configuration
aws s3api get-bucket-notification-configuration --bucket <bucket-name>

# View Lambda logs
aws logs tail /aws/lambda/research-platform-price-validator --follow
```

## Testing

### Test with Valid Data

```bash
# Get bucket name
BUCKET=$(cd ../../infrastructure/terraform && terraform output -raw s3_bucket_name)

# Upload valid price data
aws s3 cp test_data/valid_prices.csv s3://$BUCKET/raw/prices/2024/01/15/prices.csv

# Upload valid financial data
aws s3 cp test_data/valid_financials.csv s3://$BUCKET/raw/financials/2024/Q4/financials.csv

# Check Lambda logs
aws logs tail /aws/lambda/research-platform-price-validator --since 5m
```

Expected: Validation passes, file triggers ETL job (when implemented)

### Test with Invalid Data

```bash
# Upload invalid price data
aws s3 cp test_data/invalid_prices.csv s3://$BUCKET/raw/prices/2024/01/15/invalid.csv

# Check logs
aws logs tail /aws/lambda/research-platform-price-validator --since 5m

# Check quarantine folder
aws s3 ls s3://$BUCKET/quarantine/prices/

# Check Dead Letter Queue
aws sqs receive-message --queue-url <DLQ_URL>
```

Expected: Validation fails, file moved to quarantine, alert sent via SNS

## Validation Rules

### Price Data

| Rule | Type | Description |
|------|------|-------------|
| Schema | Error | All required columns must be present |
| Null Values | Error | security_id, price_date, prices cannot be null |
| Date Range | Error | No future dates, no dates before 2000 |
| Positive Prices | Error | All prices must be > 0 |
| Price Logic | Error | high >= low, close within [low, high] |
| Outliers | Warning | Price changes > 50% flagged for review |
| Duplicates | Warning | Same security + date flagged |

### Financial Data

| Rule | Type | Description |
|------|------|-------------|
| Schema | Error | All required columns must be present |
| Null Values | Error | security_id, dates cannot be null |
| Date Range | Error | No future reporting periods |
| Temporal | Error | publication_date >= reporting_period_end |
| Balance Sheet | Warning | Assets = Liabilities + Equity (1% tolerance) |
| Value Ranges | Warning | Values within reasonable bounds |
| Duplicates | Warning | Same security + period + publication date |

## Error Handling

### Validation Failure Flow

1. File fails validation
2. File copied to `s3://bucket/quarantine/`
3. Failure details sent to SQS Dead Letter Queue
4. SNS alert sent to operations team
5. Original file remains in `raw/` for manual review

### Dead Letter Queue

Failed validations are sent to SQS DLQ with:
```json
{
  "bucket": "bucket-name",
  "key": "raw/prices/file.csv",
  "validation_result": {
    "valid": false,
    "errors": ["List of errors"],
    "warnings": ["List of warnings"]
  },
  "timestamp": "2024-01-15T10:30:00Z"
}
```

### Monitoring

CloudWatch Logs:
- `/aws/lambda/research-platform-price-validator`
- `/aws/lambda/research-platform-financial-validator`

CloudWatch Metrics:
- Invocations
- Errors
- Duration
- Throttles

SNS Alerts sent for:
- Validation failures
- Lambda errors
- Unexpected exceptions

## Configuration

### Environment Variables

Both Lambda functions use:
- `SNS_TOPIC_ARN`: SNS topic for alerts
- `DLQ_URL`: SQS Dead Letter Queue URL

### Timeouts and Memory

- Timeout: 300 seconds (5 minutes)
- Memory: 512 MB
- Runtime: Python 3.11

### IAM Permissions

Lambda execution role needs:
- S3: GetObject, PutObject, ListBucket
- SNS: Publish
- SQS: SendMessage
- CloudWatch Logs: CreateLogGroup, CreateLogStream, PutLogEvents

## Troubleshooting

### Lambda Not Triggered

1. Check S3 event notification configuration
2. Verify Lambda has permission to be invoked by S3
3. Check file path matches trigger prefix/suffix

### Validation Errors

1. Check CloudWatch Logs for detailed error messages
2. Download file from S3 and validate locally
3. Check file format (CSV, UTF-8 encoding)
4. Verify column names match exactly

### High Costs

1. Review Lambda invocation count
2. Check for large files causing long execution times
3. Consider increasing memory for faster execution
4. Implement file size limits

## Next Steps

After validators are deployed:
1. Proceed to Task 2.2: Create Glue ETL jobs
2. Implement ETL job triggering from validators
3. Set up monitoring dashboard
4. Create runbook for handling validation failures
