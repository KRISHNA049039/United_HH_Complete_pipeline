-- Create Presentation Layer Fact Tables
-- Optimized star schema for analyst queries

-- =====================================================
-- FACT_DAILY_PRICES
-- =====================================================
-- Daily price data with corporate action adjustments

CREATE TABLE IF NOT EXISTS presentation.fact_daily_prices (
    price_date DATE NOT NULL,
    security_key INTEGER NOT NULL,
    
    -- Adjusted prices (default for analysis)
    open_price DECIMAL(18,4),
    high_price DECIMAL(18,4),
    low_price DECIMAL(18,4),
    close_price DECIMAL(18,4),
    volume BIGINT,
    turnover DECIMAL(18,2),
    
    -- Unadjusted prices (for reference)
    unadjusted_close DECIMAL(18,4),
    
    -- Calculated metrics
    price_change DECIMAL(18,4),
    price_change_pct DECIMAL(10,6),
    
    -- Volume metrics
    volume_change BIGINT,
    volume_change_pct DECIMAL(10,6),
    
    -- Metadata
    data_source VARCHAR(50),
    load_timestamp TIMESTAMP NOT NULL DEFAULT GETDATE(),
    
    PRIMARY KEY (price_date, security_key)
)
DISTSTYLE KEY
DISTKEY(security_key)
COMPOUND SORTKEY(price_date, security_key);

COMMENT ON TABLE presentation.fact_daily_prices IS 'Daily price data optimized for analyst queries';

-- Create indexes
CREATE INDEX idx_fact_prices_date ON presentation.fact_daily_prices(price_date);
CREATE INDEX idx_fact_prices_security ON presentation.fact_daily_prices(security_key);

-- =====================================================
-- FACT_QUARTERLY_FINANCIALS
-- =====================================================
-- Quarterly financial statements with point-in-time tracking

CREATE TABLE IF NOT EXISTS presentation.fact_quarterly_financials (
    reporting_period_end DATE NOT NULL,
    publication_date DATE NOT NULL,
    security_key INTEGER NOT NULL,
    
    -- Income Statement
    revenue DECIMAL(18,2),
    cost_of_revenue DECIMAL(18,2),
    gross_profit DECIMAL(18,2),
    operating_expenses DECIMAL(18,2),
    ebitda DECIMAL(18,2),
    ebit DECIMAL(18,2),
    interest_expense DECIMAL(18,2),
    tax_expense DECIMAL(18,2),
    net_income DECIMAL(18,2),
    
    -- Balance Sheet
    total_assets DECIMAL(18,2),
    current_assets DECIMAL(18,2),
    non_current_assets DECIMAL(18,2),
    total_liabilities DECIMAL(18,2),
    current_liabilities DECIMAL(18,2),
    non_current_liabilities DECIMAL(18,2),
    total_equity DECIMAL(18,2),
    
    -- Cash Flow
    operating_cash_flow DECIMAL(18,2),
    investing_cash_flow DECIMAL(18,2),
    financing_cash_flow DECIMAL(18,2),
    free_cash_flow DECIMAL(18,2),
    
    -- Point-in-time tracking
    as_of_date DATE, -- For point-in-time queries
    is_restated BOOLEAN DEFAULT FALSE,
    
    -- Metadata
    load_timestamp TIMESTAMP NOT NULL DEFAULT GETDATE(),
    
    PRIMARY KEY (reporting_period_end, publication_date, security_key)
)
DISTSTYLE KEY
DISTKEY(security_key)
COMPOUND SORTKEY(security_key, reporting_period_end, publication_date);

COMMENT ON TABLE presentation.fact_quarterly_financials IS 'Quarterly financial statements with point-in-time tracking';

-- Create indexes
CREATE INDEX idx_fact_financials_period ON presentation.fact_quarterly_financials(reporting_period_end);
CREATE INDEX idx_fact_financials_pub_date ON presentation.fact_quarterly_financials(publication_date);

-- =====================================================
-- FACT_INSTITUTIONAL_FLOWS
-- =====================================================
-- Daily FII/DII institutional flow data

