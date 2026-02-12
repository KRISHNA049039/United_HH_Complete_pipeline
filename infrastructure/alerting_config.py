"""
Alerting Configuration for Research Data Platform
Sets up CloudWatch alarms and SNS notifications
"""

import boto3
from typing import List, Dict

class AlertingConfigurator:
    """Configure CloudWatch alarms and SNS topics"""
    
    def __init__(self, region: str = 'us-east-1'):
        self.cloudwatch_client = boto3.client('cloudwatch', region_name=region)
        self.sns_client = boto3.client('sns', region_name=region)
        self.region = region
    
    def create_sns_topics(self) -> Dict[str, str]:
        """
        Create SNS topics for different alert types
        
        Returns:
            Dictionary mapping topic names to ARNs
        """
        topics = {
            'critical-alerts': 'Critical platform failures requiring immediate attention',
            'data-quality-alerts': 'Data quality validation failures',
            'etl-job-alerts': 'ETL job failures and delays',
            'performance-alerts': 'Query performance and resource usage alerts'
        }
        
        topic_arns = {}
        
        for topic_name, description in topics.items():
            try:
                response = self.sns_client.create_topic(
                    Name=f'research-platform-{topic_name}'
                )
                topic_arn = response['TopicArn']
                
                # Set display name
                self.sns_client.set_topic_attributes(
                    TopicArn=topic_arn,
                    AttributeName='DisplayName',
                    AttributeValue=f'Research Platform - {topic_name}'
                )
                
                topic_arns[topic_name] = topic_arn
                print(f"Created SNS topic: {topic_name} -> {topic_arn}")
                
            except Exception as e:
                print(f"Error creating SNS topic {topic_name}: {e}")
        
        return topic_arns

    
    def subscribe_email_to_topic(self, topic_arn: str, email: str):
        """
        Subscribe an email address to an SNS topic
        
        Args:
            topic_arn: SNS topic ARN
            email: Email address to subscribe
        """
        try:
            self.sns_client.subscribe(
                TopicArn=topic_arn,
                Protocol='email',
                Endpoint=email
            )
            print(f"Subscribed {email} to {topic_arn}")
            print("Note: Email confirmation required")
        except Exception as e:
            print(f"Error subscribing email: {e}")
    
    def create_etl_job_failure_alarms(self, topic_arn: str) -> List[str]:
        """
        Create alarms for ETL job failures
        
        Args:
            topic_arn: SNS topic ARN for notifications
            
        Returns:
            List of created alarm names
        """
        etl_jobs = [
            'daily-prices-etl',
            'quarterly-financials-etl',
            'daily-flows-etl',
            'corporate-actions-etl',
            'index-constituents-etl'
        ]
        
        alarm_names = []
        
        for job in etl_jobs:
            alarm_name = f'etl-failure-{job}'
            
            try:
                self.cloudwatch_client.put_metric_alarm(
                    AlarmName=alarm_name,
                    AlarmDescription=f'Alert when {job} fails',
                    ActionsEnabled=True,
                    AlarmActions=[topic_arn],
                    MetricName='JobFailure',
                    Namespace='AWS/Glue',
                    Statistic='Sum',
                    Dimensions=[
                        {'Name': 'JobName', 'Value': job}
                    ],
                    Period=300,  # 5 minutes
                    EvaluationPeriods=1,
                    Threshold=1,
                    ComparisonOperator='GreaterThanOrEqualToThreshold',
                    TreatMissingData='notBreaching'
                )
                
                alarm_names.append(alarm_name)
                print(f"Created alarm: {alarm_name}")
                
            except Exception as e:
                print(f"Error creating alarm {alarm_name}: {e}")
        
        return alarm_names

    
    def create_data_quality_alarms(self, topic_arn: str) -> List[str]:
        """
        Create alarms for data quality failures
        
        Args:
            topic_arn: SNS topic ARN for notifications
            
        Returns:
            List of created alarm names
        """
        alarms = []
        
        # Alarm for low data quality pass rate
        alarm_name = 'data-quality-low-pass-rate'
        try:
            self.cloudwatch_client.put_metric_alarm(
                AlarmName=alarm_name,
                AlarmDescription='Alert when data quality pass rate falls below 95%',
                ActionsEnabled=True,
                AlarmActions=[topic_arn],
                MetricName='DataQualityPassRate',
                Namespace='ResearchDataPlatform',
                Statistic='Average',
                Period=300,
                EvaluationPeriods=1,
                Threshold=95,
                ComparisonOperator='LessThanThreshold',
                TreatMissingData='notBreaching'
            )
            alarms.append(alarm_name)
            print(f"Created alarm: {alarm_name}")
        except Exception as e:
            print(f"Error creating alarm {alarm_name}: {e}")
        
        # Alarm for validation failures
        alarm_name = 'data-quality-validation-failures'
        try:
            self.cloudwatch_client.put_metric_alarm(
                AlarmName=alarm_name,
                AlarmDescription='Alert when validation failures occur',
                ActionsEnabled=True,
                AlarmActions=[topic_arn],
                MetricName='ValidationFailureCount',
                Namespace='ResearchDataPlatform',
                Statistic='Sum',
                Period=300,
                EvaluationPeriods=1,
                Threshold=1,
                ComparisonOperator='GreaterThanOrEqualToThreshold',
                TreatMissingData='notBreaching'
            )
            alarms.append(alarm_name)
            print(f"Created alarm: {alarm_name}")
        except Exception as e:
            print(f"Error creating alarm {alarm_name}: {e}")
        
        return alarms
    
    def create_query_performance_alarms(self, topic_arn: str) -> List[str]:
        """
        Create alarms for query performance issues
        
        Args:
            topic_arn: SNS topic ARN for notifications
            
        Returns:
            List of created alarm names
        """
        alarms = []
        
        # Alarm for high query timeout rate
        alarm_name = 'query-high-timeout-rate'
        try:
            self.cloudwatch_client.put_metric_alarm(
                AlarmName=alarm_name,
                AlarmDescription='Alert when query timeout rate exceeds 5%',
                ActionsEnabled=True,
                AlarmActions=[topic_arn],
                MetricName='QueryFailureRate',
                Namespace='ResearchDataPlatform',
                Statistic='Average',
                Period=900,  # 15 minutes
                EvaluationPeriods=2,
                Threshold=5,
                ComparisonOperator='GreaterThanThreshold',
                TreatMissingData='notBreaching'
            )
            alarms.append(alarm_name)
            print(f"Created alarm: {alarm_name}")
        except Exception as e:
            print(f"Error creating alarm {alarm_name}: {e}")
        
        return alarms

    
    def create_redshift_resource_alarms(self, 
                                       cluster_identifier: str,
                                       topic_arn: str) -> List[str]:
        """
        Create alarms for Redshift cluster resource usage
        
        Args:
            cluster_identifier: Redshift cluster identifier
            topic_arn: SNS topic ARN for notifications
            
        Returns:
            List of created alarm names
        """
        alarms = []
        
        # CPU utilization alarm
        alarm_name = f'redshift-high-cpu-{cluster_identifier}'
        try:
            self.cloudwatch_client.put_metric_alarm(
                AlarmName=alarm_name,
                AlarmDescription='Alert when Redshift CPU exceeds 80%',
                ActionsEnabled=True,
                AlarmActions=[topic_arn],
                MetricName='CPUUtilization',
                Namespace='AWS/Redshift',
                Statistic='Average',
                Dimensions=[
                    {'Name': 'ClusterIdentifier', 'Value': cluster_identifier}
                ],
                Period=300,
                EvaluationPeriods=3,
                Threshold=80,
                ComparisonOperator='GreaterThanThreshold'
            )
            alarms.append(alarm_name)
            print(f"Created alarm: {alarm_name}")
        except Exception as e:
            print(f"Error creating alarm {alarm_name}: {e}")
        
        # Disk space alarm
        alarm_name = f'redshift-low-disk-{cluster_identifier}'
        try:
            self.cloudwatch_client.put_metric_alarm(
                AlarmName=alarm_name,
                AlarmDescription='Alert when Redshift disk usage exceeds 85%',
                ActionsEnabled=True,
                AlarmActions=[topic_arn],
                MetricName='PercentageDiskSpaceUsed',
                Namespace='AWS/Redshift',
                Statistic='Average',
                Dimensions=[
                    {'Name': 'ClusterIdentifier', 'Value': cluster_identifier}
                ],
                Period=300,
                EvaluationPeriods=2,
                Threshold=85,
                ComparisonOperator='GreaterThanThreshold'
            )
            alarms.append(alarm_name)
            print(f"Created alarm: {alarm_name}")
        except Exception as e:
            print(f"Error creating alarm {alarm_name}: {e}")
        
        return alarms

