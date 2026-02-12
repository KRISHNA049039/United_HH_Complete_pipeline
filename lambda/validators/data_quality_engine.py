"""
Data Quality Engine for Research Data Platform
Executes validation rules and manages quarantine/alerting
"""

import pandas as pd
import boto3
import json
from typing import List, Dict, Any
from datetime import datetime
from data_quality_rules import DataQualityRule, ValidationResult

class DataQualityEngine:
    """
    Orchestrates data quality validation
    
    Features:
    - Execute multiple validation rules
    - Quarantine failed data
    - Send SNS alerts for critical failures
    - Log results to control tables
    """
    
    def __init__(self, 
                 s3_quarantine_bucket: str = None,
                 sns_topic_arn: str = None,
                 redshift_conn = None):
        """
        Initialize data quality engine
        
        Args:
            s3_quarantine_bucket: S3 bucket for quarantined data
            sns_topic_arn: SNS topic for alerts
            redshift_conn: Redshift connection for logging
        """
        self.s3_quarantine_bucket = s3_quarantine_bucket
        self.sns_topic_arn = sns_topic_arn
        self.redshift_conn = redshift_conn
        
        # AWS clients
        self.s3_client = boto3.client('s3') if s3_quarantine_bucket else None
        self.sns_client = boto3.client('sns') if sns_topic_arn else None
        
        # Results storage
        self.validation_results: List[ValidationResult] = []
    
    def execute_rules(self, 
                     df: pd.DataFrame, 
                     rules: List[DataQualityRule],
                     context: Dict[str, Any] = None) -> Dict[str, Any]:
        """
        Execute all validation rules on dataframe
        
        Args:
            df: DataFrame to validate
            rules: List of validation rules to execute
            context: Additional context for rules (e.g., corporate actions)
            
        Returns:
            Summary of validation results
        """
        self.validation_results = []
        
        for rule in rules:
            try:
                result = rule.validate(df, context)
                self.validation_results.append(result)
            except Exception as e:
                # Log rule execution error
                error_result = ValidationResult(
                    rule_name=rule.name,
                    status="ERROR",
                    message=f"Rule execution failed: {str(e)}",
                    failed_count=1,
                    total_count=1
                )
                self.validation_results.append(error_result)
        
        # Calculate summary
        summary = self._calculate_summary()
        
        return summary

    
    def _calculate_summary(self) -> Dict[str, Any]:
        """Calculate summary statistics from validation results"""
        total_rules = len(self.validation_results)
        passed = sum(1 for r in self.validation_results if r.status == "PASS")
        failed = sum(1 for r in self.validation_results if r.status == "FAIL")
        warnings = sum(1 for r in self.validation_results if r.status == "WARNING")
        errors = sum(1 for r in self.validation_results if r.status == "ERROR")
        
        pass_rate = (passed / total_rules * 100) if total_rules > 0 else 0
        
        return {
            "total_rules": total_rules,
            "passed": passed,
            "failed": failed,
            "warnings": warnings,
            "errors": errors,
            "pass_rate": round(pass_rate, 2),
            "timestamp": datetime.now().isoformat()
        }
    
    def quarantine_failed_data(self, 
                               df: pd.DataFrame,
                               data_source: str,
                               file_name: str) -> List[str]:
        """
        Quarantine data that failed validation
        
        Args:
            df: Original dataframe
            data_source: Source identifier (e.g., 'prices', 'financials')
            file_name: Original file name
            
        Returns:
            List of S3 keys for quarantined files
        """
        if not self.s3_client or not self.s3_quarantine_bucket:
            print("S3 quarantine not configured, skipping")
            return []
        
        quarantined_keys = []
        
        for result in self.validation_results:
            if result.status == "FAIL" and result.failed_records is not None:
                # Create quarantine file
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                s3_key = f"quarantine/{data_source}/{result.rule_name}/{timestamp}_{file_name}"
                
                # Convert to CSV
                csv_buffer = result.failed_records.to_csv(index=False)
                
                # Upload to S3
                self.s3_client.put_object(
                    Bucket=self.s3_quarantine_bucket,
                    Key=s3_key,
                    Body=csv_buffer,
                    Metadata={
                        'rule_name': result.rule_name,
                        'failed_count': str(result.failed_count),
                        'original_file': file_name,
                        'timestamp': timestamp
                    }
                )
                
                quarantined_keys.append(s3_key)
                print(f"Quarantined {result.failed_count} records to s3://{self.s3_quarantine_bucket}/{s3_key}")
        
        return quarantined_keys
    
    def send_alerts(self, 
                   data_source: str,
                   file_name: str,
                   summary: Dict[str, Any],
                   critical_threshold: float = 95.0):
        """
        Send SNS alerts for critical failures
        
        Args:
            data_source: Source identifier
            file_name: File name
            summary: Validation summary
            critical_threshold: Pass rate below which to alert (default 95%)
        """
        if not self.sns_client or not self.sns_topic_arn:
            print("SNS alerts not configured, skipping")
            return
        
        pass_rate = summary['pass_rate']
        
        # Determine if alert is needed
        is_critical = pass_rate < critical_threshold or summary['failed'] > 0
        
        if is_critical:
            # Build alert message
            failed_rules = [r for r in self.validation_results if r.status == "FAIL"]
            
            message = f"""
Data Quality Alert - {data_source}

File: {file_name}
Timestamp: {summary['timestamp']}

Summary:
- Pass Rate: {pass_rate}%
- Total Rules: {summary['total_rules']}
- Passed: {summary['passed']}
- Failed: {summary['failed']}
- Warnings: {summary['warnings']}

Failed Rules:
"""
            for result in failed_rules:
                message += f"\n- {result.rule_name}: {result.message}"
            
            message += "\n\nAction Required: Review quarantined data and investigate failures."
            
            # Send SNS notification
            self.sns_client.publish(
                TopicArn=self.sns_topic_arn,
                Subject=f"Data Quality Alert: {data_source} - Pass Rate {pass_rate}%",
                Message=message
            )
            
            print(f"Alert sent to SNS topic: {self.sns_topic_arn}")

    
    def log_results_to_redshift(self, 
                               data_source: str,
                               file_name: str,
                               summary: Dict[str, Any]):
        """
        Log validation results to Redshift control table
        
        Args:
            data_source: Source identifier
            file_name: File name
            summary: Validation summary
        """
        if not self.redshift_conn:
            print("Redshift connection not configured, skipping logging")
            return
        
        try:
            cursor = self.redshift_conn.cursor()
            
            # Insert summary record
            cursor.execute("""
                INSERT INTO control.data_quality_results (
                    data_source,
                    file_name,
                    validation_timestamp,
                    total_rules,
                    passed_rules,
                    failed_rules,
                    warning_rules,
                    pass_rate_pct
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            """, (
                data_source,
                file_name,
                summary['timestamp'],
                summary['total_rules'],
                summary['passed'],
                summary['failed'],
                summary['warnings'],
                summary['pass_rate']
            ))
            
            # Insert detail records for each rule
            for result in self.validation_results:
                cursor.execute("""
                    INSERT INTO control.data_quality_rule_details (
                        data_source,
                        file_name,
                        validation_timestamp,
                        rule_name,
                        rule_status,
                        message,
                        failed_count,
                        total_count
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                """, (
                    data_source,
                    file_name,
                    summary['timestamp'],
                    result.rule_name,
                    result.status,
                    result.message,
                    result.failed_count,
                    result.total_count
                ))
            
            self.redshift_conn.commit()
            print(f"Logged {len(self.validation_results)} validation results to Redshift")
            
        except Exception as e:
            print(f"Error logging to Redshift: {e}")
            self.redshift_conn.rollback()
    
    def validate_and_process(self,
                            df: pd.DataFrame,
                            rules: List[DataQualityRule],
                            data_source: str,
                            file_name: str,
                            context: Dict[str, Any] = None) -> Dict[str, Any]:
        """
        Complete validation workflow: execute, quarantine, alert, log
        
        Args:
            df: DataFrame to validate
            rules: Validation rules
            data_source: Source identifier
            file_name: File name
            context: Additional context
            
        Returns:
            Validation summary with actions taken
        """
        # Execute validation rules
        summary = self.execute_rules(df, rules, context)
        
        # Quarantine failed data
        quarantined_keys = self.quarantine_failed_data(df, data_source, file_name)
        summary['quarantined_files'] = quarantined_keys
        
        # Send alerts if needed
        self.send_alerts(data_source, file_name, summary)
        
        # Log to Redshift
        self.log_results_to_redshift(data_source, file_name, summary)
        
        return summary
    
    def get_results(self) -> List[ValidationResult]:
        """Get all validation results"""
        return self.validation_results
    
    def get_failed_results(self) -> List[ValidationResult]:
        """Get only failed validation results"""
        return [r for r in self.validation_results if r.status == "FAIL"]