CREATE TABLE IF NOT EXISTS presentation.fact_institutional_flows (
    flow_date DATE NOT NULL,
    security_key INTEGER NOT NULL,
    
    -- FII flows
    fii_buy_value DECIMAL(18,2),
    fii_sell_value DECIMAL(18,2),
    net_fii_flow DECIMAL(18,2),
    
    -- DII flows
    dii_buy_value DECIMAL(18,2),
    dii_sell_value DECIMAL(18,2),
    net_dii_flow DECIMAL(18,2),
    
    -- Combined metrics
    total_institutional_flow DECIMAL(18,2),
    
    -- Metadata
    load_timestamp TIMESTAMP NOT NULL DEFAULT GETDATE(),
    
    PRIMARY KEY (flow_date, security_key)
)
DISTSTYLE KEY
DISTKEY(security_key)
COMPOUND SORTKEY(flow_date, security_key);

COMMENT ON TABLE presentation.fact_institutional_flows IS 'Daily institutional flow data';

-- Create indexes
CREATE INDEX idx_fact_flows_date ON presentation.fact_institutional_flows(flow_date);

-- =====================================================
-- Procedure: Load fact_daily_prices from vault
-- =====================================================

CREATE OR REPLACE PROCEDURE presentation.load_fact_daily_prices(
    p_start_date DATE,
    p_end_date DATE
)
AS $$
BEGIN
    -- Delete existing data for date range
    DELETE FROM presentation.fact_daily_prices
    WHERE price_date BETWEEN p_start_date AND p_end_date;
    
    -- Insert from price_adjustments with security_key lookup
    INSERT INTO presentation.fact_daily_prices (
        price_date,
        security_key,
        open_price,
        high_price,
        low_price,
        close_price,
        volume,
        unadjusted_close,
        price_change,
        price_change_pct,
        data_source
    )
    SELECT 
        pa.price_date,
        ds.security_key,
        pa.adjusted_open,
        pa.adjusted_high,
        pa.adjusted_low,
        pa.adjusted_close,
        pa.adjusted_volume,
        pa.unadjusted_close,
        pa.adjusted_close - LAG(pa.adjusted_close) OVER (
            PARTITION BY pa.security_id ORDER BY pa.price_date
        ) AS price_change,
        (pa.adjusted_close - LAG(pa.adjusted_close) OVER (
            PARTITION BY pa.security_id ORDER BY pa.price_date
        )) / NULLIF(LAG(pa.adjusted_close) OVER (
            PARTITION BY pa.security_id ORDER BY pa.price_date
        ), 0) AS price_change_pct,
        'vault' AS data_source
    FROM integration.price_adjustments pa
    JOIN presentation.dim_security ds 
        ON pa.security_id = ds.security_id 
        AND ds.is_current = TRUE
    WHERE pa.price_date BETWEEN p_start_date AND p_end_date;
    
    -- Log the load
    INSERT INTO control.etl_job_log (
        job_name, start_time, end_time, status, records_processed
    )
    SELECT 
        'load_fact_daily_prices',
        p_start_date,
        GETDATE(),
        'SUCCESS',
        COUNT(*)
    FROM presentation.fact_daily_prices
    WHERE price_date BETWEEN p_start_date AND p_end_date;
    
END;
$$ LANGUAGE plpgsql;

COMMENT ON PROCEDURE presentation.load_fact_daily_prices IS 'Load fact_daily_prices from vault for date range';

-- =====================================================
-- Procedure: Load fact_quarterly_financials from vault
-- =====================================================

CREATE OR REPLACE PROCEDURE presentation.load_fact_quarterly_financials(
    p_start_period DATE,
    p_end_period DATE
)
AS $$
BEGIN
    -- Delete existing data for period range
    DELETE FROM presentation.fact_quarterly_financials
    WHERE reporting_period_end BETWEEN p_start_period AND p_end_period;
    
    -- Insert from vault_financials with security_key lookup
    INSERT INTO presentation.fact_quarterly_financials (
        reporting_period_end,
        publication_date,
        security_key,
        revenue,
        ebitda,
        net_income,
        total_assets,
        total_liabilities,
        total_equity,
        operating_cash_flow,
        as_of_date,
        is_restated
    )
    SELECT 
        vf.reporting_period_end,
        vf.publication_date,
        ds.security_key,
        vf.revenue,
        vf.ebitda,
        vf.net_income,
        vf.total_assets,
        vf.total_liabilities,
        vf.total_equity,
        vf.operating_cash_flow,
        vf.publication_date AS as_of_date,
        CASE WHEN COUNT(*) OVER (
            PARTITION BY vf.security_id, vf.reporting_period_end
        ) > 1 THEN TRUE ELSE FALSE END AS is_restated
    FROM integration.vault_financials vf
    JOIN presentation.dim_security ds 
        ON vf.security_id = ds.security_id 
        AND ds.is_current = TRUE
    WHERE vf.reporting_period_end BETWEEN p_start_period AND p_end_period
      AND vf.is_current = TRUE;
    
    -- Log the load
    INSERT INTO control.etl_job_log (
        job_name, start_time, end_time, status, records_processed
    )
    SELECT 
        'load_fact_quarterly_financials',
        p_start_period,
        GETDATE(),
        'SUCCESS',
        COUNT(*)
    FROM presentation.fact_quarterly_financials
    WHERE reporting_period_end BETWEEN p_start_period AND p_end_period;
    
