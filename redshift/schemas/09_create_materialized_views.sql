-- Create Materialized Views for Performance Optimization
-- Precomputes common calculations to accelerate analyst queries

-- =====================================================
-- MV_PRECOMPUTED_RATIOS
-- =====================================================
-- Financial ratios and margins precomputed for all securities

CREATE MATERIALIZED VIEW presentation.mv_precomputed_ratios AS
SELECT 
    f.security_key,
    s.security_id,
    s.security_name,
    s.sector,
    f.reporting_period_end,
    f.publication_date,
    
    -- Revenue metrics
    f.revenue,
    f.gross_profit,
    f.ebitda,
    f.ebit,
    f.net_income,
    
    -- Profitability ratios
    CASE WHEN f.revenue > 0 
        THEN (f.gross_profit / f.revenue) * 100 
        ELSE NULL 
    END AS gross_margin_pct,
    
    CASE WHEN f.revenue > 0 
        THEN (f.ebitda / f.revenue) * 100 
        ELSE NULL 
    END AS ebitda_margin_pct,
    
    CASE WHEN f.revenue > 0 
        THEN (f.ebit / f.revenue) * 100 
        ELSE NULL 
    END AS ebit_margin_pct,
    
    CASE WHEN f.revenue > 0 
        THEN (f.net_income / f.revenue) * 100 
        ELSE NULL 
    END AS net_margin_pct,
    
    -- Return ratios
    CASE WHEN f.total_assets > 0 
        THEN (f.net_income / f.total_assets) * 100 
        ELSE NULL 
    END AS roa_pct,
    
    CASE WHEN f.total_equity > 0 
        THEN (f.net_income / f.total_equity) * 100 
        ELSE NULL 
    END AS roe_pct,
    
    -- Leverage ratios
    CASE WHEN f.total_assets > 0 
        THEN (f.total_equity / f.total_assets) * 100 
        ELSE NULL 
    END AS equity_ratio_pct,
    
    CASE WHEN f.total_equity > 0 
        THEN (f.total_liabilities / f.total_equity) 
        ELSE NULL 
    END AS debt_to_equity,
    
    CASE WHEN f.total_assets > 0 
        THEN (f.total_liabilities / f.total_assets) * 100 
        ELSE NULL 
    END AS debt_ratio_pct,
    
    -- Growth metrics (YoY)
    LAG(f.revenue, 4) OVER (
        PARTITION BY f.security_key ORDER BY f.reporting_period_end
    ) AS revenue_4q_ago,
    
    CASE WHEN LAG(f.revenue, 4) OVER (
        PARTITION BY f.security_key ORDER BY f.reporting_period_end
    ) > 0 THEN
        ((f.revenue - LAG(f.revenue, 4) OVER (
            PARTITION BY f.security_key ORDER BY f.reporting_period_end
        )) / LAG(f.revenue, 4) OVER (
            PARTITION BY f.security_key ORDER BY f.reporting_period_end
        )) * 100
    ELSE NULL
    END AS revenue_yoy_growth_pct,
    
    CASE WHEN LAG(f.net_income, 4) OVER (
        PARTITION BY f.security_key ORDER BY f.reporting_period_end
    ) > 0 THEN
        ((f.net_income - LAG(f.net_income, 4) OVER (
            PARTITION BY f.security_key ORDER BY f.reporting_period_end
        )) / LAG(f.net_income, 4) OVER (
            PARTITION BY f.security_key ORDER BY f.reporting_period_end
        )) * 100
    ELSE NULL
    END AS net_income_yoy_growth_pct
    
FROM presentation.fact_quarterly_financials f
JOIN presentation.dim_security s ON f.security_key = s.security_key
WHERE s.is_current = TRUE;

COMMENT ON MATERIALIZED VIEW presentation.mv_precomputed_ratios IS 'Precomputed financial ratios and margins';

-- =====================================================
-- MV_ROLLING_RETURNS
-- =====================================================
-- Rolling returns and momentum indicators

