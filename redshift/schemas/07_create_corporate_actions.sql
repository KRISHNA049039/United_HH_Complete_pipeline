-- Corporate Actions Engine
-- Calculates adjustment factors and applies to historical prices

-- =====================================================
-- CORPORATE_ACTIONS Table
-- =====================================================
-- Stores all corporate action events

CREATE TABLE IF NOT EXISTS integration.corporate_actions (
    action_id INTEGER IDENTITY(1,1) PRIMARY KEY,
    security_id VARCHAR(50) NOT NULL,
    action_type VARCHAR(20) NOT NULL, -- SPLIT, DIVIDEND, BONUS, RIGHTS, MERGER
    ex_date DATE NOT NULL,
    record_date DATE,
    payment_date DATE,
    
    -- Action details
    split_ratio_from INTEGER, -- For splits: 1:2 split = from:1, to:2
    split_ratio_to INTEGER,
    dividend_amount DECIMAL(18,4), -- Per share dividend
    bonus_ratio_from INTEGER, -- For bonus: 1:1 = from:1, to:1
    bonus_ratio_to INTEGER,
    rights_ratio_from INTEGER,
    rights_ratio_to INTEGER,
    rights_price DECIMAL(18,4),
    
    -- Calculated adjustment factor
    adjustment_factor DECIMAL(18,10) NOT NULL,
    
    -- Additional details
    details VARCHAR(MAX),
    
    -- Audit fields
    load_timestamp TIMESTAMP NOT NULL DEFAULT GETDATE(),
    source_file VARCHAR(500)
)
DISTSTYLE KEY
DISTKEY(security_id)
SORTKEY(security_id, ex_date);

COMMENT ON TABLE integration.corporate_actions IS 'Corporate action events with adjustment factors';

CREATE INDEX idx_corp_actions_date ON integration.corporate_actions(ex_date);
CREATE INDEX idx_corp_actions_type ON integration.corporate_actions(action_type);

-- =====================================================
-- PRICE_ADJUSTMENTS Table
-- =====================================================
-- Stores adjusted prices with cumulative factors

CREATE TABLE IF NOT EXISTS integration.price_adjustments (
    adjustment_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    security_id VARCHAR(50) NOT NULL,
    price_date DATE NOT NULL,
    
    -- Unadjusted prices
    unadjusted_open DECIMAL(18,4),
    unadjusted_high DECIMAL(18,4),
    unadjusted_low DECIMAL(18,4),
    unadjusted_close DECIMAL(18,4),
    unadjusted_volume BIGINT,
    
    -- Adjustment factors
    adjustment_factor DECIMAL(18,10) NOT NULL DEFAULT 1.0,
    cumulative_factor DECIMAL(18,10) NOT NULL DEFAULT 1.0,
    
    -- Adjusted prices
    adjusted_open DECIMAL(18,4),
    adjusted_high DECIMAL(18,4),
    adjusted_low DECIMAL(18,4),
    adjusted_close DECIMAL(18,4),
    adjusted_volume BIGINT,
    
    -- Audit fields
    last_updated TIMESTAMP NOT NULL DEFAULT GETDATE()
)
DISTSTYLE KEY
DISTKEY(security_id)
COMPOUND SORTKEY(security_id, price_date);

COMMENT ON TABLE integration.price_adjustments IS 'Price data with corporate action adjustments applied';

CREATE INDEX idx_price_adj_date ON integration.price_adjustments(price_date);

-- =====================================================
-- Function: Calculate Adjustment Factor
-- =====================================================

CREATE OR REPLACE FUNCTION integration.calculate_adjustment_factor(
    p_action_type VARCHAR(20),
    p_split_from INTEGER,
    p_split_to INTEGER,
    p_dividend_amount DECIMAL(18,4),
    p_close_price DECIMAL(18,4),
    p_bonus_from INTEGER,
    p_bonus_to INTEGER
)
RETURNS DECIMAL(18,10)
AS $$
DECLARE
    v_factor DECIMAL(18,10);
