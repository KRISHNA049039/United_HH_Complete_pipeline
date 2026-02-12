-- User-Defined Functions (UDFs) for Query Abstraction Layer
-- Encapsulates common query patterns with built-in point-in-time correctness

-- =====================================================
-- GET_INDEX_CONSTITUENTS
-- =====================================================
-- Returns index constituents as of a specific date

CREATE OR REPLACE FUNCTION presentation.get_index_constituents(
    p_index_name VARCHAR(50),
    p_as_of_date DATE
)
RETURNS TABLE (
    security_key INTEGER,
    security_id VARCHAR(50),
    security_name VARCHAR(200),
    sector VARCHAR(100),
    effective_date DATE
)
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ic.security_key,
        s.security_id,
        s.security_name,
        s.sector,
        ic.effective_date
    FROM presentation.dim_index_constituents ic
    JOIN presentation.dim_security s ON ic.security_key = s.security_key
    WHERE ic.index_name = p_index_name
      AND ic.effective_date <= p_as_of_date
      AND (ic.exit_date IS NULL OR ic.exit_date > p_as_of_date)
      AND s.valid_from <= p_as_of_date
      AND (s.valid_to IS NULL OR s.valid_to > p_as_of_date);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION presentation.get_index_constituents IS 
'Get index constituents as of a specific date (survivorship-free)';

-- =====================================================
-- GET_FINANCIAL_METRIC_SERIES
-- =====================================================
-- Returns time series of a financial metric with point-in-time correctness

CREATE OR REPLACE FUNCTION presentation.get_financial_metric_series(
    p_security_id VARCHAR(50),
    p_metric_name VARCHAR(100),
    p_start_date DATE,
    p_end_date DATE,
    p_as_of_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    reporting_period_end DATE,
    metric_value DECIMAL(18,2),
    publication_date DATE
)
AS $$
BEGIN
    RETURN QUERY
    EXECUTE format('
        SELECT 
            f.reporting_period_end,
            f.%I AS metric_value,
            f.publication_date
        FROM presentation.fact_quarterly_financials f
        JOIN presentation.dim_security s ON f.security_key = s.security_key
        WHERE s.security_id = $1
          AND f.reporting_period_end BETWEEN $2 AND $3
          AND f.publication_date <= $4
        ORDER BY f.reporting_period_end',
        p_metric_name
    )
    USING p_security_id, p_start_date, p_end_date, p_as_of_date;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION presentation.get_financial_metric_series IS 
'Get time series of financial metric with point-in-time correctness';

-- =====================================================
-- CALCULATE_REVENUE_CAGR
-- =====================================================
-- Calculates revenue CAGR over specified years

CREATE OR REPLACE FUNCTION presentation.calculate_revenue_cagr(
    p_security_id VARCHAR(50),
    p_years INTEGER,
    p_as_of_date DATE DEFAULT CURRENT_DATE
)
RETURNS DECIMAL(10,4)
AS $$
DECLARE
    v_start_revenue DECIMAL(18,2);
    v_end_revenue DECIMAL(18,2);
    v_cagr DECIMAL(10,4);
BEGIN
    -- Get earliest revenue in period
    SELECT revenue INTO v_start_revenue
    FROM presentation.fact_quarterly_financials f
    JOIN presentation.dim_security s ON f.security_key = s.security_key
    WHERE s.security_id = p_security_id
      AND f.reporting_period_end >= p_as_of_date - (p_years * 365)
      AND f.publication_date <= p_as_of_date
    ORDER BY f.reporting_period_end ASC
    LIMIT 1;
    
    -- Get latest revenue in period
    SELECT revenue INTO v_end_revenue
    FROM presentation.fact_quarterly_financials f
    JOIN presentation.dim_security s ON f.security_key = s.security_key
    WHERE s.security_id = p_security_id
      AND f.reporting_period_end <= p_as_of_date
      AND f.publication_date <= p_as_of_date
    ORDER BY f.reporting_period_end DESC
    LIMIT 1;
    
    -- Calculate CAGR
    IF v_start_revenue > 0 AND v_end_revenue > 0 THEN
        v_cagr := (POWER(v_end_revenue / v_start_revenue, 1.0 / p_years) - 1) * 100;
    ELSE
        v_cagr := NULL;
    END IF;
    
    RETURN v_cagr;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION presentation.calculate_revenue_cagr IS 
'Calculate revenue CAGR over specified years with point-in-time correctness';

-- =====================================================
-- GET_PRICE_SERIES
-- =====================================================
-- Returns price series for a security

