#!/bin/bash

# Deploy FastAPI Query Service to AWS ECS Fargate

set -e

echo "========================================="
echo "Deploying FastAPI Query Service"
echo "========================================="
echo ""

# Configuration
REGION="ap-south-1"
ECR_REPO_NAME="research-platform-api"
ECS_CLUSTER_NAME="research-platform-cluster"
ECS_SERVICE_NAME="query-api-service"
TASK_FAMILY="query-api-task"

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO_NAME}"

echo "AWS Account: $AWS_ACCOUNT_ID"
echo "ECR Repository: $ECR_REPO_URI"
echo ""

# Create ECR repository if it doesn't exist
echo "Creating ECR repository..."
aws ecr create-repository \
    --repository-name $ECR_REPO_NAME \
    --region $REGION \
    2>/dev/null || echo "Repository already exists"

# Login to ECR
echo "Logging in to ECR..."
aws ecr get-login-password --region $REGION | \
    docker login --username AWS --password-stdin $ECR_REPO_URI

# Build Docker image
echo "Building Docker image..."
docker build -t $ECR_REPO_NAME:latest .

# Tag image
docker tag $ECR_REPO_NAME:latest $ECR_REPO_URI:latest

# Push to ECR
echo "Pushing image to ECR..."
docker push $ECR_REPO_URI:latest

echo "✓ Docker image pushed to ECR"
echo ""

# Create ECS cluster if it doesn't exist
echo "Creating ECS cluster..."
aws ecs create-cluster \
    --cluster-name $ECS_CLUSTER_NAME \
    --region $REGION \
    2>/dev/null || echo "Cluster already exists"

# Create task definition
echo "Creating ECS task definition..."
cat > task-definition.json <<EOF
{
  "family": "$TASK_FAMILY",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/ecsTaskExecutionRole",
  "containerDefinitions": [
    {
      "name": "query-api",
      "image": "${ECR_REPO_URI}:latest",
      "portMappings": [
        {
          "containerPort": 8000,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "REDSHIFT_HOST",
          "value": "${REDSHIFT_HOST}"
        },
        {
          "name": "REDSHIFT_PORT",
          "value": "5439"
        },
        {
          "name": "REDSHIFT_DB",
          "value": "research_platform"
        },
        {
          "name": "REDIS_HOST",
          "value": "${REDIS_HOST}"
        }
      ],
      "secrets": [
        {
          "name": "REDSHIFT_USER",
          "valueFrom": "arn:aws:secretsmanager:${REGION}:${AWS_ACCOUNT_ID}:secret:redshift/api-user"
        },
        {
          "name": "REDSHIFT_PASSWORD",
          "valueFrom": "arn:aws:secretsmanager:${REGION}:${AWS_ACCOUNT_ID}:secret:redshift/api-password"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/query-api",
          "awslogs-region": "${REGION}",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
EOF

aws ecs register-task-definition \
    --cli-input-json file://task-definition.json \
    --region $REGION

echo "✓ Task definition registered"
echo ""

# Create ECS service
echo "Creating ECS service..."
aws ecs create-service \
    --cluster $ECS_CLUSTER_NAME \
    --service-name $ECS_SERVICE_NAME \
    --task-definition $TASK_FAMILY \
    --desired-count 2 \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[subnet-xxx],securityGroups=[sg-xxx],assignPublicIp=ENABLED}" \
    --region $REGION \
    2>/dev/null || echo "Service already exists, updating..."

# Update service if it exists
aws ecs update-service \
    --cluster $ECS_CLUSTER_NAME \
    --service $ECS_SERVICE_NAME \
    --task-definition $TASK_FAMILY \
    --force-new-deployment \
    --region $REGION

echo "✓ ECS service deployed"
echo ""

# Cleanup
rm task-definition.json

echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo ""
echo "API Service:"
echo "  - Cluster: $ECS_CLUSTER_NAME"
echo "  - Service: $ECS_SERVICE_NAME"
echo "  - Task Count: 2"
echo ""
echo "Next Steps:"
echo "1. Configure Application Load Balancer"
echo "2. Set up Route53 DNS"
echo "3. Configure SSL certificate"
echo "4. Test API endpoints"
