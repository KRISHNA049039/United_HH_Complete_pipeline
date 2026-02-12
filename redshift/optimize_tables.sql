-- =====================================================
-- Redshift Table Optimization Script
-- Analyzes and optimizes table design for performance
-- =====================================================

-- =====================================================
-- 1. Analyze Compression
-- =====================================================

-- Run ANALYZE COMPRESSION on all fact tables
ANALYZE COMPRESSION fact_daily_prices;
ANALYZE COMPRESSION fact_quarterly_financials;
ANALYZE COMPRESSION fact_institutional_flows;

-- Run ANALYZE COMPRESSION on large dimension tables
ANALYZE COMPRESSION dim_security;
ANALYZE COMPRESSION dim_index_constituents;

-- Run ANALYZE COMPRESSION on vault tables
ANALYZE COMPRESSION vault_financials;
ANALYZE COMPRESSION vault_prices;

-- =====================================================
-- 2. Update Table Statistics
-- =====================================================

-- Analyze all tables to update statistics for query planner
ANALYZE fact_daily_prices;
ANALYZE fact_quarterly_financials;
ANALYZE fact_institutional_flows;
ANALYZE dim_security;
ANALYZE dim_date;
ANALYZE dim_index_constituents;
ANALYZE vault_financials;
ANALYZE vault_prices;
ANALYZE corporate_actions;
ANALYZE price_adjustments;

-- =====================================================
-- 3. Verify DISTKEY and SORTKEY Configuration
-- =====================================================

-- Query to check current distribution and sort keys
SELECT 
    schemaname,
    tablename,
    "column",
    distkey,
    sortkey,
    encoding
FROM pg_table_def
WHERE schemaname IN ('presentation', 'integration', 'staging')
ORDER BY schemaname, tablename, sortkey;


-- =====================================================
-- 4. Check Table Skew (Distribution Balance)
-- =====================================================

-- Check if data is evenly distributed across nodes
SELECT 
    slice,
    COUNT(*) as row_count
FROM fact_daily_prices
GROUP BY slice
ORDER BY slice;

-- Check skew ratio for fact tables
SELECT 
    'fact_daily_prices' as table_name,
    MAX(row_count) * 1.0 / NULLIF(MIN(row_count), 0) as skew_ratio
FROM (
    SELECT slice, COUNT(*) as row_count
    FROM fact_daily_prices
    GROUP BY slice
);

-- =====================================================
-- 5. VACUUM Operations
-- =====================================================

-- VACUUM to reclaim space and re-sort rows
-- Run during maintenance window (low activity period)

-- Full vacuum on fact tables
VACUUM FULL fact_daily_prices;
VACUUM FULL fact_quarterly_financials;
VACUUM FULL fact_institutional_flows;

