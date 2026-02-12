-- Create Historical Vault Tables for Bi-Temporal Storage
-- Implements immutable append-only storage with valid time and transaction time

-- =====================================================
-- VAULT_FINANCIALS
-- =====================================================
-- Stores all versions of financial statement data
-- Supports financial restatements by maintaining multiple versions

CREATE TABLE IF NOT EXISTS integration.vault_financials (
    vault_key BIGINT IDENTITY(1,1) PRIMARY KEY,
    security_id VARCHAR(50) NOT NULL,
    reporting_period_end DATE NOT NULL,
    publication_date DATE NOT NULL,
    
    -- Financial metrics
    revenue DECIMAL(18,2),
    cost_of_revenue DECIMAL(18,2),
    gross_profit DECIMAL(18,2),
    operating_expenses DECIMAL(18,2),
    ebitda DECIMAL(18,2),
    ebit DECIMAL(18,2),
    interest_expense DECIMAL(18,2),
    tax_expense DECIMAL(18,2),
    net_income DECIMAL(18,2),
    
    -- Balance sheet
    total_assets DECIMAL(18,2),
    current_assets DECIMAL(18,2),
    non_current_assets DECIMAL(18,2),
    total_liabilities DECIMAL(18,2),
    current_liabilities DECIMAL(18,2),
    non_current_liabilities DECIMAL(18,2),
    total_equity DECIMAL(18,2),
    
    -- Cash flow
    operating_cash_flow DECIMAL(18,2),
    investing_cash_flow DECIMAL(18,2),
    financing_cash_flow DECIMAL(18,2),
    free_cash_flow DECIMAL(18,2),
    
    -- Temporal tracking
    valid_from TIMESTAMP NOT NULL DEFAULT GETDATE(),
    valid_to TIMESTAMP,
    is_current BOOLEAN NOT NULL DEFAULT TRUE,
    
    -- Change detection
    hash_diff VARCHAR(64) NOT NULL,
    
    -- Audit fields
    load_timestamp TIMESTAMP NOT NULL DEFAULT GETDATE(),
    source_file VARCHAR(500),
    job_name VARCHAR(200)
)
DISTSTYLE KEY
DISTKEY(security_id)
SORTKEY(security_id, reporting_period_end, publication_date);

COMMENT ON TABLE integration.vault_financials IS 'Historical vault for financial statements with bi-temporal tracking';

-- Create indexes for common queries
CREATE INDEX idx_vault_financials_current ON integration.vault_financials(security_id, is_current) 
WHERE is_current = TRUE;

CREATE INDEX idx_vault_financials_pub_date ON integration.vault_financials(publication_date);

-- =====================================================
-- VAULT_PRICES
-- =====================================================
-- Stores unadjusted price history
-- Corporate action adjustments applied in separate table

CREATE TABLE IF NOT EXISTS integration.vault_prices (
    vault_key BIGINT IDENTITY(1,1) PRIMARY KEY,
    security_id VARCHAR(50) NOT NULL,
    price_date DATE NOT NULL,
    
    -- OHLCV data (unadjusted)
    open_price DECIMAL(18,4) NOT NULL,
    high_price DECIMAL(18,4) NOT NULL,
    low_price DECIMAL(18,4) NOT NULL,
    close_price DECIMAL(18,4) NOT NULL,
    volume BIGINT,
    turnover DECIMAL(18,2),
    
    -- Temporal tracking
    valid_from TIMESTAMP NOT NULL DEFAULT GETDATE(),
    valid_to TIMESTAMP,
    is_current BOOLEAN NOT NULL DEFAULT TRUE,
    
    -- Change detection
    hash_diff VARCHAR(64) NOT NULL,
    
    -- Audit fields
    load_timestamp TIMESTAMP NOT NULL DEFAULT GETDATE(),
    source_file VARCHAR(500),
    job_name VARCHAR(200)
)
DISTSTYLE KEY
DISTKEY(security_id)
COMPOUND SORTKEY(security_id, price_date);

COMMENT ON TABLE integration.vault_prices IS 'Historical vault for unadjusted price data';

-- Create indexes
CREATE INDEX idx_vault_prices_current ON integration.vault_prices(security_id, is_current) 
WHERE is_current = TRUE;

CREATE INDEX idx_vault_prices_date ON integration.vault_prices(price_date);

-- =====================================================
-- VAULT_FLOWS
-- =====================================================
-- Stores institutional flow data

CREATE TABLE IF NOT EXISTS integration.vault_flows (
    vault_key BIGINT IDENTITY(1,1) PRIMARY KEY,
    security_id VARCHAR(50) NOT NULL,
    flow_date DATE NOT NULL,
    
    -- Flow data
    fii_buy_value DECIMAL(18,2),
    fii_sell_value DECIMAL(18,2),
    dii_buy_value DECIMAL(18,2),
    dii_sell_value DECIMAL(18,2),
    net_fii_flow DECIMAL(18,2),
    net_dii_flow DECIMAL(18,2),
    
    -- Temporal tracking
    valid_from TIMESTAMP NOT NULL DEFAULT GETDATE(),
    valid_to TIMESTAMP,
    is_current BOOLEAN NOT NULL DEFAULT TRUE,
    
    -- Change detection
    hash_diff VARCHAR(64) NOT NULL,
    
    -- Audit fields
    load_timestamp TIMESTAMP NOT NULL DEFAULT GETDATE(),
    source_file VARCHAR(500)
)
DISTSTYLE KEY
DISTKEY(security_id)
COMPOUND SORTKEY(security_id, flow_date);

