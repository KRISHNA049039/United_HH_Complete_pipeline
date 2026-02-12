-- =====================================================
-- Redshift Concurrency Scaling and Auto-Scaling Configuration
-- =====================================================

-- =====================================================
-- 1. Enable Concurrency Scaling
-- =====================================================

-- Concurrency scaling allows Redshift to automatically add cluster capacity
-- to handle increases in concurrent read queries

-- Enable concurrency scaling for analyst queue
-- This allows up to 10 additional clusters to handle query spikes

-- First, check current WLM configuration
SELECT * FROM stv_wlm_service_class_config;

-- =====================================================
-- 2. Configure WLM Queues with Concurrency Scaling
-- =====================================================

-- WLM configuration should be done via AWS Console or CLI
-- Here's the recommended configuration:

/*
Queue Configuration:

Queue 1 - ETL Queue:
- Memory: 40%
- Concurrency: 2
- Timeout: 3600 seconds (1 hour)
- Concurrency Scaling: OFF
- Priority: NORMAL

Queue 2 - Analyst Queue:
- Memory: 50%
- Concurrency: 5
- Timeout: 300 seconds (5 minutes)
- Concurrency Scaling: ON (max 10 clusters)
- Priority: NORMAL

Queue 3 - Admin Queue:
- Memory: 10%
- Concurrency: 1
- Timeout: None
- Concurrency Scaling: OFF
- Priority: HIGHEST
*/

-- =====================================================
-- 3. Set Query Group for Routing
-- =====================================================

-- Queries can be routed to specific queues using query groups

-- For ETL jobs:
SET query_group TO 'etl';

-- For analyst queries:
SET query_group TO 'analyst';

-- For admin queries:
SET query_group TO 'admin';

-- Reset to default:
RESET query_group;


-- =====================================================
-- 4. Monitor Concurrency Scaling Usage
-- =====================================================

-- Check concurrency scaling usage
SELECT 
    DATE_TRUNC('hour', start_time) as hour,
    COUNT(*) as queries_on_concurrency_cluster,
    SUM(charged_seconds) / 3600.0 as charged_hours
FROM stl_concurrency_scaling_usage
WHERE start_time >= DATEADD(day, -7, CURRENT_DATE)
GROUP BY DATE_TRUNC('hour', start_time)
ORDER BY hour DESC;

-- Check which queries used concurrency scaling
SELECT 
    query,
    start_time,
    end_time,
    DATEDIFF(seconds, start_time, end_time) as duration_seconds,
    charged_seconds
FROM stl_concurrency_scaling_usage
WHERE start_time >= DATEADD(day, -1, CURRENT_DATE)
ORDER BY start_time DESC
LIMIT 50;

-- =====================================================
-- 5. Scheduled Cluster Scaling
-- =====================================================

-- Redshift supports scheduled actions for scaling
-- These should be configured via AWS CLI or Console

-- Example AWS CLI commands (run from command line, not SQL):

/*
# Scale up to 4 nodes during peak hours (8 AM IST)
aws redshift create-scheduled-action \
    --scheduled-action-name scale-up-peak-hours \
    --target-action ResizeCluster={ClusterIdentifier=research-platform-cluster,NumberOfNodes=4} \
    --schedule "cron(30 2 * * ? *)" \
    --iam-role arn:aws:iam::ACCOUNT_ID:role/RedshiftScheduledActionRole

# Scale down to 2 nodes during off-hours (6 PM IST)
aws redshift create-scheduled-action \
    --scheduled-action-name scale-down-off-hours \
    --target-action ResizeCluster={ClusterIdentifier=research-platform-cluster,NumberOfNodes=2} \
    --schedule "cron(30 12 * * ? *)" \
    --iam-role arn:aws:iam::ACCOUNT_ID:role/RedshiftScheduledActionRole

# Pause cluster during nights (11 PM IST)
aws redshift create-scheduled-action \
    --scheduled-action-name pause-cluster-night \
    --target-action PauseCluster={ClusterIdentifier=research-platform-cluster} \
    --schedule "cron(30 17 * * ? *)" \
    --iam-role arn:aws:iam::ACCOUNT_ID:role/RedshiftScheduledActionRole

# Resume cluster in morning (7 AM IST)
aws redshift create-scheduled-action \
    --scheduled-action-name resume-cluster-morning \
    --target-action ResumeCluster={ClusterIdentifier=research-platform-cluster} \
    --schedule "cron(30 1 * * ? *)" \
    --iam-role arn:aws:iam::ACCOUNT_ID:role/RedshiftScheduledActionRole
*/