END;
$$ LANGUAGE plpgsql;

COMMENT ON PROCEDURE presentation.load_fact_quarterly_financials IS 'Load fact_quarterly_financials from vault';

-- =====================================================
-- Procedure: Load fact_institutional_flows from vault
-- =====================================================

CREATE OR REPLACE PROCEDURE presentation.load_fact_institutional_flows(
    p_start_date DATE,
    p_end_date DATE
)
AS $$
BEGIN
    -- Delete existing data for date range
    DELETE FROM presentation.fact_institutional_flows
    WHERE flow_date BETWEEN p_start_date AND p_end_date;
    
    -- Insert from vault_flows with security_key lookup
    INSERT INTO presentation.fact_institutional_flows (
        flow_date,
        security_key,
        fii_buy_value,
        fii_sell_value,
        net_fii_flow,
        dii_buy_value,
        dii_sell_value,
        net_dii_flow,
        total_institutional_flow
    )
    SELECT 
        vf.flow_date,
        ds.security_key,
        vf.fii_buy_value,
        vf.fii_sell_value,
        vf.net_fii_flow,
        vf.dii_buy_value,
        vf.dii_sell_value,
        vf.net_dii_flow,
        vf.net_fii_flow + vf.net_dii_flow AS total_institutional_flow
    FROM integration.vault_flows vf
    JOIN presentation.dim_security ds 
        ON vf.security_id = ds.security_id 
        AND ds.is_current = TRUE
    WHERE vf.flow_date BETWEEN p_start_date AND p_end_date
      AND vf.is_current = TRUE;
    
END;
$$ LANGUAGE plpgsql;

COMMENT ON PROCEDURE presentation.load_fact_institutional_flows IS 'Load fact_institutional_flows from vault';

COMMIT;

-- =====================================================
-- Usage Examples
-- =====================================================

/*
-- Load price data for a date range
CALL presentation.load_fact_daily_prices('2024-01-01', '2024-01-31');

-- Load financial data for a period range
CALL presentation.load_fact_quarterly_financials('2023-01-01', '2023-12-31');

-- Load flow data
CALL presentation.load_fact_institutional_flows('2024-01-01', '2024-01-31');

-- Query daily prices
SELECT 
    d.date_key,
    s.security_name,
    f.close_price,
    f.price_change_pct,
    f.volume
FROM presentation.fact_daily_prices f
JOIN presentation.dim_security s ON f.security_key = s.security_key
JOIN presentation.dim_date d ON f.price_date = d.date_key
WHERE s.security_id = 'RELIANCE'
  AND d.year = 2024
  AND d.month = 1
ORDER BY d.date_key;

-- Query quarterly financials
SELECT 
    f.reporting_period_end,
    s.security_name,
    f.revenue,
    f.ebitda,
    f.net_income,
    f.is_restated
FROM presentation.fact_quarterly_financials f
JOIN presentation.dim_security s ON f.security_key = s.security_key
WHERE s.security_id = 'TCS'
  AND f.reporting_period_end >= '2023-01-01'
ORDER BY f.reporting_period_end;

-- Query institutional flows
SELECT 
    f.flow_date,
    s.security_name,
    f.net_fii_flow,
    f.net_dii_flow,
    f.total_institutional_flow
FROM presentation.fact_institutional_flows f
JOIN presentation.dim_security s ON f.security_key = s.security_key
WHERE s.sector = 'Technology'
  AND f.flow_date >= '2024-01-01'
ORDER BY f.flow_date, s.security_name;
*/
