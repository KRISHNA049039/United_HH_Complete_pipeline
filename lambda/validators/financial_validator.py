"""
Lambda function to validate financial statement files before processing.
Validates schema, referential integrity, and business rules.
"""

import json
import boto3
import pandas as pd
from io import StringIO
from datetime import datetime
from typing import Dict, List

s3_client = boto3.client('s3')
sns_client = boto3.client('sns')
sqs_client = boto3.client('sqs')

# Configuration
REQUIRED_COLUMNS = [
    'security_id', 'reporting_period_end', 'publication_date',
    'revenue', 'ebitda', 'net_income', 'total_assets', 'total_equity'
]

BALANCE_SHEET_COLUMNS = ['total_assets', 'total_liabilities', 'total_equity']
SNS_TOPIC_ARN = None
DLQ_URL = None


def lambda_handler(event, context):
    """Main Lambda handler for S3 event notifications."""
    
    global SNS_TOPIC_ARN, DLQ_URL
    SNS_TOPIC_ARN = context.get('SNS_TOPIC_ARN')
    DLQ_URL = context.get('DLQ_URL')
    
    try:
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = record['s3']['object']['key']
            
            # Only process files in raw/financials/
            if not key.startswith('raw/financials/'):
                continue
            
            print(f"Validating file: s3://{bucket}/{key}")
            
            validation_result = validate_financial_file(bucket, key)
            
            if validation_result['valid']:
                print(f"✓ Validation passed: {key}")
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


def validate_financial_file(bucket: str, key: str) -> Dict:
    """Validate financial statement file."""
    errors = []
    warnings = []
    
    try:
        # Download file
        response = s3_client.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        df = pd.read_csv(StringIO(content))
        
        # Validation 1: Schema validation
        schema_errors = validate_schema(df)
        errors.extend(schema_errors)
        
        if schema_errors:
            return {'valid': False, 'errors': errors, 'warnings': warnings}
        
        # Validation 2: Required fields non-null
        null_errors = validate_required_fields(df)
        errors.extend(null_errors)
        
        # Validation 3: Date validation
        date_errors = validate_dates(df)
        errors.extend(date_errors)
        
        # Validation 4: Temporal consistency (publication_date >= reporting_period_end)
        temporal_errors = validate_temporal_consistency(df)
        errors.extend(temporal_errors)
        
        # Validation 5: Balance sheet equation
        balance_warnings = validate_balance_sheet(df)
        warnings.extend(balance_warnings)
        
        # Validation 6: Reasonable value ranges
        range_warnings = validate_value_ranges(df)
        warnings.extend(range_warnings)
        
        # Validation 7: Duplicate detection
        duplicate_warnings = check_duplicates(df)
        warnings.extend(duplicate_warnings)
        
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
    """Validate schema."""
    errors = []
    
    missing_columns = set(REQUIRED_COLUMNS) - set(df.columns)
    if missing_columns:
        errors.append(f"Missing required columns: {', '.join(missing_columns)}")
    
    return errors


def validate_required_fields(df: pd.DataFrame) -> List[str]:
    """Check for null values in critical fields."""
    errors = []
    
    critical_fields = ['security_id', 'reporting_period_end', 'publication_date']
    
    for col in critical_fields:
        null_count = df[col].isnull().sum()
        if null_count > 0:
            errors.append(f"Column '{col}' has {null_count} null values")
    
    return errors


def validate_dates(df: pd.DataFrame) -> List[str]:
    """Validate date fields."""
    errors = []
    
    try:
        df['reporting_period_end'] = pd.to_datetime(df['reporting_period_end'])
        df['publication_date'] = pd.to_datetime(df['publication_date'])
        
        # Check for future reporting periods
        today = pd.Timestamp.now()
        future_periods = (df['reporting_period_end'] > today).sum()
        if future_periods > 0:
            errors.append(f"Found {future_periods} future reporting periods")
        
        # Check for very old dates
        old_dates = (df['reporting_period_end'] < pd.Timestamp('1990-01-01')).sum()
        if old_dates > 0:
            errors.append(f"Found {old_dates} reporting periods before 1990")
    
    except Exception as e:
        errors.append(f"Date parsing error: {str(e)}")
    
    return errors