-- =====================================================
-- 6. Monitor Queue Performance
-- =====================================================

-- Check queue wait times
SELECT 
    service_class,
    COUNT(*) as query_count,
    AVG(total_queue_time) / 1000000 as avg_queue_seconds,
    MAX(total_queue_time) / 1000000 as max_queue_seconds,
    AVG(total_exec_time) / 1000000 as avg_exec_seconds
FROM stl_wlm_query
WHERE userid > 1
  AND service_class > 4
  AND exec_start_time >= DATEADD(day, -1, CURRENT_DATE)
GROUP BY service_class
ORDER BY service_class;

-- Check queries that waited in queue
SELECT 
    query,
    service_class,
    queue_start_time,
    queue_end_time,
    total_queue_time / 1000000 as queue_seconds,
    total_exec_time / 1000000 as exec_seconds
FROM stl_wlm_query
WHERE userid > 1
  AND total_queue_time > 0
  AND exec_start_time >= DATEADD(day, -1, CURRENT_DATE)
ORDER BY queue_seconds DESC
LIMIT 50;

-- =====================================================
-- 7. Cost Monitoring
-- =====================================================

-- Monitor concurrency scaling costs
CREATE OR REPLACE VIEW control.concurrency_scaling_costs AS
SELECT 
    DATE_TRUNC('day', start_time) as date,
    COUNT(*) as queries_scaled,
    SUM(charged_seconds) / 3600.0 as charged_hours,
    -- Approximate cost (adjust rate based on region)
    (SUM(charged_seconds) / 3600.0) * 5.0 as estimated_cost_usd
FROM stl_concurrency_scaling_usage
WHERE start_time >= DATEADD(day, -30, CURRENT_DATE)
GROUP BY DATE_TRUNC('day', start_time)
ORDER BY date DESC;

-- Query the costs
SELECT * FROM control.concurrency_scaling_costs
ORDER BY date DESC;

-- =====================================================
-- 8. Auto-Scaling Recommendations
-- =====================================================

-- Check if cluster is under-utilized (candidate for scaling down)
SELECT 
    DATE_TRUNC('hour', starttime) as hour,
    AVG(cpu_usage) as avg_cpu_pct,
    AVG(disk_usage) as avg_disk_pct,
    COUNT(*) as query_count
FROM (
    SELECT 
        starttime,
        -- Approximate CPU usage based on query duration
        CASE 
            WHEN DATEDIFF(seconds, starttime, endtime) > 60 THEN 80
            WHEN DATEDIFF(seconds, starttime, endtime) > 30 THEN 50
            ELSE 20
        END as cpu_usage,
        50 as disk_usage  -- Placeholder
    FROM stl_query
    WHERE userid > 1
      AND starttime >= DATEADD(day, -7, CURRENT_DATE)
) q
GROUP BY DATE_TRUNC('hour', starttime)
ORDER BY hour DESC;

-- =====================================================
-- 9. Best Practices Summary
-- =====================================================

/*
Concurrency Scaling Best Practices:

1. Enable for read-heavy workloads (analyst queries)
2. Don't enable for ETL/write workloads
3. Set appropriate timeout limits to prevent runaway queries
4. Monitor costs daily
5. Use query groups to route queries to appropriate queues

Auto-Scaling Best Practices:

1. Scale up during peak hours (8 AM - 6 PM IST)
2. Scale down during off-hours
3. Pause cluster during nights/weekends if not needed
4. Monitor query queue times to determine if scaling is needed
5. Use elastic resize for faster scaling (minutes vs hours)

Cost Optimization:

1. Use concurrency scaling free tier (1 hour per day)
2. Pause cluster when not in use
3. Right-size cluster based on actual usage
4. Use RA3 nodes for better price/performance
5. Monitor and optimize expensive queries
*/

-- =====================================================
-- End of Scaling Configuration
-- =====================================================
