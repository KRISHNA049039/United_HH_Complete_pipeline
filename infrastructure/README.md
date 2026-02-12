# Research Data Platform V2 - Infrastructure

This directory contains Infrastructure as Code (IaC) for the Research Data Platform V2 using Terraform.

## Architecture Overview

The infrastructure includes:
- **Amazon Redshift**: 2-node RA3.4xlarge cluster with auto-scaling (scales to 4 nodes during peak hours)
- **Amazon S3**: Data lake with raw/, processed/, and archive/ folders
- **VPC**: Multi-AZ VPC with public and private subnets
- **IAM Roles**: Least-privilege roles for Redshift, Lambda, and Glue
- **CloudWatch**: Monitoring, logging, and alerting
- **SNS**: Alert notifications

## Prerequisites

1. AWS CLI configured with appropriate credentials
2. Terraform >= 1.0 installed
3. Access to AWS account with permissions to create resources

## Deployment Instructions

### Step 1: Configure Variables

```bash
cd infrastructure/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and update:
- `redshift_master_username`: Choose a secure username
- `redshift_master_password`: Use a strong password (min 8 chars, uppercase, lowercase, number)
- `alert_email`: Email address for CloudWatch alerts

### Step 2: Initialize Terraform

```bash
terraform init
```

### Step 3: Review Plan

```bash
terraform plan
```

Review the resources that will be created.

### Step 4: Apply Configuration

```bash
terraform apply
```

Type `yes` when prompted to confirm.

**Deployment time**: Approximately 10-15 minutes (Redshift cluster takes the longest)

### Step 5: Verify Deployment

After successful deployment, Terraform will output:
- Redshift cluster endpoint
- S3 bucket name
- VPC ID
- SNS topic ARN
- IAM role ARNs

Save these outputs for later configuration steps.

### Step 6: Confirm SNS Subscription

Check your email for an SNS subscription confirmation and click the confirmation link.

## Post-Deployment Configuration

### Connect to Redshift

```bash
# Get the cluster endpoint from Terraform outputs
terraform output redshift_cluster_endpoint

# Connect using psql (from within VPC or via bastion host)
psql -h <cluster-endpoint> -U <master-username> -d research_platform -p 5439
```

### Create S3 Folder Structure

```bash
# Get bucket name
BUCKET_NAME=$(terraform output -raw s3_bucket_name)

# Create folder structure
aws s3api put-object --bucket $BUCKET_NAME --key raw/prices/
aws s3api put-object --bucket $BUCKET_NAME --key raw/financials/
aws s3api put-object --bucket $BUCKET_NAME --key raw/flows/
aws s3api put-object --bucket $BUCKET_NAME --key raw/macro/
aws s3api put-object --bucket $BUCKET_NAME --key processed/
aws s3api put-object --bucket $BUCKET_NAME --key archive/
```

## Cost Optimization Features

The infrastructure includes several cost optimization features:

1. **Auto-scaling**: Cluster scales from 2 to 4 nodes during business hours (8 AM - 6 PM IST)
2. **Pause/Resume**: Cluster pauses on Friday evening and resumes Monday morning
3. **S3 Lifecycle**: Raw files archived to Glacier after 90 days
4. **Concurrency Scaling**: Up to 10 additional clusters for read queries during peak load

## Estimated Monthly Costs

- Redshift RA3.4xlarge (2 nodes, ~16 hours/day): ~$2,500
- S3 storage (1-2 TB): ~$25-50
- Data transfer and other services: ~$100-200
- **Total**: ~$2,700-3,000/month

## Monitoring

### CloudWatch Dashboard

Access the CloudWatch dashboard:
```bash
aws cloudwatch get-dashboard --dashboard-name $(terraform output -raw dashboard_name)
```

### CloudWatch Alarms

The following alarms are configured:
- High CPU utilization (> 80%)
- Low disk space (< 20% free)
- Cluster health issues
- High query queue depth (> 10 queries)

All alarms send notifications to the configured SNS topic.

## Security Features

1. **Encryption**: 
   - Redshift cluster encrypted at rest using KMS
   - S3 bucket encrypted with AES256
   
2. **Network**:
   - Redshift in private subnets (not publicly accessible)
   - Security groups with least-privilege access
   - Enhanced VPC routing enabled

3. **IAM**:
   - Separate roles for Redshift, Lambda, and Glue
   - Least-privilege policies
   - No hardcoded credentials

4. **Logging**:
   - Redshift audit logging enabled
   - CloudWatch logs for Lambda and Glue
   - 30-day log retention

## Maintenance

### Update Redshift Password

```bash
aws redshift modify-cluster \
  --cluster-identifier itus-research-platform \
  --master-user-password <new-password>
```

### Manual Scaling

```bash
# Scale up to 4 nodes
aws redshift modify-cluster \
  --cluster-identifier itus-research-platform \
  --number-of-nodes 4

# Scale down to 2 nodes
aws redshift modify-cluster \
  --cluster-identifier itus-research-platform \
  --number-of-nodes 2
```

### Pause/Resume Cluster

```bash
# Pause cluster
aws redshift pause-cluster --cluster-identifier itus-research-platform

# Resume cluster
aws redshift resume-cluster --cluster-identifier itus-research-platform
```

## Troubleshooting

### Redshift Connection Issues

1. Verify security group allows inbound on port 5439
2. Check VPC routing and NAT gateway
3. Ensure you're connecting from within VPC or via VPN/bastion

### High Costs

1. Check if cluster is pausing/resuming as scheduled
2. Review S3 lifecycle policies are working
3. Monitor concurrency scaling usage
4. Consider reducing node count during low-usage periods

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will delete the Redshift cluster and all data. Ensure you have backups before proceeding.

## Next Steps

After infrastructure is deployed:
1. Proceed to Task 2: Implement data ingestion pipeline
2. Create database schemas (Task 3)
3. Set up Lambda validators and Glue ETL jobs

## Support

For issues or questions:
- Check CloudWatch logs for error messages
- Review Terraform state: `terraform show`
- Contact platform team
