#!/bin/bash

# Research Data Platform V2 - Infrastructure Deployment Script
# This script automates the deployment of AWS infrastructure using Terraform

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Research Data Platform V2 Deployment${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v terraform &> /dev/null; then
    echo -e "${RED}Error: Terraform is not installed${NC}"
    echo "Please install Terraform: https://www.terraform.io/downloads"
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    echo "Please install AWS CLI: https://aws.amazon.com/cli/"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS credentials not configured${NC}"
    echo "Please run: aws configure"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites check passed${NC}"
echo ""

# Navigate to terraform directory
cd "$(dirname "$0")/terraform"

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    echo -e "${YELLOW}terraform.tfvars not found. Creating from example...${NC}"
    cp terraform.tfvars.example terraform.tfvars
    echo -e "${RED}Please edit terraform.tfvars with your configuration${NC}"
    echo "Required changes:"
    echo "  - redshift_master_username"
    echo "  - redshift_master_password"
    echo "  - alert_email"
    echo ""
    echo "Then run this script again."
    exit 1
fi

# Validate required variables
echo -e "${YELLOW}Validating configuration...${NC}"

if grep -q "CHANGE_ME" terraform.tfvars; then
    echo -e "${RED}Error: Please update terraform.tfvars with actual values${NC}"
    echo "Found placeholder values that need to be changed."
    exit 1
fi

echo -e "${GREEN}✓ Configuration validated${NC}"
echo ""

# Initialize Terraform
echo -e "${YELLOW}Initializing Terraform...${NC}"
terraform init

echo -e "${GREEN}✓ Terraform initialized${NC}"
echo ""

# Run terraform plan
echo -e "${YELLOW}Generating deployment plan...${NC}"
terraform plan -out=tfplan

echo ""
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Review the plan above${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

# Confirm deployment
read -p "Do you want to proceed with deployment? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo -e "${RED}Deployment cancelled${NC}"
    rm -f tfplan
    exit 0
fi

# Apply terraform
echo ""
echo -e "${YELLOW}Deploying infrastructure...${NC}"
echo -e "${YELLOW}This will take approximately 10-15 minutes${NC}"
echo ""

terraform apply tfplan

# Clean up plan file
rm -f tfplan

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Display outputs
echo -e "${YELLOW}Important Information:${NC}"
echo ""
terraform output

echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Check your email and confirm SNS subscription"
echo "2. Save the Redshift endpoint and credentials securely"
echo "3. Create S3 folder structure (see README.md)"
echo "4. Proceed to Task 2: Implement data ingestion pipeline"
echo ""
echo -e "${GREEN}For more information, see infrastructure/README.md${NC}"
