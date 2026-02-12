"""
Cost Optimization Strategies for Research Data Platform
Implements S3 lifecycle policies, data compression, and cost monitoring
"""

import boto3
from datetime import datetime, timedelta
from typing import Dict, List

class CostOptimizer:
    """Implements cost optimization strategies"""
    
    def __init__(self, region: str = 'us-east-1'):
        self.s3_client = boto3.client('s3', region_name=region)
        self.cloudwatch_client = boto3.client('cloudwatch', region_name=region)
        self.ce_client = boto3.client('ce', region_name=region)  # Cost Explorer
        self.region = region
    
    def setup_s3_lifecycle_policies(self, bucket_name: str) -> Dict[str, str]:
        """
        Set up S3 lifecycle policies to archive old data
        
        Args:
            bucket_name: S3 bucket name
            
        Returns:
            Dictionary with policy details
        """
        lifecycle_config = {
            'Rules': [
                {
                    'Id': 'archive-raw-files-after-90-days',
                    'Status': 'Enabled',
                    'Prefix': 'raw/',
                    'Transitions': [
                        {
                            'Days': 90,
                            'StorageClass': 'GLACIER'
                        }
                    ]
                },
                {
                    'Id': 'delete-processed-files-after-180-days',
                    'Status': 'Enabled',
                    'Prefix': 'processed/',
                    'Expiration': {
                        'Days': 180
                    }
                },
                {
                    'Id': 'archive-quarantine-after-30-days',
                    'Status': 'Enabled',
                    'Prefix': 'quarantine/',
                    'Transitions': [
                        {
                            'Days': 30,
                            'StorageClass': 'GLACIER'
                        }
                    ]
                }
            ]
        }
        
        try:
            self.s3_client.put_bucket_lifecycle_configuration(
                Bucket=bucket_name,
                LifecycleConfiguration=lifecycle_config
            )
            print(f"Set lifecycle policies for bucket: {bucket_name}")
            return {
                'bucket': bucket_name,
                'policies': len(lifecycle_config['Rules']),
                'status': 'success'
            }
        except Exception as e:
            print(f"Error setting lifecycle policies: {e}")
            return {'status': 'error', 'message': str(e)}

    
    def monitor_storage_growth(self, bucket_name: str) -> Dict[str, any]:
        """
        Monitor S3 storage growth and costs
        
        Args:
            bucket_name: S3 bucket name
            
        Returns:
            Storage metrics
        """
        try:
            # Get bucket size metrics from CloudWatch
            end_time = datetime.now()
            start_time = end_time - timedelta(days=30)
            
            response = self.cloudwatch_client.get_metric_statistics(
                Namespace='AWS/S3',
                MetricName='BucketSizeBytes',
                Dimensions=[
                    {'Name': 'BucketName', 'Value': bucket_name},
                    {'Name': 'StorageType', 'Value': 'StandardStorage'}
                ],
                StartTime=start_time,
                EndTime=end_time,
                Period=86400,  # Daily
                Statistics=['Average']
            )
            
            datapoints = sorted(response['Datapoints'], key=lambda x: x['Timestamp'])
            
            if len(datapoints) >= 2:
                current_size_gb = datapoints[-1]['Average'] / (1024**3)
                previous_size_gb = datapoints[0]['Average'] / (1024**3)
                growth_gb = current_size_gb - previous_size_gb
                growth_pct = (growth_gb / previous_size_gb * 100) if previous_size_gb > 0 else 0
                
                return {
                    'bucket': bucket_name,
                    'current_size_gb': round(current_size_gb, 2),
                    'growth_30d_gb': round(growth_gb, 2),
                    'growth_30d_pct': round(growth_pct, 2),
                    'estimated_monthly_cost_usd': round(current_size_gb * 0.023, 2)  # $0.023/GB
                }
            else:
                return {'bucket': bucket_name, 'status': 'insufficient_data'}
                
        except Exception as e:
            print(f"Error monitoring storage: {e}")
            return {'status': 'error', 'message': str(e)}
    
    def get_cost_report(self, days: int = 30) -> Dict[str, any]:
        """
        Get cost report for the platform
        
        Args:
            days: Number of days to look back
            
        Returns:
            Cost breakdown by service
        """
        try:
            end_date = datetime.now().date()
            start_date = end_date - timedelta(days=days)
            
            response = self.ce_client.get_cost_and_usage(
                TimePeriod={
                    'Start': start_date.strftime('%Y-%m-%d'),
                    'End': end_date.strftime('%Y-%m-%d')
                },
                Granularity='MONTHLY',
                Metrics=['UnblendedCost'],
                GroupBy=[
                    {'Type': 'SERVICE', 'Key': 'SERVICE'}
                ],
                Filter={
                    'Tags': {
                        'Key': 'Project',
                        'Values': ['ResearchDataPlatform']
                    }
                }
            )
            
            costs = {}
            total_cost = 0
            
            for result in response['ResultsByTime']:
                for group in result['Groups']:
                    service = group['Keys'][0]
                    cost = float(group['Metrics']['UnblendedCost']['Amount'])
                    costs[service] = costs.get(service, 0) + cost
                    total_cost += cost
            
            return {
                'period_days': days,
                'total_cost_usd': round(total_cost, 2),
                'cost_by_service': {k: round(v, 2) for k, v in costs.items()},
                'top_services': sorted(costs.items(), key=lambda x: x[1], reverse=True)[:5]
            }
            
        except Exception as e:
            print(f"Error getting cost report: {e}")
            return {'status': 'error', 'message': str(e)}

    
    def create_cost_alert(self, 
                         monthly_budget_usd: float,
                         alert_threshold_pct: float = 80.0,
                         sns_topic_arn: str = None):
        """
        Create cost alert when spending exceeds threshold
        
        Args:
            monthly_budget_usd: Monthly budget in USD
            alert_threshold_pct: Alert when this % of budget is reached
            sns_topic_arn: SNS topic for alerts
        """
        try:
            # Create CloudWatch alarm for cost
            alarm_name = 'research-platform-cost-alert'
            
            self.cloudwatch_client.put_metric_alarm(
                AlarmName=alarm_name,
                AlarmDescription=f'Alert when monthly cost exceeds {alert_threshold_pct}% of ${monthly_budget_usd} budget',
                ActionsEnabled=True if sns_topic_arn else False,
                AlarmActions=[sns_topic_arn] if sns_topic_arn else [],
                MetricName='EstimatedCharges',
                Namespace='AWS/Billing',
                Statistic='Maximum',
                Dimensions=[
                    {'Name': 'Currency', 'Value': 'USD'}
                ],
                Period=21600,  # 6 hours
                EvaluationPeriods=1,
                Threshold=monthly_budget_usd * (alert_threshold_pct / 100),
                ComparisonOperator='GreaterThanThreshold'
            )
            
            print(f"Created cost alert: {alarm_name}")
            return {'alarm_name': alarm_name, 'status': 'success'}
            
        except Exception as e:
            print(f"Error creating cost alert: {e}")
            return {'status': 'error', 'message': str(e)}
    
    def identify_expensive_queries(self, redshift_conn) -> List[Dict]:
        """
        Identify expensive Redshift queries for optimization
        
        Args:
            redshift_conn: Redshift database connection
            
        Returns:
            List of expensive queries
        """
        query = """
            SELECT 
                query,
                TRIM(querytxt) as query_text,
                starttime,
                endtime,
                DATEDIFF(seconds, starttime, endtime) as duration_seconds,
                -- Estimate cost based on duration and cluster size
                (DATEDIFF(seconds, starttime, endtime) / 3600.0) * 1.086 as estimated_cost_usd
            FROM stl_query
            WHERE userid > 1
              AND starttime >= DATEADD(day, -7, CURRENT_DATE)
              AND DATEDIFF(seconds, starttime, endtime) > 60
            ORDER BY duration_seconds DESC
            LIMIT 20
        """
        
        try:
            cursor = redshift_conn.cursor()
            cursor.execute(query)
            results = cursor.fetchall()
            
            expensive_queries = []
            for row in results:
                expensive_queries.append({
                    'query_id': row[0],
                    'query_text': row[1][:200],  # Truncate for display
                    'start_time': row[2],
                    'duration_seconds': row[4],
                    'estimated_cost_usd': round(row[5], 4)
                })
            
            return expensive_queries
            
        except Exception as e:
            print(f"Error identifying expensive queries: {e}")
            return []

