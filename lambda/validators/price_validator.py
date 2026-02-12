"""
Lambda function to validate price data files before processing.
Validates schema, data quality, and detects statistical outliers.
"""

import json
import boto3
import pandas as pd
from io import StringIO
from datetime import datetime
from typing import Dict, List, Tuple

s3_client = boto3.client('s3')
sns_client = boto3.client('sns')
sqs_client = boto3.client('sqs')

# Configuration
REQUIRED_COLUMNS = ['security_id', 'price_date', 'open', 'high', 'low', 'close', 'volume']
MAX_PRICE_CHANGE_PCT = 0.50  # 50% max price change
SNS_TOPIC_ARN = None  # Set via environment variable
DLQ_URL = None  # Set via environment variable


def lambda_handler(event, context):
    """Main Lambda handler for S3 event notifications."""
    
    # Get SNS and SQS from environment
    global SNS_TOPIC_ARN, DLQ_URL
    SNS_TOPIC_ARN = context.get('SNS_TOPIC_ARN')
    DLQ_URL = context.get('DLQ_URL')
    
    try:
        # Parse S3 event
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = record['s3']['object']['key']
            
            # Only process files in raw/prices/
            if not key.startswith('raw/prices/'):
                continue
            
            print(f"Validating file: s3://{bucket}/{key}")
            
            # Download and validate file
            validation_result = validate_price_file(bucket, key)
            
            if validation_result['valid']:
                print(f"✓ Validation passed: {key}")
                # Trigger Glue ETL job (will be implemented in Task 2.2)
                trigger_etl_job(bucket, key)
            else:
                print(f"✗ Validation failed: {key}")
                handle_validation_failure(bucket, key, validation_result)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Validation complete')
        }
    
    except Exception as e:
        print(f"Error in lambda_handler: {str(e)}")
        send_alert(f"Lambda validation error: {str(e)}")
        raise


def validate_price_file(bucket: str, key: str) -> Dict:
    """
    Validate price data file.
    
    Returns:
        Dict with 'valid' boolean and 'errors' list
    """
    errors = []
    warnings = []
    
    try:
        # Download file from S3
        response = s3_client.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        
        # Parse CSV
        df = pd.read_csv(StringIO(content))
        
        # Validation 1: Schema validation
        schema_errors = validate_schema(df)
        errors.extend(schema_errors)
        
        if schema_errors:
            # If schema is invalid, can't proceed with other validations
            return {'valid': False, 'errors': errors, 'warnings': warnings}
        
        # Validation 2: Required fields non-null
        null_errors = validate_required_fields(df)
        errors.extend(null_errors)
        
        # Validation 3: Date range validation
        date_errors = validate_date_range(df)
        errors.extend(date_errors)
        
        # Validation 4: Price validation (positive values)
        price_errors = validate_prices(df)
        errors.extend(price_errors)
        
        # Validation 5: Statistical outlier detection
        outlier_warnings = detect_price_outliers(df)
        warnings.extend(outlier_warnings)
        
        # Validation 6: Referential integrity (security IDs)
        # Note: This would check against dim_security table in production
        ref_warnings = validate_security_ids(df)
        warnings.extend(ref_warnings)
        
        return {
            'valid': len(errors) == 0,
            'errors': errors,
            'warnings': warnings,
            'record_count': len(df)
        }
    
    except Exception as e:
        return {
            'valid': False,
            'errors': [f"File parsing error: {str(e)}"],
            'warnings': []
        }


def validate_schema(df: pd.DataFrame) -> List[str]:
    """Validate that all required columns are present."""
    errors = []
    
    missing_columns = set(REQUIRED_COLUMNS) - set(df.columns)
    if missing_columns:
        errors.append(f"Missing required columns: {', '.join(missing_columns)}")
    
    return errors


def validate_required_fields(df: pd.DataFrame) -> List[str]:
    """Check for null values in required fields."""
    errors = []
    
    for col in REQUIRED_COLUMNS:
        null_count = df[col].isnull().sum()
        if null_count > 0:
            errors.append(f"Column '{col}' has {null_count} null values")
    
    return errors


def validate_date_range(df: pd.DataFrame) -> List[str]:
    """Validate that dates are within expected bounds."""
    errors = []
    
    try:
        df['price_date'] = pd.to_datetime(df['price_date'])
        
        min_date = df['price_date'].min()
        max_date = df['price_date'].max()
        today = pd.Timestamp.now()
        
        # Check for future dates
        if max_date > today:
            errors.append(f"Found future dates: max date is {max_date}")
        
        # Check for very old dates (before 2000)
        if min_date < pd.Timestamp('2000-01-01'):
            errors.append(f"Found dates before 2000: min date is {min_date}")
    
    except Exception as e:
        errors.append(f"Date parsing error: {str(e)}")
    
    return errors