CREATE OR REPLACE FUNCTION presentation.get_price_series(
    p_security_id VARCHAR(50),
    p_start_date DATE,
    p_end_date DATE,
    p_adjusted BOOLEAN DEFAULT TRUE
)
RETURNS TABLE (
    price_date DATE,
    open_price DECIMAL(18,4),
    high_price DECIMAL(18,4),
    low_price DECIMAL(18,4),
    close_price DECIMAL(18,4),
    volume BIGINT
)
AS $$
BEGIN
    IF p_adjusted THEN
        -- Return adjusted prices
        RETURN QUERY
        SELECT 
            f.price_date,
            f.open_price,
            f.high_price,
            f.low_price,
            f.close_price,
            f.volume
        FROM presentation.fact_daily_prices f
        JOIN presentation.dim_security s ON f.security_key = s.security_key
        WHERE s.security_id = p_security_id
          AND f.price_date BETWEEN p_start_date AND p_end_date
        ORDER BY f.price_date;
    ELSE
        -- Return unadjusted prices
        RETURN QUERY
        SELECT 
            pa.price_date,
            pa.unadjusted_open,
            pa.unadjusted_high,
            pa.unadjusted_low,
            pa.unadjusted_close,
            pa.unadjusted_volume
        FROM integration.price_adjustments pa
        JOIN presentation.dim_security s ON pa.security_id = s.security_id
        WHERE s.security_id = p_security_id
          AND pa.price_date BETWEEN p_start_date AND p_end_date
        ORDER BY pa.price_date;
    END IF;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION presentation.get_price_series IS 
'Get price series (adjusted or unadjusted) for a security';

-- =====================================================
-- GET_FII_FLOW_DURING_DRAWDOWNS
-- =====================================================
-- Returns FII flow during market drawdowns