BEGIN
    CASE p_action_type
        -- Stock Split: Adjust by split ratio
        -- Example: 1:2 split means 1 share becomes 2, so prices are halved
        WHEN 'SPLIT' THEN
            v_factor := p_split_from::DECIMAL / NULLIF(p_split_to, 0);
            
        -- Dividend: Adjust by (price - dividend) / price
        -- Example: Rs 10 dividend on Rs 100 stock = 90/100 = 0.9
        WHEN 'DIVIDEND' THEN
            v_factor := (p_close_price - p_dividend_amount) / NULLIF(p_close_price, 0);
            
        -- Bonus: Similar to split
        -- Example: 1:1 bonus means 1 share becomes 2, so prices are halved
        WHEN 'BONUS' THEN
            v_factor := p_bonus_from::DECIMAL / NULLIF(p_bonus_from + p_bonus_to, 0);
            
        -- Rights: Complex calculation
        WHEN 'RIGHTS' THEN
            -- Simplified: treat as bonus for now
            v_factor := 1.0;
            
        -- Merger: No automatic adjustment
        WHEN 'MERGER' THEN
            v_factor := 1.0;
            
        ELSE
            v_factor := 1.0;
    END CASE;
    
    RETURN v_factor;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION integration.calculate_adjustment_factor IS 'Calculate adjustment factor for corporate action';

-- =====================================================
-- Procedure: Apply Corporate Actions
-- =====================================================
-- Calculates cumulative adjustment factors and applies to prices

CREATE OR REPLACE PROCEDURE integration.apply_corporate_actions(
    p_security_id VARCHAR(50)
)
AS $$
DECLARE
    v_action RECORD;
    v_price RECORD;
    v_cumulative_factor DECIMAL(18,10);
BEGIN
    -- Initialize cumulative factor
    v_cumulative_factor := 1.0;
    
    -- Get all corporate actions for this security, ordered by date (newest first)
    FOR v_action IN (
        SELECT 
            ex_date,
            adjustment_factor
        FROM integration.corporate_actions
        WHERE security_id = p_security_id
        ORDER BY ex_date DESC
    ) LOOP
        -- Update prices before this ex_date with cumulative factor
        UPDATE integration.price_adjustments
        SET 
            cumulative_factor = v_cumulative_factor,
            adjusted_open = unadjusted_open * v_cumulative_factor,
            adjusted_high = unadjusted_high * v_cumulative_factor,
            adjusted_low = unadjusted_low * v_cumulative_factor,
            adjusted_close = unadjusted_close * v_cumulative_factor,
            adjusted_volume = unadjusted_volume / v_cumulative_factor,
            last_updated = GETDATE()
        WHERE security_id = p_security_id
          AND price_date < v_action.ex_date
          AND cumulative_factor != v_cumulative_factor;
        
        -- Multiply cumulative factor for next iteration
        v_cumulative_factor := v_cumulative_factor * v_action.adjustment_factor;
    END LOOP;
    
    -- Update prices on or after the earliest ex_date (no adjustment)
    UPDATE integration.price_adjustments
    SET 
        cumulative_factor = 1.0,
        adjusted_open = unadjusted_open,
        adjusted_high = unadjusted_high,
        adjusted_low = unadjusted_low,
        adjusted_close = unadjusted_close,
        adjusted_volume = unadjusted_volume,
        last_updated = GETDATE()
    WHERE security_id = p_security_id
      AND price_date >= (
          SELECT MIN(ex_date) 
          FROM integration.corporate_actions 
          WHERE security_id = p_security_id
      )
      AND cumulative_factor != 1.0;
      
END;
$$ LANGUAGE plpgsql;

COMMENT ON PROCEDURE integration.apply_corporate_actions IS 'Apply corporate action adjustments to price history';

-- =====================================================
-- Procedure: Refresh All Adjustments
-- =====================================================
-- Recalculates adjustments for all securities

