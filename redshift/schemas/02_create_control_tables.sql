-- Create Control Tables for ETL Metadata and Job Tracking

-- =====================================================
-- ETL High Water Marks
-- =====================================================
-- Tracks the last processed date for incremental loading

CREATE TABLE IF NOT EXISTS control.etl_high_water_marks (
    table_name VARCHAR(200) PRIMARY KEY,
    high_water_mark DATE NOT NULL,
    last_updated TIMESTAMP NOT NULL DEFAULT GETDATE(),
    job_name VARCHAR(200),
    records_processed BIGINT,
    notes VARCHAR(500)
)
DISTSTYLE ALL
SORTKEY(table_name);

COMMENT ON TABLE control.etl_high_water_marks IS 'Tracks last processed date for incremental ETL jobs';

-- =====================================================
-- ETL Job Execution Log
-- =====================================================
-- Comprehensive log of all ETL job executions

CREATE TABLE IF NOT EXISTS control.etl_job_log (
    job_log_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    job_name VARCHAR(200) NOT NULL,
    job_run_id VARCHAR(200),
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP,
    status VARCHAR(20) NOT NULL, -- RUNNING, SUCCESS, FAILED
    records_processed BIGINT,
    records_inserted BIGINT,
    records_updated BIGINT,
    records_failed BIGINT,
    source_file VARCHAR(500),
    error_message VARCHAR(MAX),
    execution_time_seconds INTEGER
)
DISTSTYLE EVEN
SORTKEY(start_time);

COMMENT ON TABLE control.etl_job_log IS 'Execution log for all ETL jobs';

-- =====================================================
-- Data Quality Check Results
-- =====================================================
-- Stores results of data quality validation checks

CREATE TABLE IF NOT EXISTS control.data_quality_results (
    check_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    check_name VARCHAR(200) NOT NULL,
    table_name VARCHAR(200) NOT NULL,
    check_timestamp TIMESTAMP NOT NULL DEFAULT GETDATE(),
    check_status VARCHAR(20) NOT NULL, -- PASS, FAIL, WARNING
    records_checked BIGINT,
    records_failed BIGINT,
    failure_details VARCHAR(MAX),
    check_query VARCHAR(MAX)
)
DISTSTYLE EVEN
SORTKEY(check_timestamp);

COMMENT ON TABLE control.data_quality_results IS 'Results of data quality validation checks';

-- =====================================================
-- Schema Version Control
-- =====================================================
-- Tracks database schema versions and migrations

CREATE TABLE IF NOT EXISTS control.schema_versions (
    version_id INTEGER PRIMARY KEY,
    version_number VARCHAR(20) NOT NULL,
    description VARCHAR(500),
    applied_by VARCHAR(100),
    applied_at TIMESTAMP NOT NULL DEFAULT GETDATE(),
    script_name VARCHAR(200)
)
DISTSTYLE ALL
SORTKEY(version_id);

COMMENT ON TABLE control.schema_versions IS 'Database schema version history';

-- Insert initial version
INSERT INTO control.schema_versions (version_id, version_number, description, applied_by, script_name)
VALUES (1, '1.0.0', 'Initial schema creation', CURRENT_USER, '02_create_control_tables.sql');

-- =====================================================
-- Query Audit Log
-- =====================================================
-- Tracks all queries executed through the API layer

CREATE TABLE IF NOT EXISTS control.query_audit_log (
    query_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    user_name VARCHAR(100),
    query_text VARCHAR(MAX),
    query_timestamp TIMESTAMP NOT NULL DEFAULT GETDATE(),
    execution_time_ms INTEGER,
    rows_returned BIGINT,
    query_status VARCHAR(20), -- SUCCESS, FAILED, TIMEOUT
    error_message VARCHAR(MAX),
    source_application VARCHAR(100)
)
DISTSTYLE EVEN
SORTKEY(query_timestamp);

COMMENT ON TABLE control.query_audit_log IS 'Audit log of all queries executed';

COMMIT;
