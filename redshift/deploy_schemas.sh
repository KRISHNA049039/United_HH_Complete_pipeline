#!/bin/bash

# Deploy Redshift Database Schemas

set -e

echo "========================================="
echo "Deploying Redshift Database Schemas"
echo "========================================="
echo ""

# Get Redshift connection details from Terraform
cd ../infrastructure/terraform
REDSHIFT_ENDPOINT=$(terraform output -raw redshift_cluster_endpoint | cut -d':' -f1)
REDSHIFT_PORT=5439
REDSHIFT_DB=$(terraform output -raw redshift_database_name)
cd ../../redshift

# Prompt for credentials
read -p "Redshift master username: " REDSHIFT_USER
read -sp "Redshift master password: " REDSHIFT_PASSWORD
echo ""
echo ""

# Test connection
echo "Testing connection to Redshift..."
PGPASSWORD=$REDSHIFT_PASSWORD psql \
    -h $REDSHIFT_ENDPOINT \
    -p $REDSHIFT_PORT \
    -U $REDSHIFT_USER \
    -d $REDSHIFT_DB \
    -c "SELECT version();" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "✓ Connection successful"
else
    echo "✗ Connection failed"
    echo "Please check your credentials and ensure you can connect to Redshift"
    exit 1
fi

echo ""

# Execute SQL scripts in order
echo "Executing SQL scripts..."

scripts=(
    "schemas/01_create_schemas.sql"
    "schemas/02_create_control_tables.sql"
    "schemas/03_configure_wlm.sql"
    "schemas/04_create_dimension_tables.sql"
    "schemas/05_populate_dim_date.sql"
)

for script in "${scripts[@]}"; do
    echo "  - Executing $script"
    PGPASSWORD=$REDSHIFT_PASSWORD psql \
        -h $REDSHIFT_ENDPOINT \
        -p $REDSHIFT_PORT \
        -U $REDSHIFT_USER \
        -d $REDSHIFT_DB \
        -f $script \
        -v ON_ERROR_STOP=1 \
        --quiet
    
    if [ $? -eq 0 ]; then
        echo "    ✓ Success"
    else
        echo "    ✗ Failed"
        exit 1
    fi
done

echo ""
echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo ""

# Verify deployment
echo "Verifying deployment..."
echo ""

PGPASSWORD=$REDSHIFT_PASSWORD psql \
    -h $REDSHIFT_ENDPOINT \
    -p $REDSHIFT_PORT \
    -U $REDSHIFT_USER \
    -d $REDSHIFT_DB \
    -c "
    SELECT 
        schemaname AS schema,
        COUNT(*) AS table_count
    FROM pg_tables
    WHERE schemaname IN ('staging', 'integration', 'presentation', 'control')
    GROUP BY schemaname
    ORDER BY schemaname;
    "

echo ""
echo "Dimension table row counts:"
PGPASSWORD=$REDSHIFT_PASSWORD psql \
    -h $REDSHIFT_ENDPOINT \
    -p $REDSHIFT_PORT \
    -U $REDSHIFT_USER \
    -d $REDSHIFT_DB \
    -c "
    SELECT 
        'dim_date' AS table_name,
        COUNT(*) AS row_count
    FROM presentation.dim_date
    UNION ALL
    SELECT 
        'dim_security' AS table_name,
        COUNT(*) AS row_count
    FROM presentation.dim_security
    UNION ALL
    SELECT 
        'dim_index_constituents' AS table_name,
        COUNT(*) AS row_count
    FROM presentation.dim_index_constituents;
    "

echo ""
echo "Next Steps:"
echo "1. Review WLM configuration in AWS Console"
echo "2. Create users and assign to groups"
echo "3. Load initial security master data"
echo "4. Proceed to Task 4: Implement temporal data model"