-- Sort-only vacuum (faster, doesn't reclaim space)
VACUUM SORT ONLY fact_daily_prices;
VACUUM SORT ONLY fact_quarterly_financials;

-- Delete-only vacuum (reclaim space from deleted rows)
VACUUM DELETE ONLY fact_daily_prices;

-- =====================================================
-- 6. Enable Automatic Table Optimization (ATO)
-- =====================================================

-- Enable ATO for automatic sort key and distribution optimization
ALTER TABLE fact_daily_prices ALTER SORTKEY AUTO;
ALTER TABLE fact_quarterly_financials ALTER SORTKEY AUTO;
ALTER TABLE fact_institutional_flows ALTER SORTKEY AUTO;

-- Enable automatic distribution
ALTER TABLE fact_daily_prices ALTER DISTSTYLE AUTO;
ALTER TABLE fact_quarterly_financials ALTER DISTSTYLE AUTO;
ALTER TABLE fact_institutional_flows ALTER DISTSTYLE AUTO;


-- =====================================================
-- 7. Query Performance Analysis
-- =====================================================

-- Find slow queries from system tables
SELECT 
    query,
    TRIM(querytxt) as query_text,
    starttime,
    endtime,
    DATEDIFF(seconds, starttime, endtime) as duration_seconds,
    aborted
FROM stl_query
WHERE userid > 1  -- Exclude system queries
  AND DATEDIFF(seconds, starttime, endtime) > 30  -- Queries > 30 seconds
ORDER BY duration_seconds DESC
LIMIT 20;

-- Check for queries with high disk usage
SELECT 
    q.query,
    TRIM(q.querytxt) as query_text,
    d.bytes / 1024 / 1024 as disk_mb,
    q.starttime
FROM stl_query q
JOIN stl_disk_full_diag d ON q.query = d.query
WHERE q.userid > 1
ORDER BY disk_mb DESC
LIMIT 20;

-- =====================================================
-- 8. Table Size and Growth Analysis
-- =====================================================

-- Check table sizes
SELECT 
    schemaname,
    tablename,
    SUM(rows) as total_rows,
    SUM(size) / 1024 / 1024 as size_mb,
    SUM(size) / 1024 / 1024 / 1024 as size_gb
FROM svv_table_info
WHERE schemaname IN ('presentation', 'integration', 'staging')
GROUP BY schemaname, tablename
ORDER BY size_mb DESC;

-- Check unsorted data percentage
SELECT 
    schemaname,
    tablename,
    unsorted,
    CASE 
        WHEN unsorted > 20 THEN 'VACUUM RECOMMENDED'
        WHEN unsorted > 10 THEN 'MONITOR'
        ELSE 'OK'
    END as status
FROM svv_table_info
WHERE schemaname IN ('presentation', 'integration', 'staging')
  AND unsorted > 0
ORDER BY unsorted DESC;

-- =====================================================
-- 9. Workload Management (WLM) Configuration Check
-- =====================================================

-- Check current WLM queue configuration
SELECT * FROM stv_wlm_service_class_config
ORDER BY service_class;

-- Check query queue wait times
SELECT 
    service_class,
    COUNT(*) as query_count,
    AVG(total_queue_time) / 1000000 as avg_queue_time_seconds,
    MAX(total_queue_time) / 1000000 as max_queue_time_seconds
FROM stl_wlm_query
WHERE userid > 1
  AND service_class > 4  -- User-defined queues
GROUP BY service_class
ORDER BY service_class;


-- =====================================================
-- 10. Optimization Recommendations
-- =====================================================

-- Create a summary view of optimization opportunities
CREATE OR REPLACE VIEW control.table_optimization_recommendations AS
SELECT 
    schemaname,
    tablename,
    CASE 
        WHEN unsorted > 20 THEN 'HIGH: Run VACUUM'
        WHEN unsorted > 10 THEN 'MEDIUM: Schedule VACUUM'
        ELSE NULL
    END as vacuum_recommendation,
    CASE 
        WHEN stats_off > 10 THEN 'HIGH: Run ANALYZE'
        WHEN stats_off > 5 THEN 'MEDIUM: Schedule ANALYZE'
        ELSE NULL
    END as analyze_recommendation,
    CASE 
        WHEN skew_rows > 2.0 THEN 'HIGH: Review DISTKEY'
        WHEN skew_rows > 1.5 THEN 'MEDIUM: Monitor distribution'
        ELSE NULL
    END as distribution_recommendation,
    unsorted as unsorted_pct,
    stats_off as stats_off_pct,
    skew_rows as skew_ratio,
    size / 1024 / 1024 as size_mb
FROM svv_table_info
WHERE schemaname IN ('presentation', 'integration', 'staging')
  AND (unsorted > 5 OR stats_off > 5 OR skew_rows > 1.5);

-- Query the recommendations
SELECT * FROM control.table_optimization_recommendations
ORDER BY 
    CASE 
        WHEN vacuum_recommendation LIKE 'HIGH%' THEN 1
        WHEN analyze_recommendation LIKE 'HIGH%' THEN 2
        WHEN distribution_recommendation LIKE 'HIGH%' THEN 3
        ELSE 4
    END,
    size_mb DESC;

-- =====================================================
-- 11. Scheduled Maintenance Script
-- =====================================================

-- This should be run during off-hours (e.g., 2 AM daily)
-- Can be scheduled using Redshift scheduled queries or Airflow

-- Step 1: Analyze tables
ANALYZE fact_daily_prices;
ANALYZE fact_quarterly_financials;
ANALYZE fact_institutional_flows;

-- Step 2: Vacuum tables with high unsorted percentage
-- (Only if unsorted > 20%)
-- VACUUM SORT ONLY fact_daily_prices;

-- Step 3: Update statistics
ANALYZE;

-- =====================================================
-- 12. Performance Monitoring Queries
-- =====================================================

-- Monitor query performance over time
CREATE OR REPLACE VIEW control.query_performance_metrics AS
SELECT 
    DATE_TRUNC('hour', starttime) as hour,
    COUNT(*) as query_count,
    AVG(DATEDIFF(seconds, starttime, endtime)) as avg_duration_seconds,
    MAX(DATEDIFF(seconds, starttime, endtime)) as max_duration_seconds,
    SUM(CASE WHEN aborted = 1 THEN 1 ELSE 0 END) as aborted_count
FROM stl_query
WHERE userid > 1
  AND starttime >= DATEADD(day, -7, CURRENT_DATE)
GROUP BY DATE_TRUNC('hour', starttime)
ORDER BY hour DESC;

-- Query the metrics
SELECT * FROM control.query_performance_metrics
ORDER BY hour DESC
LIMIT 168;  -- Last 7 days

-- =====================================================
-- End of Optimization Script
-- =====================================================
