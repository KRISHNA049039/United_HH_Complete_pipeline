-- Populate DIM_DATE dimension table
-- Generates 20+ years of dates (2000-2030) with fiscal calendar

-- =====================================================
-- Generate Date Range
-- =====================================================

-- Create temporary table with date sequence
CREATE TEMP TABLE temp_dates AS
WITH RECURSIVE date_range AS (
    SELECT DATE '2000-01-01' AS date_key
    UNION ALL
    SELECT DATEADD(day, 1, date_key)
    FROM date_range
    WHERE date_key < DATE '2030-12-31'
)
SELECT date_key FROM date_range;

-- =====================================================
-- Populate DIM_DATE
-- =====================================================

INSERT INTO presentation.dim_date (
    date_key,
    year,
    quarter,
    month,
    week,
    day_of_week,
    day_of_month,
    day_of_year,
    week_of_year,
    month_name,
    day_name,
    is_weekend,
    is_trading_day,
    is_month_end,
    is_quarter_end,
    is_year_end,
    fiscal_year,
    fiscal_quarter,
    fiscal_month,
    previous_trading_day,
    next_trading_day
)
SELECT
    date_key,
    EXTRACT(YEAR FROM date_key) AS year,
    EXTRACT(QUARTER FROM date_key) AS quarter,
    EXTRACT(MONTH FROM date_key) AS month,
    EXTRACT(WEEK FROM date_key) AS week,
    EXTRACT(DOW FROM date_key) AS day_of_week, -- 0=Sunday, 6=Saturday
    EXTRACT(DAY FROM date_key) AS day_of_month,
    EXTRACT(DOY FROM date_key) AS day_of_year,
    EXTRACT(WEEK FROM date_key) AS week_of_year,
    TO_CHAR(date_key, 'Month') AS month_name,
    TO_CHAR(date_key, 'Day') AS day_name,
    CASE WHEN EXTRACT(DOW FROM date_key) IN (0, 6) THEN TRUE ELSE FALSE END AS is_weekend,
    -- Trading days: Monday-Friday, excluding weekends (holidays to be updated separately)
    CASE WHEN EXTRACT(DOW FROM date_key) BETWEEN 1 AND 5 THEN TRUE ELSE FALSE END AS is_trading_day,
    -- Month end: last day of month
    CASE WHEN date_key = LAST_DAY(date_key) THEN TRUE ELSE FALSE END AS is_month_end,
    -- Quarter end: last day of quarter
    CASE WHEN EXTRACT(MONTH FROM date_key) IN (3, 6, 9, 12) 
         AND date_key = LAST_DAY(date_key) THEN TRUE ELSE FALSE END AS is_quarter_end,
    -- Year end: December 31
    CASE WHEN EXTRACT(MONTH FROM date_key) = 12 
         AND EXTRACT(DAY FROM date_key) = 31 THEN TRUE ELSE FALSE END AS is_year_end,
    -- Fiscal year (India: April-March)
    CASE WHEN EXTRACT(MONTH FROM date_key) >= 4 
         THEN EXTRACT(YEAR FROM date_key) 
         ELSE EXTRACT(YEAR FROM date_key) - 1 END AS fiscal_year,
    -- Fiscal quarter (India: Q1=Apr-Jun, Q2=Jul-Sep, Q3=Oct-Dec, Q4=Jan-Mar)
    CASE 
        WHEN EXTRACT(MONTH FROM date_key) BETWEEN 4 AND 6 THEN 1
        WHEN EXTRACT(MONTH FROM date_key) BETWEEN 7 AND 9 THEN 2
        WHEN EXTRACT(MONTH FROM date_key) BETWEEN 10 AND 12 THEN 3
        ELSE 4
    END AS fiscal_quarter,
    -- Fiscal month (1-12, starting from April)
    CASE 
        WHEN EXTRACT(MONTH FROM date_key) >= 4 
        THEN EXTRACT(MONTH FROM date_key) - 3
        ELSE EXTRACT(MONTH FROM date_key) + 9
    END AS fiscal_month,
    NULL AS previous_trading_day, -- Will be updated in next step
    NULL AS next_trading_day      -- Will be updated in next step
FROM temp_dates;

-- =====================================================
-- Update Previous/Next Trading Days
-- =====================================================

-- Update previous trading day
UPDATE presentation.dim_date d1
SET previous_trading_day = (
    SELECT MAX(d2.date_key)
    FROM presentation.dim_date d2
    WHERE d2.date_key < d1.date_key
      AND d2.is_trading_day = TRUE
);

-- Update next trading day
UPDATE presentation.dim_date d1
SET next_trading_day = (
    SELECT MIN(d2.date_key)
    FROM presentation.dim_date d2
    WHERE d2.date_key > d1.date_key
      AND d2.is_trading_day = TRUE
);

-- =====================================================
-- Mark Indian Stock Market Holidays
-- =====================================================
-- Update is_trading_day for known holidays
-- This is a sample list - should be updated annually

-- Republic Day (January 26)
UPDATE presentation.dim_date
SET is_trading_day = FALSE
WHERE EXTRACT(MONTH FROM date_key) = 1 
  AND EXTRACT(DAY FROM date_key) = 26;

-- Independence Day (August 15)
UPDATE presentation.dim_date
SET is_trading_day = FALSE
WHERE EXTRACT(MONTH FROM date_key) = 8 
  AND EXTRACT(DAY FROM date_key) = 15;

-- Gandhi Jayanti (October 2)
UPDATE presentation.dim_date
SET is_trading_day = FALSE
WHERE EXTRACT(MONTH FROM date_key) = 10 
  AND EXTRACT(DAY FROM date_key) = 2;

-- Diwali (varies each year - sample dates, update annually)
-- Add specific dates for Diwali, Holi, etc.

-- =====================================================
-- Verify Data
-- =====================================================

-- Check record count
SELECT 
    COUNT(*) AS total_dates,
    MIN(date_key) AS min_date,
    MAX(date_key) AS max_date,
    SUM(CASE WHEN is_trading_day THEN 1 ELSE 0 END) AS trading_days,
    SUM(CASE WHEN is_weekend THEN 1 ELSE 0 END) AS weekend_days
FROM presentation.dim_date;

-- Check fiscal year distribution
SELECT 
    fiscal_year,
    COUNT(*) AS days,
    SUM(CASE WHEN is_trading_day THEN 1 ELSE 0 END) AS trading_days
FROM presentation.dim_date
GROUP BY fiscal_year
ORDER BY fiscal_year;

COMMIT;

-- =====================================================
-- Notes
-- =====================================================

/*
Maintenance:
1. Update holiday list annually
2. Add new years as needed (run similar INSERT for future dates)
3. Verify trading day flags match actual market calendar

Usage Examples:

-- Get all trading days in a month
SELECT date_key 
FROM presentation.dim_date 
WHERE year = 2024 AND month = 1 AND is_trading_day = TRUE;

-- Get fiscal year dates
SELECT date_key 
FROM presentation.dim_date 
WHERE fiscal_year = 2024;

-- Get quarter-end dates
SELECT date_key 
FROM presentation.dim_date 
WHERE is_quarter_end = TRUE AND year = 2024;
*/
