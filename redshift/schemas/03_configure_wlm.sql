-- Configure Workload Management (WLM) Queues
-- This script provides the WLM configuration to be applied via AWS Console or CLI

/*
WLM Configuration for Research Data Platform

Apply this configuration via AWS Console:
1. Go to Redshift Console
2. Select your cluster
3. Click "Workload management" tab
4. Click "Edit" and paste the JSON below

Or via AWS CLI:
aws redshift modify-cluster-parameter-group \
    --parameter-group-name <your-parameter-group> \
    --parameters ParameterName=wlm_json_configuration,ParameterValue='<json-below>'

WLM JSON Configuration:
*/

/*
[
  {
    "name": "etl_queue",
    "query_concurrency": 2,
    "memory_percent_to_use": 40,
    "max_execution_time": 3600000,
    "user_group": ["etl_users"],
    "query_group": ["etl"],
    "priority": "normal"
  },
  {
    "name": "analyst_queue",
    "query_concurrency": 5,
    "memory_percent_to_use": 50,
    "max_execution_time": 300000,
    "user_group": ["analyst_users"],
    "query_group": ["analyst"],
    "priority": "normal"
  },
  {
    "name": "admin_queue",
    "query_concurrency": 1,
    "memory_percent_to_use": 10,
    "max_execution_time": 0,
    "user_group": ["admin_users"],
    "query_group": ["admin"],
    "priority": "highest"
  }
]
*/

-- =====================================================
-- Create User Groups
-- =====================================================

-- ETL Users Group
CREATE GROUP etl_users;

-- Analyst Users Group
CREATE GROUP analyst_users;

-- Admin Users Group
CREATE GROUP admin_users;

-- =====================================================
-- Grant Permissions to Groups
-- =====================================================

-- ETL Users: Full access to staging and integration schemas
GRANT USAGE ON SCHEMA staging TO GROUP etl_users;
GRANT USAGE ON SCHEMA integration TO GROUP etl_users;
GRANT USAGE ON SCHEMA control TO GROUP etl_users;

GRANT ALL ON ALL TABLES IN SCHEMA staging TO GROUP etl_users;
GRANT ALL ON ALL TABLES IN SCHEMA integration TO GROUP etl_users;
GRANT ALL ON ALL TABLES IN SCHEMA control TO GROUP etl_users;

-- Analyst Users: Read access to presentation schema
GRANT USAGE ON SCHEMA presentation TO GROUP analyst_users;
GRANT SELECT ON ALL TABLES IN SCHEMA presentation TO GROUP analyst_users;

-- Admin Users: Full access to all schemas
GRANT ALL ON SCHEMA staging TO GROUP admin_users;
GRANT ALL ON SCHEMA integration TO GROUP admin_users;
GRANT ALL ON SCHEMA presentation TO GROUP admin_users;
GRANT ALL ON SCHEMA control TO GROUP admin_users;

GRANT ALL ON ALL TABLES IN SCHEMA staging TO GROUP admin_users;
GRANT ALL ON ALL TABLES IN SCHEMA integration TO GROUP admin_users;
GRANT ALL ON ALL TABLES IN SCHEMA presentation TO GROUP admin_users;
GRANT ALL ON ALL TABLES IN SCHEMA control TO GROUP admin_users;

-- =====================================================
-- Create Sample Users (Optional)
-- =====================================================

-- Create ETL service user
-- CREATE USER etl_service PASSWORD 'CHANGE_ME' IN GROUP etl_users;

-- Create analyst users
-- CREATE USER analyst1 PASSWORD 'CHANGE_ME' IN GROUP analyst_users;
-- CREATE USER analyst2 PASSWORD 'CHANGE_ME' IN GROUP analyst_users;

-- Create admin user
-- CREATE USER platform_admin PASSWORD 'CHANGE_ME' IN GROUP admin_users;

-- =====================================================
-- Query Group Assignment
-- =====================================================

-- Users can set their query group to route to specific WLM queue
-- SET query_group TO 'etl';
-- SET query_group TO 'analyst';
-- SET query_group TO 'admin';

-- =====================================================
-- WLM Queue Monitoring Queries
-- =====================================================

-- View current WLM configuration
-- SELECT * FROM stv_wlm_service_class_config;

-- View queries in WLM queues
-- SELECT * FROM stv_wlm_query_state;

-- View WLM queue metrics
-- SELECT service_class, num_queued_queries, num_executing_queries
-- FROM stv_wlm_service_class_state;

COMMIT;

-- =====================================================
-- Notes
-- =====================================================

/*
WLM Queue Configuration Summary:

1. ETL Queue (40% memory, 2 slots, 1 hour timeout)
   - For data loading and transformation jobs
   - Lower concurrency for large batch operations
   - Long timeout for complex transformations

2. Analyst Queue (50% memory, 5 slots, 5 minute timeout)
   - For interactive analyst queries
   - Higher concurrency for multiple users
   - Shorter timeout to prevent runaway queries

3. Admin Queue (10% memory, 1 slot, no timeout)
   - For administrative operations
   - Highest priority
   - No timeout for maintenance tasks

Concurrency Scaling:
- Enable for analyst queue to handle peak loads
- Up to 10 additional clusters
- Automatically scales based on queue depth

Short Query Acceleration (SQA):
- Automatically prioritizes short queries
- Recommended: Enable with 5-10 second threshold
- Bypasses WLM queue for fast queries
*/
