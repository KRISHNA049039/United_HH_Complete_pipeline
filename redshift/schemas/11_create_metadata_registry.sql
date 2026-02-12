-- Metadata Registry for Query Validation
-- Centralized schema metadata for query validation and natural language translation

-- =====================================================
-- METADATA_TABLES
-- =====================================================
-- Catalog of all tables with their characteristics

CREATE TABLE IF NOT EXISTS control.metadata_tables (
    table_id INTEGER IDENTITY(1,1) PRIMARY KEY,
    schema_name VARCHAR(100) NOT NULL,
    table_name VARCHAR(200) NOT NULL,
    table_type VARCHAR(20) NOT NULL, -- FACT, DIMENSION, VIEW, MATERIALIZED_VIEW
    temporal_type VARCHAR(50), -- POINT_IN_TIME, SNAPSHOT, IMMUTABLE, TEMPORAL_VAULT
    description TEXT,
    primary_date_column VARCHAR(100),
    primary_key_columns VARCHAR(500),
    distribution_key VARCHAR(100),
    sort_keys VARCHAR(500),
    row_count_estimate BIGINT,
    last_updated TIMESTAMP DEFAULT GETDATE(),
    is_queryable BOOLEAN DEFAULT TRUE,
    
    UNIQUE(schema_name, table_name)
)
DISTSTYLE ALL
SORTKEY(schema_name, table_name);

COMMENT ON TABLE control.metadata_tables IS 'Catalog of all tables with metadata for query validation';

-- =====================================================
-- METADATA_COLUMNS
-- =====================================================
-- Detailed column metadata with business glossary

CREATE TABLE IF NOT EXISTS control.metadata_columns (
    column_id INTEGER IDENTITY(1,1) PRIMARY KEY,
    table_id INTEGER NOT NULL,
    column_name VARCHAR(200) NOT NULL,
    data_type VARCHAR(100) NOT NULL,
    is_nullable BOOLEAN DEFAULT TRUE,
    is_temporal_key BOOLEAN DEFAULT FALSE,
    is_primary_key BOOLEAN DEFAULT FALSE,
    is_foreign_key BOOLEAN DEFAULT FALSE,
    description TEXT,
    business_glossary_term VARCHAR(200),
    sample_values VARCHAR(500),
    value_range VARCHAR(200),
    last_updated TIMESTAMP DEFAULT GETDATE()
)
DISTSTYLE ALL
SORTKEY(table_id, column_name);

COMMENT ON TABLE control.metadata_columns IS 'Column metadata with business glossary terms';

-- =====================================================
-- METADATA_RELATIONSHIPS
-- =====================================================
-- Valid table relationships and join conditions

CREATE TABLE IF NOT EXISTS control.metadata_relationships (
    relationship_id INTEGER IDENTITY(1,1) PRIMARY KEY,
    parent_table_id INTEGER NOT NULL,
    child_table_id INTEGER NOT NULL,
    relationship_type VARCHAR(50) NOT NULL, -- ONE_TO_MANY, MANY_TO_ONE, MANY_TO_MANY
    join_type VARCHAR(20) DEFAULT 'INNER', -- INNER, LEFT, RIGHT
    join_condition TEXT NOT NULL,
    temporal_constraint TEXT,
    description TEXT,
    is_valid BOOLEAN DEFAULT TRUE,
    last_updated TIMESTAMP DEFAULT GETDATE()
)
DISTSTYLE ALL
SORTKEY(parent_table_id, child_table_id);

COMMENT ON TABLE control.metadata_relationships IS 'Valid table relationships for query validation';

-- =====================================================
-- METADATA_BUSINESS_GLOSSARY
-- =====================================================
-- Business terms and their technical mappings

CREATE TABLE IF NOT EXISTS control.metadata_business_glossary (
    term_id INTEGER IDENTITY(1,1) PRIMARY KEY,
    business_term VARCHAR(200) NOT NULL UNIQUE,
    technical_term VARCHAR(200),
    definition TEXT,
    synonyms VARCHAR(500),
    category VARCHAR(100),
    example_usage TEXT,
    related_tables VARCHAR(500),
    last_updated TIMESTAMP DEFAULT GETDATE()
)
DISTSTYLE ALL
SORTKEY(business_term);

COMMENT ON TABLE control.metadata_business_glossary IS 'Business glossary for natural language translation';

-- =====================================================
-- Populate Metadata Tables
-- =====================================================

-- Insert table metadata
INSERT INTO control.metadata_tables (
    schema_name, table_name, table_type, temporal_type, description,
    primary_date_column, distribution_key, is_queryable
) VALUES
-- Dimension tables
('presentation', 'dim_security', 'DIMENSION', 'TEMPORAL_VAULT', 
 'Master dimension of all securities with Type 2 SCD', 
 'valid_from', 'ALL', TRUE),
 