CREATE OR REPLACE PROCEDURE integration.refresh_all_adjustments()
AS $$
DECLARE
    v_security VARCHAR(50);
BEGIN
    -- Loop through all securities with corporate actions
    FOR v_security IN (
        SELECT DISTINCT security_id 
        FROM integration.corporate_actions
    ) LOOP
        CALL integration.apply_corporate_actions(v_security);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- View: Adjusted Prices
-- =====================================================

CREATE OR REPLACE VIEW integration.v_adjusted_prices AS
SELECT 
    security_id,
    price_date,
    adjusted_open AS open,
    adjusted_high AS high,
    adjusted_low AS low,
    adjusted_close AS close,
    adjusted_volume AS volume,
    cumulative_factor
FROM integration.price_adjustments;

COMMENT ON VIEW integration.v_adjusted_prices IS 'Price data with corporate action adjustments applied';

-- =====================================================
-- View: Unadjusted Prices
-- =====================================================

CREATE OR REPLACE VIEW integration.v_unadjusted_prices AS
SELECT 
    security_id,
    price_date,
    unadjusted_open AS open,
    unadjusted_high AS high,
    unadjusted_low AS low,
    unadjusted_close AS close,
    unadjusted_volume AS volume
FROM integration.price_adjustments;

COMMENT ON VIEW integration.v_unadjusted_prices IS 'Unadjusted price data (as traded)';

COMMIT;

-- =====================================================
-- Usage Examples
-- =====================================================

/*
-- 1. Insert a stock split (1:2 split on 2024-01-15)
INSERT INTO integration.corporate_actions (
    security_id, action_type, ex_date,
    split_ratio_from, split_ratio_to,
    adjustment_factor
) VALUES (
    'RELIANCE', 'SPLIT', '2024-01-15',
    1, 2,
    0.5  -- Prices before split are halved
);

-- 2. Insert a dividend (Rs 10 dividend, stock trading at Rs 100)
INSERT INTO integration.corporate_actions (
    security_id, action_type, ex_date,
    dividend_amount, adjustment_factor
) VALUES (
    'TCS', 'DIVIDEND', '2024-02-01',
    10.00,
    0.9  -- (100-10)/100 = 0.9
);

-- 3. Apply adjustments for a specific security
CALL integration.apply_corporate_actions('RELIANCE');

-- 4. Refresh all adjustments (run after loading new corporate actions)
CALL integration.refresh_all_adjustments();

-- 5. Query adjusted prices
SELECT * FROM integration.v_adjusted_prices
WHERE security_id = 'RELIANCE'
  AND price_date BETWEEN '2024-01-01' AND '2024-01-31'
ORDER BY price_date;

-- 6. Query unadjusted prices
SELECT * FROM integration.v_unadjusted_prices
WHERE security_id = 'RELIANCE'
  AND price_date BETWEEN '2024-01-01' AND '2024-01-31'
ORDER BY price_date;

-- 7. Compare adjusted vs unadjusted
SELECT 
    pa.security_id,
    pa.price_date,
    pa.unadjusted_close,
    pa.adjusted_close,
    pa.cumulative_factor,
    (pa.adjusted_close / pa.unadjusted_close) AS actual_factor
FROM integration.price_adjustments pa
WHERE pa.security_id = 'RELIANCE'
  AND pa.price_date < '2024-01-15'
ORDER BY pa.price_date DESC
LIMIT 10;

-- 8. View all corporate actions for a security
SELECT 
    action_type,
    ex_date,
    adjustment_factor,
    CASE action_type
        WHEN 'SPLIT' THEN split_ratio_from || ':' || split_ratio_to
        WHEN 'DIVIDEND' THEN 'Rs ' || dividend_amount
        WHEN 'BONUS' THEN bonus_ratio_from || ':' || bonus_ratio_to
        ELSE details
    END AS action_details
FROM integration.corporate_actions
WHERE security_id = 'RELIANCE'
ORDER BY ex_date DESC;
*/