def setup_alerting(region: str = 'us-east-1',
                  operations_email: str = None,
                  redshift_cluster: str = None):
    """
    Complete alerting setup for the platform
    
    Args:
        region: AWS region
        operations_email: Email for alert notifications
        redshift_cluster: Redshift cluster identifier
    """
    configurator = AlertingConfigurator(region)
    
    print("Setting up alerting...")
    
    # Create SNS topics
    topic_arns = configurator.create_sns_topics()
    print(f"\nCreated {len(topic_arns)} SNS topics")
    
    # Subscribe email if provided
    if operations_email:
        for topic_name, topic_arn in topic_arns.items():
            configurator.subscribe_email_to_topic(topic_arn, operations_email)
    
    # Create alarms
    all_alarms = []
    
    if 'etl-job-alerts' in topic_arns:
        etl_alarms = configurator.create_etl_job_failure_alarms(topic_arns['etl-job-alerts'])
        all_alarms.extend(etl_alarms)
        print(f"\nCreated {len(etl_alarms)} ETL job alarms")
    
    if 'data-quality-alerts' in topic_arns:
        dq_alarms = configurator.create_data_quality_alarms(topic_arns['data-quality-alerts'])
        all_alarms.extend(dq_alarms)
        print(f"\nCreated {len(dq_alarms)} data quality alarms")
    
    if 'performance-alerts' in topic_arns:
        perf_alarms = configurator.create_query_performance_alarms(topic_arns['performance-alerts'])
        all_alarms.extend(perf_alarms)
        print(f"\nCreated {len(perf_alarms)} performance alarms")
    
    if redshift_cluster and 'critical-alerts' in topic_arns:
        rs_alarms = configurator.create_redshift_resource_alarms(
            redshift_cluster, 
            topic_arns['critical-alerts']
        )
        all_alarms.extend(rs_alarms)
        print(f"\nCreated {len(rs_alarms)} Redshift resource alarms")
    
    print(f"\nAlerting setup complete! Total alarms: {len(all_alarms)}")
    
    return {
        'topic_arns': topic_arns,
        'alarms': all_alarms
    }

if __name__ == '__main__':
    # Run setup
    result = setup_alerting(
        operations_email='ops@example.com',
        redshift_cluster='research-platform-cluster'
    )
    print(f"\nSetup summary: {result}")