COMMENT ON TABLE integration.vault_flows IS 'Historical vault for institutional flow data';

-- =====================================================
-- Stored Procedure: Insert or Update Vault Record
-- =====================================================
-- Handles SCD Type 2 logic for vault tables

CREATE OR REPLACE PROCEDURE integration.upsert_vault_financials(
    p_security_id VARCHAR(50),
    p_reporting_period_end DATE,
    p_publication_date DATE,
    p_hash_diff VARCHAR(64),
    p_revenue DECIMAL(18,2),
    p_ebitda DECIMAL(18,2),
    p_net_income DECIMAL(18,2),
    p_total_assets DECIMAL(18,2),
    p_total_liabilities DECIMAL(18,2),
    p_total_equity DECIMAL(18,2),
    p_source_file VARCHAR(500)
)
AS $$
DECLARE
    v_existing_hash VARCHAR(64);
    v_existing_key BIGINT;
BEGIN
    -- Check if record already exists with same hash
    SELECT hash_diff, vault_key INTO v_existing_hash, v_existing_key
    FROM integration.vault_financials
    WHERE security_id = p_security_id
      AND reporting_period_end = p_reporting_period_end
      AND publication_date = p_publication_date
      AND is_current = TRUE
    LIMIT 1;
    
    -- If hash is different, this is a restatement
    IF v_existing_hash IS NOT NULL AND v_existing_hash != p_hash_diff THEN
        -- Close out the old version
        UPDATE integration.vault_financials
        SET valid_to = GETDATE(),
            is_current = FALSE
        WHERE vault_key = v_existing_key;
        
        -- Insert new version
        INSERT INTO integration.vault_financials (
            security_id, reporting_period_end, publication_date,
            revenue, ebitda, net_income,
            total_assets, total_liabilities, total_equity,
            hash_diff, source_file
        ) VALUES (
            p_security_id, p_reporting_period_end, p_publication_date,
            p_revenue, p_ebitda, p_net_income,
            p_total_assets, p_total_liabilities, p_total_equity,
            p_hash_diff, p_source_file
        );
        
    ELSIF v_existing_hash IS NULL THEN
        -- New record, just insert
        INSERT INTO integration.vault_financials (
            security_id, reporting_period_end, publication_date,
            revenue, ebitda, net_income,
            total_assets, total_liabilities, total_equity,
            hash_diff, source_file
        ) VALUES (
            p_security_id, p_reporting_period_end, p_publication_date,
            p_revenue, p_ebitda, p_net_income,
            p_total_assets, p_total_liabilities, p_total_equity,
            p_hash_diff, p_source_file
        );
    END IF;
    -- If hash is same, no action needed (duplicate)
END;
$$ LANGUAGE plpgsql;

COMMENT ON PROCEDURE integration.upsert_vault_financials IS 'Insert or update financial data in vault with SCD Type 2 logic';

-- =====================================================
-- View: Current Financial Data
-- =====================================================
-- Simplified view showing only current versions

CREATE OR REPLACE VIEW integration.v_current_financials AS
SELECT 
    security_id,
    reporting_period_end,
    publication_date,
    revenue,
    ebitda,
    net_income,
    total_assets,
    total_liabilities,
    total_equity,
    valid_from,
    load_timestamp
FROM integration.vault_financials
WHERE is_current = TRUE;

COMMENT ON VIEW integration.v_current_financials IS 'Current version of financial data (no restatements)';

-- =====================================================
-- View: Point-in-Time Financial Data
-- =====================================================
-- Function to query financial data as of a specific date

CREATE OR REPLACE FUNCTION integration.get_financials_as_of_date(
    p_as_of_date DATE
)
RETURNS TABLE (
    security_id VARCHAR(50),
    reporting_period_end DATE,
    publication_date DATE,
    revenue DECIMAL(18,2),
    ebitda DECIMAL(18,2),
    net_income DECIMAL(18,2),
    total_assets DECIMAL(18,2),
    total_equity DECIMAL(18,2)
)
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        vf.security_id,
        vf.reporting_period_end,
        vf.publication_date,
        vf.revenue,
        vf.ebitda,
        vf.net_income,
        vf.total_assets,
        vf.total_equity
    FROM integration.vault_financials vf
    WHERE vf.publication_date <= p_as_of_date
      AND vf.valid_from <= p_as_of_date
      AND (vf.valid_to IS NULL OR vf.valid_to > p_as_of_date);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION integration.get_financials_as_of_date IS 'Get financial data as it existed on a specific date';

COMMIT;

-- =====================================================
-- Usage Examples
-- =====================================================

/*
-- Insert financial data (handles restatements automatically)
CALL integration.upsert_vault_financials(
    'RELIANCE', 
    '2023-12-31', 
    '2024-01-20',
    'abc123hash',
    500000, 100000, 50000,
    1000000, 400000, 600000,
    's3://bucket/file.csv'
);

-- Query current financial data
SELECT * FROM integration.v_current_financials
WHERE security_id = 'RELIANCE';

-- Query financial data as of a specific date (point-in-time)
SELECT * FROM integration.get_financials_as_of_date('2024-01-15');

-- Find all restatements for a security
SELECT 
    reporting_period_end,
    publication_date,
    revenue,
    valid_from,
    valid_to,
    is_current
FROM integration.vault_financials
WHERE security_id = 'RELIANCE'
  AND reporting_period_end = '2023-12-31'
ORDER BY publication_date, valid_from;
*/