def validate_temporal_consistency(df: pd.DataFrame) -> List[str]:
    """Validate that publication_date >= reporting_period_end."""
    errors = []
    
    try:
        df['reporting_period_end'] = pd.to_datetime(df['reporting_period_end'])
        df['publication_date'] = pd.to_datetime(df['publication_date'])
        
        invalid_temporal = (df['publication_date'] < df['reporting_period_end']).sum()
        if invalid_temporal > 0:
            errors.append(
                f"Found {invalid_temporal} records where publication_date < reporting_period_end"
            )
    
    except Exception as e:
        errors.append(f"Temporal validation error: {str(e)}")
    
    return errors


def validate_balance_sheet(df: pd.DataFrame) -> List[str]:
    """Validate balance sheet equation: Assets = Liabilities + Equity."""
    warnings = []
    
    if not all(col in df.columns for col in BALANCE_SHEET_COLUMNS):
        return warnings  # Skip if columns not present
    
    try:
        # Calculate difference
        df['balance_diff'] = df['total_assets'] - (df['total_liabilities'] + df['total_equity'])
        df['balance_diff_pct'] = df['balance_diff'].abs() / df['total_assets']
        
        # Allow 1% tolerance for rounding
        imbalanced = df[df['balance_diff_pct'] > 0.01]
        
        if len(imbalanced) > 0:
            examples = []
            for _, row in imbalanced.head(5).iterrows():
                examples.append(
                    f"{row['security_id']} ({row['reporting_period_end']}): "
                    f"diff={row['balance_diff']:.2f}"
                )
            
            warnings.append(
                f"Found {len(imbalanced)} records with balance sheet imbalance > 1%. "
                f"Examples: {'; '.join(examples)}"
            )
    
    except Exception as e:
        warnings.append(f"Balance sheet validation error: {str(e)}")
    
    return warnings


def validate_value_ranges(df: pd.DataFrame) -> List[str]:
    """Validate that financial values are within reasonable ranges."""
    warnings = []
    
    financial_columns = ['revenue', 'ebitda', 'net_income', 'total_assets', 'total_equity']
    
    for col in financial_columns:
        if col not in df.columns:
            continue
        
        # Check for extremely large values (> 1 trillion)
        extreme_high = (df[col].abs() > 1e12).sum()
        if extreme_high > 0:
            warnings.append(f"Column '{col}' has {extreme_high} extremely large values (>1T)")
        
        # Check for negative assets or equity (usually invalid)
        if col in ['total_assets', 'total_equity']:
            negative_count = (df[col] < 0).sum()
            if negative_count > 0:
                warnings.append(f"Column '{col}' has {negative_count} negative values")
    
    return warnings


def check_duplicates(df: pd.DataFrame) -> List[str]:
    """Check for duplicate records."""
    warnings = []
    
    # Check for exact duplicates (same security + reporting period + publication date)
    duplicates = df.duplicated(
        subset=['security_id', 'reporting_period_end', 'publication_date']
    ).sum()
    
    if duplicates > 0:
        warnings.append(
            f"Found {duplicates} duplicate records "
            f"(same security + reporting period + publication date)"
        )
    
    return warnings


def handle_validation_failure(bucket: str, key: str, validation_result: Dict):
    """Handle validation failure."""
    
    # Move to quarantine
    quarantine_key = key.replace('raw/', 'quarantine/')
    s3_client.copy_object(
        Bucket=bucket,
        CopySource={'Bucket': bucket, 'Key': key},
        Key=quarantine_key
    )
    
    # Send to DLQ
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
        f"Financial data validation failed\n"
        f"File: s3://{bucket}/{key}\n"
        f"Errors:\n{error_summary}"
    )


def trigger_etl_job(bucket: str, key: str):
    """Trigger Glue ETL job."""
    print(f"Would trigger ETL job for: s3://{bucket}/{key}")
    pass


def send_alert(message: str):
    """Send alert via SNS."""
    if SNS_TOPIC_ARN:
        try:
            sns_client.publish(
                TopicArn=SNS_TOPIC_ARN,
                Subject='Research Platform: Financial Data Validation Alert',
                Message=message
            )
        except Exception as e:
            print(f"Failed to send SNS alert: {str(e)}")
