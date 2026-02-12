"""
CloudWatch Monitoring Configuration for Research Data Platform
Sets up log groups, custom metrics, and retention policies
"""

import boto3
from typing import List, Dict

class CloudWatchConfigurator:
    """Configure CloudWatch logging and monitoring"""
    
    def __init__(self, region: str = 'us-east-1'):
        self.logs_client = boto3.client('logs', region_name=region)
        self.cloudwatch_client = boto3.client('cloudwatch', region_name=region)
        self.region = region
    
    def create_log_groups(self) -> List[str]:
        """
        Create CloudWatch log groups for all platform components
        
        Returns:
            List of created log group names
        """
        log_groups = [
            # Lambda validators
            '/aws/lambda/price-validator',
            '/aws/lambda/financial-validator',
            '/aws/lambda/flow-validator',
            
            # Glue ETL jobs
            '/aws/glue/daily-prices-etl',
            '/aws/glue/quarterly-financials-etl',
            '/aws/glue/daily-flows-etl',
            '/aws/glue/corporate-actions-etl',
            '/aws/glue/index-constituents-etl',
            
            # API service
            '/ecs/research-platform-api',
            
            # Data quality
            '/aws/lambda/data-quality-engine'
        ]
        
        created_groups = []
        
        for log_group in log_groups:
            try:
                self.logs_client.create_log_group(logGroupName=log_group)
                print(f"Created log group: {log_group}")
                created_groups.append(log_group)
            except self.logs_client.exceptions.ResourceAlreadyExistsException:
                print(f"Log group already exists: {log_group}")
                created_groups.append(log_group)
            except Exception as e:
                print(f"Error creating log group {log_group}: {e}")
        
        return created_groups

    
    def set_retention_policies(self, retention_days: int = 30) -> List[str]:
        """
        Set retention policies for all log groups
        
        Args:
            retention_days: Number of days to retain logs (default 30)
            
        Returns:
            List of log groups with retention set
        """
        log_groups = self._get_all_log_groups()
        updated_groups = []
        
        for log_group in log_groups:
            try:
                self.logs_client.put_retention_policy(
                    logGroupName=log_group,
                    retentionInDays=retention_days
                )
                print(f"Set retention to {retention_days} days for: {log_group}")
                updated_groups.append(log_group)
            except Exception as e:
                print(f"Error setting retention for {log_group}: {e}")
        
        return updated_groups
    
    def _get_all_log_groups(self) -> List[str]:
        """Get all log groups for the platform"""
        try:
            response = self.logs_client.describe_log_groups(
                logGroupNamePrefix='/aws/'
            )
            return [lg['logGroupName'] for lg in response.get('logGroups', [])]
        except Exception as e:
            print(f"Error getting log groups: {e}")
            return []
    
    def create_custom_metrics(self) -> List[str]:
        """
        Create custom CloudWatch metrics for platform monitoring
        
        Returns:
            List of created metric names
        """
        metrics = [
            'QueryExecutionTime',
            'QueryFailureRate',
            'DataQualityPassRate',
            'ETLJobDuration',
            'CacheHitRate',
            'ValidationFailureCount'
        ]
        
        # Custom metrics are created automatically when first data point is published
        # This method documents the metrics we'll use
        
        print(f"Documented {len(metrics)} custom metrics")
        return metrics
    
    def publish_metric(self, 
                      metric_name: str,
                      value: float,
                      unit: str = 'None',
                      dimensions: Dict[str, str] = None):
        """
        Publish a custom metric to CloudWatch
        
        Args:
            metric_name: Name of the metric
            value: Metric value
            unit: Unit of measurement
            dimensions: Metric dimensions (e.g., {'DataSource': 'prices'})
        """
        try:
            metric_data = {
                'MetricName': metric_name,
                'Value': value,
                'Unit': unit,
                'Timestamp': boto3.utils.datetime.datetime.now()
            }
            
            if dimensions:
                metric_data['Dimensions'] = [
                    {'Name': k, 'Value': v} for k, v in dimensions.items()
                ]
            
            self.cloudwatch_client.put_metric_data(
                Namespace='ResearchDataPlatform',
                MetricData=[metric_data]
            )
            
            print(f"Published metric: {metric_name} = {value}")
            
        except Exception as e:
            print(f"Error publishing metric {metric_name}: {e}")


def setup_cloudwatch_monitoring(region: str = 'us-east-1', retention_days: int = 30):
    """
    Complete CloudWatch setup for the platform
    
    Args:
        region: AWS region
        retention_days: Log retention period
    """
    configurator = CloudWatchConfigurator(region)
    
    print("Setting up CloudWatch monitoring...")
    
    # Create log groups
    log_groups = configurator.create_log_groups()
    print(f"\nCreated/verified {len(log_groups)} log groups")
    
    # Set retention policies
    updated_groups = configurator.set_retention_policies(retention_days)
    print(f"\nSet retention policies for {len(updated_groups)} log groups")
    
    # Document custom metrics
    metrics = configurator.create_custom_metrics()
    print(f"\nDocumented {len(metrics)} custom metrics")
    
    print("\nCloudWatch monitoring setup complete!")
    
    return {
        'log_groups': log_groups,
        'retention_days': retention_days,
        'custom_metrics': metrics
    }

if __name__ == '__main__':
    # Run setup
    result = setup_cloudwatch_monitoring()
    print(f"\nSetup summary: {result}")
