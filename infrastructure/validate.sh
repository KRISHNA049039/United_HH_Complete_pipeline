#!/bin/bash

# Research Data Platform V2 - Infrastructure Validation Script
# This script validates that all infrastructure components are properly deployed

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Infrastructure Validation${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

cd "$(dirname "$0")/terraform"

# Check if Terraform state exists
if [ ! -f "terraform.tfstate" ]; then
    echo -e "${RED}Error: No Terraform state found${NC}"
    echo "Please deploy infrastructure first using deploy.sh"
    exit 1
fi

# Get outputs
echo -e "${YELLOW}Retrieving infrastructure details...${NC}"
CLUSTER_ID=$(terraform output -raw redshift_cluster_endpoint | cut -d'.' -f1)
BUCKET_NAME=$(terraform output -raw s3_bucket_name)
VPC_ID=$(terraform output -raw vpc_id)

echo ""
echo -e "${YELLOW}Validating components...${NC}"
echo ""

# Validate Redshift Cluster
echo -n "Checking Redshift cluster... "
CLUSTER_STATUS=$(aws redshift describe-clusters \
    --cluster-identifier "$CLUSTER_ID" \
    --query 'Clusters[0].ClusterStatus' \
    --output text 2>/dev/null || echo "not-found")

if [ "$CLUSTER_STATUS" == "available" ]; then
    echo -e "${GREEN}✓ Available${NC}"
elif [ "$CLUSTER_STATUS" == "creating" ]; then
    echo -e "${YELLOW}⚠ Still creating...${NC}"
else
    echo -e "${RED}✗ Status: $CLUSTER_STATUS${NC}"
fi

# Validate S3 Bucket
echo -n "Checking S3 bucket... "
if aws s3 ls "s3://$BUCKET_NAME" &> /dev/null; then
    echo -e "${GREEN}✓ Accessible${NC}"
else
    echo -e "${RED}✗ Not accessible${NC}"
fi

# Validate VPC
echo -n "Checking VPC... "
VPC_STATE=$(aws ec2 describe-vpcs \
    --vpc-ids "$VPC_ID" \
    --query 'Vpcs[0].State' \
    --output text 2>/dev/null || echo "not-found")

if [ "$VPC_STATE" == "available" ]; then
    echo -e "${GREEN}✓ Available${NC}"
else
    echo -e "${RED}✗ Status: $VPC_STATE${NC}"
fi

# Check CloudWatch Alarms
echo -n "Checking CloudWatch alarms... "
ALARM_COUNT=$(aws cloudwatch describe-alarms \
    --query 'length(MetricAlarms[?contains(AlarmName, `research-platform`)])' \
    --output text)

if [ "$ALARM_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ $ALARM_COUNT alarms configured${NC}"
else
    echo -e "${RED}✗ No alarms found${NC}"
fi

# Check SNS Topic
echo -n "Checking SNS topic... "
SNS_ARN=$(terraform output -raw sns_topic_arn)
SUBSCRIPTION_COUNT=$(aws sns list-subscriptions-by-topic \
    --topic-arn "$SNS_ARN" \
    --query 'length(Subscriptions)' \
    --output text)

if [ "$SUBSCRIPTION_COUNT" -gt 0 ]; then
    CONFIRMED=$(aws sns list-subscriptions-by-topic \
        --topic-arn "$SNS_ARN" \
        --query 'Subscriptions[?SubscriptionArn!=`PendingConfirmation`]' \
        --output text | wc -l)
    
    if [ "$CONFIRMED" -gt 0 ]; then
        echo -e "${GREEN}✓ Subscribed and confirmed${NC}"
    else
        echo -e "${YELLOW}⚠ Pending confirmation${NC}"
    fi
else
    echo -e "${RED}✗ No subscriptions${NC}"
fi

# Check IAM Roles
echo -n "Checking IAM roles... "
ROLE_COUNT=0

for role in "redshift-role" "lambda-validator-role" "glue-etl-role"; do
    if aws iam get-role --role-name "prod-$role" &> /dev/null; then
        ((ROLE_COUNT++))
    fi
done

if [ "$ROLE_COUNT" -eq 3 ]; then
    echo -e "${GREEN}✓ All 3 roles exist${NC}"
else
    echo -e "${YELLOW}⚠ Only $ROLE_COUNT/3 roles found${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Validation Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Display resource details
echo "Redshift Cluster:"
aws redshift describe-clusters \
    --cluster-identifier "$CLUSTER_ID" \
    --query 'Clusters[0].{Status:ClusterStatus,Nodes:NumberOfNodes,Type:NodeType}' \
    --output table 2>/dev/null || echo "  Not available"

echo ""
echo "S3 Bucket Structure:"
aws s3 ls "s3://$BUCKET_NAME/" --recursive | head -10 || echo "  Empty or not accessible"

echo ""
echo -e "${YELLOW}Cost Estimate:${NC}"
echo "  Redshift (2 nodes, ~16h/day): ~\$2,500/month"
echo "  S3 storage: ~\$25-50/month"
echo "  Other services: ~\$100-200/month"
echo "  Total: ~\$2,700-3,000/month"

echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. If SNS subscription is pending, check email and confirm"
echo "2. Test Redshift connection from within VPC"
echo "3. Create database schemas (Task 3)"
echo "4. Set up Lambda validators (Task 2)"