CREATE OR REPLACE FUNCTION presentation.get_fii_flow_during_drawdowns(
    p_index_name VARCHAR(50),
    p_drawdown_threshold DECIMAL(10,2) DEFAULT -10.0,
    p_lookback_days INTEGER DEFAULT 1825 -- 5 years
)
RETURNS TABLE (
    drawdown_start_date DATE,
    drawdown_end_date DATE,
    drawdown_pct DECIMAL(10,2),
    total_fii_flow DECIMAL(18,2),
    avg_daily_fii_flow DECIMAL(18,2)
)
AS $$
BEGIN
    -- This is a simplified version
    -- Full implementation would identify drawdown periods and aggregate flows
    RETURN QUERY
    WITH index_prices AS (
        SELECT 
            f.price_date,
            AVG(f.close_price) AS avg_close,
            MAX(AVG(f.close_price)) OVER (
                ORDER BY f.price_date 
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS running_max
        FROM presentation.fact_daily_prices f
        JOIN presentation.dim_index_constituents ic ON f.security_key = ic.security_key
        WHERE ic.index_name = p_index_name
          AND ic.is_current = TRUE
          AND f.price_date >= CURRENT_DATE - p_lookback_days
        GROUP BY f.price_date
    ),
    drawdowns AS (
        SELECT 
            price_date,
            ((avg_close - running_max) / running_max) * 100 AS drawdown_pct
        FROM index_prices
        WHERE ((avg_close - running_max) / running_max) * 100 <= p_drawdown_threshold
    )
    SELECT 
        MIN(d.price_date) AS drawdown_start_date,
        MAX(d.price_date) AS drawdown_end_date,
        MIN(d.drawdown_pct) AS drawdown_pct,
        SUM(f.net_fii_flow) AS total_fii_flow,
        AVG(f.net_fii_flow) AS avg_daily_fii_flow
    FROM drawdowns d
    JOIN presentation.fact_institutional_flows f ON f.flow_date = d.price_date
    GROUP BY DATE_TRUNC('month', d.price_date);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION presentation.get_fii_flow_during_drawdowns IS 
'Get FII flow during market drawdown periods';

-- =====================================================
-- GET_SECTOR_PERFORMANCE_WHEN
-- =====================================================
-- Returns sector performance when a macro condition is met

CREATE OR REPLACE FUNCTION presentation.get_sector_performance_when(
    p_condition VARCHAR(200),
    p_lookback_days INTEGER DEFAULT 1825
)
RETURNS TABLE (
    sector VARCHAR(100),
    avg_return_pct DECIMAL(10,4),
    median_return_pct DECIMAL(10,4),
    outperformance_days INTEGER,
    total_days INTEGER
)
AS $$
BEGIN
    -- Simplified version - would need macro data table
    RETURN QUERY
    SELECT 
        s.sector,
        AVG(f.price_change_pct) AS avg_return_pct,
        MEDIAN(f.price_change_pct) AS median_return_pct,
        SUM(CASE WHEN f.price_change_pct > 0 THEN 1 ELSE 0 END) AS outperformance_days,
        COUNT(*)::INTEGER AS total_days
    FROM presentation.fact_daily_prices f
    JOIN presentation.dim_security s ON f.security_key = s.security_key
    WHERE f.price_date >= CURRENT_DATE - p_lookback_days
      AND s.is_current = TRUE
    GROUP BY s.sector
    ORDER BY avg_return_pct DESC;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION presentation.get_sector_performance_when IS 
'Get sector performance when macro condition is met';

-- =====================================================
-- GET_STOCKS_WITH_CRITERIA
-- =====================================================
-- Returns stocks matching multiple criteria

CREATE OR REPLACE FUNCTION presentation.get_stocks_with_criteria(
    p_min_market_cap DECIMAL(18,2) DEFAULT NULL,
    p_max_market_cap DECIMAL(18,2) DEFAULT NULL,
    p_min_roe DECIMAL(10,2) DEFAULT NULL,
    p_min_revenue_growth DECIMAL(10,2) DEFAULT NULL,
    p_min_return_6m DECIMAL(10,2) DEFAULT NULL,
    p_sectors VARCHAR(500) DEFAULT NULL
)
RETURNS TABLE (
    security_id VARCHAR(50),
    security_name VARCHAR(200),
    sector VARCHAR(100),
    market_cap DECIMAL(18,2),
    roe_pct DECIMAL(10,4),
    revenue_growth_pct DECIMAL(10,4),
    return_6m_pct DECIMAL(10,4)
)
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        s.security_id,
        s.security_name,
        s.sector,
        mc.approx_market_cap,
        r.roe_pct,
        r.revenue_yoy_growth_pct,
        rr.return_6m_pct
    FROM presentation.dim_security s
    LEFT JOIN presentation.mv_market_cap_rankings mc ON s.security_key = mc.security_key
    LEFT JOIN (
        SELECT security_key, roe_pct, revenue_yoy_growth_pct
        FROM presentation.mv_precomputed_ratios
        WHERE reporting_period_end = (
            SELECT MAX(reporting_period_end) 
            FROM presentation.mv_precomputed_ratios
        )
    ) r ON s.security_key = r.security_key
    LEFT JOIN (
        SELECT security_key, return_6m_pct
        FROM presentation.mv_rolling_returns
        WHERE price_date = (
            SELECT MAX(price_date) 
            FROM presentation.mv_rolling_returns
        )
    ) rr ON s.security_key = rr.security_key
    WHERE s.is_current = TRUE
      AND (p_min_market_cap IS NULL OR mc.approx_market_cap >= p_min_market_cap)
      AND (p_max_market_cap IS NULL OR mc.approx_market_cap <= p_max_market_cap)
      AND (p_min_roe IS NULL OR r.roe_pct >= p_min_roe)
      AND (p_min_revenue_growth IS NULL OR r.revenue_yoy_growth_pct >= p_min_revenue_growth)
      AND (p_min_return_6m IS NULL OR rr.return_6m_pct >= p_min_return_6m)
      AND (p_sectors IS NULL OR s.sector = ANY(STRING_TO_ARRAY(p_sectors, ',')))
    ORDER BY rr.return_6m_pct DESC NULLS LAST;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION presentation.get_stocks_with_criteria IS 
'Get stocks matching multiple screening criteria';

COMMIT;

-- =====================================================
-- Usage Examples
-- =====================================================

/*
-- 1. Get NIFTY50 constituents as of a historical date
SELECT * FROM presentation.get_index_constituents('NIFTY50', '2020-01-01');

-- 2. Get revenue time series with point-in-time correctness
SELECT * FROM presentation.get_financial_metric_series(
    'RELIANCE', 'revenue', '2020-01-01', '2023-12-31', '2024-01-01'
);

-- 3. Calculate 10-year revenue CAGR
SELECT presentation.calculate_revenue_cagr('TCS', 10, CURRENT_DATE);

-- 4. Get adjusted price series
SELECT * FROM presentation.get_price_series(
    'INFY', '2024-01-01', '2024-01-31', TRUE
);

-- 5. Get FII flow during drawdowns
SELECT * FROM presentation.get_fii_flow_during_drawdowns('NIFTY50', -10.0, 1825);

-- 6. Screen stocks with criteria
SELECT * FROM presentation.get_stocks_with_criteria(
    p_min_roe := 15.0,
    p_min_revenue_growth := 10.0,
    p_min_return_6m := 5.0,
    p_sectors := 'Technology,Financial Services'
);

-- 7. Get 10-year revenue CAGR for current NIFTY500
SELECT 
    s.security_name,
    presentation.calculate_revenue_cagr(s.security_id, 10, CURRENT_DATE) AS revenue_cagr_10y
FROM presentation.get_index_constituents('NIFTY500', CURRENT_DATE) ic
JOIN presentation.dim_security s ON ic.security_key = s.security_key
WHERE presentation.calculate_revenue_cagr(s.security_id, 10, CURRENT_DATE) IS NOT NULL
ORDER BY revenue_cagr_10y DESC
LIMIT 20;
*/