CREATE MATERIALIZED VIEW presentation.mv_rolling_returns AS
SELECT 
    f.security_key,
    s.security_id,
    s.security_name,
    s.sector,
    f.price_date,
    f.close_price,
    
    -- Historical prices for return calculation
    LAG(f.close_price, 1) OVER w AS close_1d_ago,
    LAG(f.close_price, 5) OVER w AS close_1w_ago,
    LAG(f.close_price, 21) OVER w AS close_1m_ago,
    LAG(f.close_price, 63) OVER w AS close_3m_ago,
    LAG(f.close_price, 126) OVER w AS close_6m_ago,
    LAG(f.close_price, 252) OVER w AS close_1y_ago,
    LAG(f.close_price, 756) OVER w AS close_3y_ago,
    
    -- Returns
    CASE WHEN LAG(f.close_price, 1) OVER w > 0 
        THEN ((f.close_price - LAG(f.close_price, 1) OVER w) / LAG(f.close_price, 1) OVER w) * 100
        ELSE NULL 
    END AS return_1d_pct,
    
    CASE WHEN LAG(f.close_price, 5) OVER w > 0 
        THEN ((f.close_price - LAG(f.close_price, 5) OVER w) / LAG(f.close_price, 5) OVER w) * 100
        ELSE NULL 
    END AS return_1w_pct,
    
    CASE WHEN LAG(f.close_price, 21) OVER w > 0 
        THEN ((f.close_price - LAG(f.close_price, 21) OVER w) / LAG(f.close_price, 21) OVER w) * 100
        ELSE NULL 
    END AS return_1m_pct,
    
    CASE WHEN LAG(f.close_price, 63) OVER w > 0 
        THEN ((f.close_price - LAG(f.close_price, 63) OVER w) / LAG(f.close_price, 63) OVER w) * 100
        ELSE NULL 
    END AS return_3m_pct,
    
    CASE WHEN LAG(f.close_price, 126) OVER w > 0 
        THEN ((f.close_price - LAG(f.close_price, 126) OVER w) / LAG(f.close_price, 126) OVER w) * 100
        ELSE NULL 
    END AS return_6m_pct,
    
    CASE WHEN LAG(f.close_price, 252) OVER w > 0 
        THEN ((f.close_price - LAG(f.close_price, 252) OVER w) / LAG(f.close_price, 252) OVER w) * 100
        ELSE NULL 
    END AS return_1y_pct,
    
    CASE WHEN LAG(f.close_price, 756) OVER w > 0 
        THEN ((f.close_price - LAG(f.close_price, 756) OVER w) / LAG(f.close_price, 756) OVER w) * 100
        ELSE NULL 
    END AS return_3y_pct,
    
    -- Volatility (20-day rolling standard deviation)
    STDDEV(f.price_change_pct) OVER (
        PARTITION BY f.security_key 
        ORDER BY f.price_date 
        ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
    ) AS volatility_20d,
    
    -- Volume metrics
    f.volume,
    AVG(f.volume) OVER (
        PARTITION BY f.security_key 
        ORDER BY f.price_date 
        ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
    ) AS avg_volume_20d
    
FROM presentation.fact_daily_prices f
JOIN presentation.dim_security s ON f.security_key = s.security_key
WHERE s.is_current = TRUE
WINDOW w AS (PARTITION BY f.security_key ORDER BY f.price_date);

COMMENT ON MATERIALIZED VIEW presentation.mv_rolling_returns IS 'Rolling returns and momentum indicators';

-- =====================================================
-- MV_CURRENT_INDEX_CONSTITUENTS
-- =====================================================
-- Current index membership for fast lookups

CREATE MATERIALIZED VIEW presentation.mv_current_index_constituents AS
SELECT 
    ic.index_name,
    ic.security_key,
    s.security_id,
    s.security_name,
    s.sector,
    s.industry,
    s.market_cap_category,
    ic.effective_date,
    ic.weight
FROM presentation.dim_index_constituents ic
JOIN presentation.dim_security s ON ic.security_key = s.security_key
WHERE ic.is_current = TRUE 
  AND s.is_current = TRUE;

COMMENT ON MATERIALIZED VIEW presentation.mv_current_index_constituents IS 'Current index constituents for fast lookups';

-- =====================================================
-- MV_SECTOR_AGGREGATES
-- =====================================================
-- Sector-level aggregated metrics

CREATE MATERIALIZED VIEW presentation.mv_sector_aggregates AS
SELECT 
    d.date_key AS price_date,
    s.sector,
    COUNT(DISTINCT f.security_key) AS security_count,
    AVG(f.close_price) AS avg_close_price,
    SUM(f.volume) AS total_volume,
    AVG(f.price_change_pct) AS avg_price_change_pct,
    STDDEV(f.price_change_pct) AS price_change_stddev
FROM presentation.fact_daily_prices f
JOIN presentation.dim_security s ON f.security_key = s.security_key
JOIN presentation.dim_date d ON f.price_date = d.date_key
WHERE s.is_current = TRUE
  AND d.is_trading_day = TRUE
GROUP BY d.date_key, s.sector;

COMMENT ON MATERIALIZED VIEW presentation.mv_sector_aggregates IS 'Sector-level aggregated metrics';

-- =====================================================
-- MV_MARKET_CAP_RANKINGS
-- =====================================================
-- Market cap rankings and percentiles