('presentation', 'dim_date', 'DIMENSION', 'IMMUTABLE', 
 'Date dimension with fiscal calendar and trading days', 
 'date_key', 'ALL', TRUE),
 
('presentation', 'dim_index_constituents', 'DIMENSION', 'TEMPORAL_VAULT', 
 'Index membership history for survivorship-free analysis', 
 'effective_date', 'ALL', TRUE),
 
('presentation', 'dim_sector', 'DIMENSION', 'SNAPSHOT', 
 'Sector and industry classification hierarchy', 
 NULL, 'ALL', TRUE),

-- Fact tables
('presentation', 'fact_daily_prices', 'FACT', 'SNAPSHOT', 
 'Daily price data with corporate action adjustments', 
 'price_date', 'security_key', TRUE),
 
('presentation', 'fact_quarterly_financials', 'FACT', 'POINT_IN_TIME', 
 'Quarterly financial statements with temporal tracking', 
 'reporting_period_end', 'security_key', TRUE),
 
('presentation', 'fact_institutional_flows', 'FACT', 'SNAPSHOT', 
 'Daily FII/DII institutional flow data', 
 'flow_date', 'security_key', TRUE),

-- Materialized views
('presentation', 'mv_precomputed_ratios', 'MATERIALIZED_VIEW', 'SNAPSHOT', 
 'Precomputed financial ratios and margins', 
 'reporting_period_end', NULL, TRUE),
 
('presentation', 'mv_rolling_returns', 'MATERIALIZED_VIEW', 'SNAPSHOT', 
 'Rolling returns and momentum indicators', 
 'price_date', NULL, TRUE),
 
('presentation', 'mv_current_index_constituents', 'MATERIALIZED_VIEW', 'SNAPSHOT', 
 'Current index constituents for fast lookups', 
 NULL, NULL, TRUE),

-- Vault tables
('integration', 'vault_financials', 'FACT', 'TEMPORAL_VAULT', 
 'Historical vault for financial statements with bi-temporal tracking', 
 'reporting_period_end', 'security_id', FALSE),
 
('integration', 'vault_prices', 'FACT', 'TEMPORAL_VAULT', 
 'Historical vault for unadjusted price data', 
 'price_date', 'security_id', FALSE),
 
('integration', 'corporate_actions', 'DIMENSION', 'IMMUTABLE', 
 'Corporate action events with adjustment factors', 
 'ex_date', 'security_id', TRUE);

-- Insert column metadata for key tables
INSERT INTO control.metadata_columns (
    table_id, column_name, data_type, is_nullable, is_temporal_key, 
    description, business_glossary_term
)
SELECT 
    t.table_id,
    'security_key',
    'INTEGER',
    FALSE,
    FALSE,
    'Surrogate key for security dimension',
    'Security Identifier'
FROM control.metadata_tables t
WHERE t.table_name IN ('fact_daily_prices', 'fact_quarterly_financials', 'fact_institutional_flows');

-- Insert relationships
INSERT INTO control.metadata_relationships (
    parent_table_id, child_table_id, relationship_type, join_condition, temporal_constraint
)
SELECT 
    (SELECT table_id FROM control.metadata_tables WHERE table_name = 'dim_security'),
    (SELECT table_id FROM control.metadata_tables WHERE table_name = 'fact_daily_prices'),
    'ONE_TO_MANY',
    'dim_security.security_key = fact_daily_prices.security_key',
    'dim_security.is_current = TRUE';

-- Insert business glossary terms
INSERT INTO control.metadata_business_glossary (
    business_term, technical_term, definition, synonyms, category
) VALUES
('Revenue', 'revenue', 'Total income from business operations', 'Sales,Turnover,Top Line', 'Financial Metrics'),
('EBITDA', 'ebitda', 'Earnings Before Interest, Taxes, Depreciation, and Amortization', 'Operating Profit', 'Financial Metrics'),
('Market Cap', 'approx_market_cap', 'Total market value of company shares', 'Market Capitalization,Market Value', 'Valuation'),
('Return on Equity', 'roe_pct', 'Net income as percentage of shareholder equity', 'ROE', 'Financial Ratios'),
('Stock Price', 'close_price', 'Closing price of security', 'Price,Close,Closing Price', 'Market Data'),
('FII Flow', 'net_fii_flow', 'Net Foreign Institutional Investor flow', 'Foreign Investment,FII', 'Flows'),
('Index Constituents', 'index_name', 'Securities that are members of an index', 'Index Members,Index Stocks', 'Index Data');

COMMIT;

-- =====================================================
-- Query Validation Functions
-- =====================================================

CREATE OR REPLACE FUNCTION control.validate_table_access(
    p_schema_name VARCHAR(100),
    p_table_name VARCHAR(200)
)
RETURNS BOOLEAN
AS $$
DECLARE
    v_is_queryable BOOLEAN;