def optimize_platform_costs(
    s3_bucket: str,
    monthly_budget_usd: float = 5000,
    sns_topic_arn: str = None,
    region: str = 'us-east-1'
):
    """
    Complete cost optimization setup
    
    Args:
        s3_bucket: S3 data lake bucket
        monthly_budget_usd: Monthly budget
        sns_topic_arn: SNS topic for alerts
        region: AWS region
    """
    optimizer = CostOptimizer(region)
    
    print("Setting up cost optimization...")
    
    # Set up S3 lifecycle policies
    lifecycle_result = optimizer.setup_s3_lifecycle_policies(s3_bucket)
    print(f"\nS3 Lifecycle: {lifecycle_result}")
    
    # Monitor storage growth
    storage_metrics = optimizer.monitor_storage_growth(s3_bucket)
    print(f"\nStorage Metrics: {storage_metrics}")
    
    # Get cost report
    cost_report = optimizer.get_cost_report(days=30)
    print(f"\nCost Report: {cost_report}")
    
    # Create cost alert
    if sns_topic_arn:
        alert_result = optimizer.create_cost_alert(
            monthly_budget_usd,
            alert_threshold_pct=80.0,
            sns_topic_arn=sns_topic_arn
        )
        print(f"\nCost Alert: {alert_result}")
    
    print("\nCost optimization setup complete!")
    
    return {
        'lifecycle_policies': lifecycle_result,
        'storage_metrics': storage_metrics,
        'cost_report': cost_report
    }

if __name__ == '__main__':
    # Run optimization
    result = optimize_platform_costs(
        s3_bucket='itus-data-lake',
        monthly_budget_usd=5000
    )
    print(f"\nOptimization summary: {result}")