CREATE MATERIALIZED VIEW presentation.mv_market_cap_rankings AS
WITH latest_prices AS (
    SELECT 
        f.security_key,
        f.close_price,
        f.price_date,
        ROW_NUMBER() OVER (PARTITION BY f.security_key ORDER BY f.price_date DESC) AS rn
    FROM presentation.fact_daily_prices f
),
latest_financials AS (
    SELECT 
        f.security_key,
        f.total_equity,
        f.reporting_period_end,
        ROW_NUMBER() OVER (PARTITION BY f.security_key ORDER BY f.reporting_period_end DESC) AS rn
    FROM presentation.fact_quarterly_financials f
)
SELECT 
    s.security_key,
    s.security_id,
    s.security_name,
    s.sector,
    s.market_cap_category,
    lp.close_price,
    lp.price_date AS price_as_of_date,
    lf.total_equity,
    lf.reporting_period_end AS equity_as_of_date,
    -- Approximate market cap (price * shares outstanding would be more accurate)
    lp.close_price * COALESCE(lf.total_equity, 0) AS approx_market_cap,
    NTILE(100) OVER (ORDER BY lp.close_price * COALESCE(lf.total_equity, 0)) AS market_cap_percentile
FROM presentation.dim_security s
LEFT JOIN latest_prices lp ON s.security_key = lp.security_key AND lp.rn = 1
LEFT JOIN latest_financials lf ON s.security_key = lf.security_key AND lf.rn = 1
WHERE s.is_current = TRUE
  AND s.delisting_date IS NULL;

COMMENT ON MATERIALIZED VIEW presentation.mv_market_cap_rankings IS 'Market cap rankings and percentiles';

-- =====================================================
-- Refresh Procedures
-- =====================================================

-- Refresh all materialized views
CREATE OR REPLACE PROCEDURE presentation.refresh_all_materialized_views()
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW presentation.mv_precomputed_ratios;
    REFRESH MATERIALIZED VIEW presentation.mv_rolling_returns;
    REFRESH MATERIALIZED VIEW presentation.mv_current_index_constituents;
    REFRESH MATERIALIZED VIEW presentation.mv_sector_aggregates;
    REFRESH MATERIALIZED VIEW presentation.mv_market_cap_rankings;
    
    -- Log the refresh
    INSERT INTO control.etl_job_log (
        job_name, start_time, end_time, status
    ) VALUES (
        'refresh_all_materialized_views',
        GETDATE(),
        GETDATE(),
        'SUCCESS'
    );
END;
$$ LANGUAGE plpgsql;

COMMENT ON PROCEDURE presentation.refresh_all_materialized_views IS 'Refresh all materialized views';

-- Schedule: Run daily at 7 AM IST after data ingestion
-- Can be scheduled using Redshift scheduled queries or external scheduler

COMMIT;

-- =====================================================
-- Usage Examples
-- =====================================================

/*
-- Refresh all materialized views
CALL presentation.refresh_all_materialized_views();

-- Query precomputed ratios
SELECT 
    security_name,
    reporting_period_end,
    revenue,
    ebitda_margin_pct,
    net_margin_pct,
    roe_pct,
    revenue_yoy_growth_pct
FROM presentation.mv_precomputed_ratios
WHERE sector = 'Technology'
  AND reporting_period_end >= '2023-01-01'
ORDER BY revenue_yoy_growth_pct DESC
LIMIT 10;

-- Query rolling returns
SELECT 
    security_name,
    price_date,
    close_price,
    return_1m_pct,
    return_6m_pct,
    return_1y_pct,
    volatility_20d
FROM presentation.mv_rolling_returns
WHERE security_id = 'RELIANCE'
  AND price_date >= CURRENT_DATE - 90
ORDER BY price_date DESC;

-- Query current index constituents
SELECT 
    index_name,
    security_name,
    sector,
    market_cap_category
FROM presentation.mv_current_index_constituents
WHERE index_name = 'NIFTY50'
ORDER BY security_name;

-- Query sector aggregates
SELECT 
    price_date,
    sector,
    security_count,
    avg_price_change_pct,
    total_volume
FROM presentation.mv_sector_aggregates
WHERE price_date >= CURRENT_DATE - 30
ORDER BY price_date DESC, sector;

-- Find top performers by 6-month return
SELECT 
    security_name,
    sector,
    return_6m_pct,
    volatility_20d
FROM presentation.mv_rolling_returns
WHERE price_date = (SELECT MAX(price_date) FROM presentation.mv_rolling_returns)
  AND return_6m_pct IS NOT NULL
ORDER BY return_6m_pct DESC
LIMIT 20;

-- Find stocks with improving margins
SELECT 
    security_name,
    reporting_period_end,
    ebitda_margin_pct,
    LAG(ebitda_margin_pct, 4) OVER (
        PARTITION BY security_key ORDER BY reporting_period_end
    ) AS ebitda_margin_4q_ago
FROM presentation.mv_precomputed_ratios
WHERE reporting_period_end >= '2023-01-01'
QUALIFY ebitda_margin_pct > LAG(ebitda_margin_pct, 4) OVER (
    PARTITION BY security_key ORDER BY reporting_period_end
)
ORDER BY (ebitda_margin_pct - LAG(ebitda_margin_pct, 4) OVER (
    PARTITION BY security_key ORDER BY reporting_period_end
)) DESC
LIMIT 20;
*/
