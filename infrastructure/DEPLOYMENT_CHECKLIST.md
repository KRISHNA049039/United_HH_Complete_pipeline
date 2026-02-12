# Infrastructure Deployment Checklist

Use this checklist to ensure all steps are completed for Task 1.

## Pre-Deployment

- [ ] AWS CLI installed and configured
- [ ] Terraform >= 1.0 installed
- [ ] AWS account with appropriate permissions
- [ ] Decided on Redshift master username and password
- [ ] Identified email address for alerts

## Deployment Steps

- [ ] Copy `terraform.tfvars.example` to `terraform.tfvars`
- [ ] Update `terraform.tfvars` with:
  - [ ] `redshift_master_username`
  - [ ] `redshift_master_password` (strong password)
  - [ ] `alert_email`
- [ ] Run `./deploy.sh` or manually:
  - [ ] `terraform init`
  - [ ] `terraform plan`
  - [ ] `terraform apply`
- [ ] Save Terraform outputs securely
- [ ] Confirm SNS email subscription

## Post-Deployment Validation

- [ ] Run `./validate.sh` to check all components
- [ ] Verify Redshift cluster status is "available"
- [ ] Verify S3 bucket is accessible
- [ ] Verify VPC and subnets are created
- [ ] Verify CloudWatch alarms are configured
- [ ] Verify SNS subscription is confirmed
- [ ] Verify IAM roles exist (Redshift, Lambda, Glue)

## Configuration

- [ ] Create S3 folder structure:
  - [ ] `raw/prices/`
  - [ ] `raw/financials/`
  - [ ] `raw/flows/`
  - [ ] `raw/macro/`
  - [ ] `processed/`
  - [ ] `archive/`
- [ ] Test Redshift connection (from within VPC)
- [ ] Verify auto-scaling schedule (8 AM - 6 PM IST)
- [ ] Verify pause/resume schedule (weekend pause)

## Security Verification

- [ ] Redshift cluster is NOT publicly accessible
- [ ] Redshift is in private subnets
- [ ] Security groups allow only necessary traffic
- [ ] Encryption at rest is enabled (KMS)
- [ ] S3 bucket has encryption enabled
- [ ] IAM roles follow least-privilege principle
- [ ] CloudWatch logging is enabled

## Cost Optimization Verification

- [ ] S3 lifecycle policies are configured
- [ ] Redshift auto-scaling is configured
- [ ] Redshift pause/resume is configured
- [ ] Concurrency scaling limits are set

## Documentation

- [ ] Save Redshift endpoint securely
- [ ] Save master credentials in password manager
- [ ] Document VPC ID and subnet IDs
- [ ] Document IAM role ARNs
- [ ] Document S3 bucket name
- [ ] Share CloudWatch dashboard with team

## Requirements Satisfied

This task satisfies the following requirements:

- [x] 1.1-1.5: Survivorship-Free Historical Data (infrastructure ready)
- [x] 2.1-2.5: Point-in-Time Data Integrity (infrastructure ready)
- [x] 12.1-12.5: Failure Detection and Recovery (CloudWatch, SNS configured)

## Estimated Costs

- Redshift RA3.4xlarge (2 nodes): ~$2,500/month
- S3 storage (1-2 TB): ~$25-50/month
- Data transfer and other: ~$100-200/month
- **Total**: ~$2,700-3,000/month

## Troubleshooting

If deployment fails:
1. Check AWS credentials: `aws sts get-caller-identity`
2. Check Terraform version: `terraform version`
3. Review error messages in Terraform output
4. Check CloudWatch logs for specific service errors
5. Verify AWS service quotas (especially Redshift)

## Next Steps

After completing this checklist:
1. Proceed to Task 2: Implement data ingestion pipeline
2. Create Lambda validators for data validation
3. Set up Glue ETL jobs for data loading