def validate_prices(df: pd.DataFrame) -> List[str]:
    """Validate that prices are positive and logical."""
    errors = []
    
    price_columns = ['open', 'high', 'low', 'close']
    
    for col in price_columns:
        # Check for negative prices
        negative_count = (df[col] <= 0).sum()
        if negative_count > 0:
            errors.append(f"Column '{col}' has {negative_count} non-positive values")
        
        # Check for extremely high prices (> 1 million)
        extreme_count = (df[col] > 1000000).sum()
        if extreme_count > 0:
            errors.append(f"Column '{col}' has {extreme_count} extremely high values (>1M)")
    
    # Validate high >= low
    invalid_range = (df['high'] < df['low']).sum()
    if invalid_range > 0:
        errors.append(f"Found {invalid_range} records where high < low")
    
    # Validate close within [low, high]
    invalid_close = ((df['close'] < df['low']) | (df['close'] > df['high'])).sum()
    if invalid_close > 0:
        errors.append(f"Found {invalid_close} records where close is outside [low, high]")
    
    return errors


def detect_price_outliers(df: pd.DataFrame) -> List[str]:
    """Detect statistical outliers in price changes."""
    warnings = []
    
    try:
        # Sort by security and date
        df = df.sort_values(['security_id', 'price_date'])
        
        # Calculate day-over-day price change
        df['prev_close'] = df.groupby('security_id')['close'].shift(1)
        df['pct_change'] = (df['close'] - df['prev_close']) / df['prev_close']
        
        # Find outliers (>50% change)
        outliers = df[df['pct_change'].abs() > MAX_PRICE_CHANGE_PCT]
        
        if len(outliers) > 0:
            outlier_details = []
            for _, row in outliers.head(10).iterrows():  # Limit to first 10
                outlier_details.append(
                    f"{row['security_id']} on {row['price_date']}: "
                    f"{row['pct_change']*100:.1f}% change"
                )
            
            warnings.append(
                f"Found {len(outliers)} price changes > {MAX_PRICE_CHANGE_PCT*100}%. "
                f"Examples: {'; '.join(outlier_details)}"
            )
    
    except Exception as e:
        warnings.append(f"Outlier detection error: {str(e)}")
    
    return warnings


def validate_security_ids(df: pd.DataFrame) -> List[str]:
    """Validate security IDs format."""
    warnings = []
    
    # Check for empty security IDs
    empty_ids = df['security_id'].isnull().sum()
    if empty_ids > 0:
        warnings.append(f"Found {empty_ids} empty security IDs")
    
    # Check for duplicate records (same security + date)
    duplicates = df.duplicated(subset=['security_id', 'price_date']).sum()
    if duplicates > 0:
        warnings.append(f"Found {duplicates} duplicate records (same security + date)")
    
    return warnings


def handle_validation_failure(bucket: str, key: str, validation_result: Dict):
    """Handle validation failure by moving file to quarantine and alerting."""
    
    # Move file to quarantine
    quarantine_key = key.replace('raw/', 'quarantine/')
    s3_client.copy_object(
        Bucket=bucket,
        CopySource={'Bucket': bucket, 'Key': key},
        Key=quarantine_key
    )
    
    # Send to dead letter queue
    if DLQ_URL:
        sqs_client.send_message(
            QueueUrl=DLQ_URL,
            MessageBody=json.dumps({
                'bucket': bucket,
                'key': key,
                'validation_result': validation_result,
                'timestamp': datetime.utcnow().isoformat()
            })
        )
    
    # Send alert
    error_summary = '\n'.join(validation_result['errors'])
    send_alert(
        f"Price data validation failed\n"
        f"File: s3://{bucket}/{key}\n"
        f"Errors:\n{error_summary}"
    )


def trigger_etl_job(bucket: str, key: str):
    """Trigger Glue ETL job for valid file."""
    # This will be implemented in Task 2.2
    print(f"Would trigger ETL job for: s3://{bucket}/{key}")
    pass


def send_alert(message: str):
    """Send alert via SNS."""
    if SNS_TOPIC_ARN:
        try:
            sns_client.publish(
                TopicArn=SNS_TOPIC_ARN,
                Subject='Research Platform: Data Validation Alert',
                Message=message
            )
        except Exception as e:
            print(f"Failed to send SNS alert: {str(e)}")