BEGIN
    SELECT is_queryable INTO v_is_queryable
    FROM control.metadata_tables
    WHERE schema_name = p_schema_name
      AND table_name = p_table_name;
    
    RETURN COALESCE(v_is_queryable, FALSE);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION control.validate_table_access IS 'Validate if table can be queried';

CREATE OR REPLACE FUNCTION control.get_valid_joins(
    p_table_name VARCHAR(200)
)
RETURNS TABLE (
    related_table VARCHAR(200),
    join_condition TEXT,
    temporal_constraint TEXT
)
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        t2.table_name AS related_table,
        r.join_condition,
        r.temporal_constraint
    FROM control.metadata_relationships r
    JOIN control.metadata_tables t1 ON r.parent_table_id = t1.table_id
    JOIN control.metadata_tables t2 ON r.child_table_id = t2.table_id
    WHERE t1.table_name = p_table_name
      AND r.is_valid = TRUE
    UNION
    SELECT 
        t1.table_name AS related_table,
        r.join_condition,
        r.temporal_constraint
    FROM control.metadata_relationships r
    JOIN control.metadata_tables t1 ON r.parent_table_id = t1.table_id
    JOIN control.metadata_tables t2 ON r.child_table_id = t2.table_id
    WHERE t2.table_name = p_table_name
      AND r.is_valid = TRUE;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION control.get_valid_joins IS 'Get valid join relationships for a table';

CREATE OR REPLACE FUNCTION control.translate_business_term(
    p_business_term VARCHAR(200)
)
RETURNS VARCHAR(200)
AS $$
DECLARE
    v_technical_term VARCHAR(200);
BEGIN
    SELECT technical_term INTO v_technical_term
    FROM control.metadata_business_glossary
    WHERE LOWER(business_term) = LOWER(p_business_term)
       OR LOWER(synonyms) LIKE '%' || LOWER(p_business_term) || '%';
    
    RETURN v_technical_term;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION control.translate_business_term IS 'Translate business term to technical column name';

-- =====================================================
-- Metadata Maintenance Procedures
-- =====================================================

CREATE OR REPLACE PROCEDURE control.refresh_metadata_from_catalog()
AS $$
BEGIN
    -- Update row count estimates
    UPDATE control.metadata_tables mt
    SET row_count_estimate = (
        SELECT reltuples::BIGINT
        FROM pg_class c
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = mt.schema_name
          AND c.relname = mt.table_name
    ),
    last_updated = GETDATE();
    
    -- Log refresh
    INSERT INTO control.etl_job_log (job_name, start_time, end_time, status)
    VALUES ('refresh_metadata_from_catalog', GETDATE(), GETDATE(), 'SUCCESS');
END;
$$ LANGUAGE plpgsql;

COMMENT ON PROCEDURE control.refresh_metadata_from_catalog IS 'Refresh metadata from system catalog';

-- =====================================================
-- Views for Easy Access
-- =====================================================

CREATE OR REPLACE VIEW control.v_metadata_catalog AS
SELECT 
    t.schema_name,
    t.table_name,
    t.table_type,
    t.temporal_type,
    t.description,
    t.primary_date_column,
    t.row_count_estimate,
    COUNT(c.column_id) AS column_count
FROM control.metadata_tables t
LEFT JOIN control.metadata_columns c ON t.table_id = c.table_id
WHERE t.is_queryable = TRUE
GROUP BY 
    t.schema_name, t.table_name, t.table_type, t.temporal_type,
    t.description, t.primary_date_column, t.row_count_estimate;

COMMENT ON VIEW control.v_metadata_catalog IS 'Simplified metadata catalog view';

COMMIT;

-- =====================================================
-- Usage Examples
-- =====================================================

/*
-- Check if table can be queried
SELECT control.validate_table_access('presentation', 'fact_daily_prices');

-- Get valid joins for a table
SELECT * FROM control.get_valid_joins('fact_daily_prices');

-- Translate business term to technical term
SELECT control.translate_business_term('Revenue');
SELECT control.translate_business_term('Market Cap');

-- View metadata catalog
SELECT * FROM control.v_metadata_catalog
WHERE schema_name = 'presentation'
ORDER BY table_type, table_name;

-- Find tables with temporal tracking
SELECT schema_name, table_name, temporal_type, description
FROM control.metadata_tables
WHERE temporal_type IN ('POINT_IN_TIME', 'TEMPORAL_VAULT')
ORDER BY schema_name, table_name;

-- Get all business terms in a category
SELECT business_term, definition, synonyms
FROM control.metadata_business_glossary
WHERE category = 'Financial Metrics'
ORDER BY business_term;

-- Refresh metadata
CALL control.refresh_metadata_from_catalog();
*/
