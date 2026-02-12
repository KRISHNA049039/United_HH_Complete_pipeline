-- Create Dimension Tables for Research Data Platform V2
-- Implements Type 2 Slowly Changing Dimensions (SCD) for temporal tracking

-- =====================================================
-- DIM_SECURITY
-- =====================================================
-- Master table of all securities with Type 2 SCD for tracking changes

CREATE TABLE IF NOT EXISTS presentation.dim_security (
    security_key INTEGER IDENTITY(1,1) PRIMARY KEY,
    security_id VARCHAR(50) NOT NULL,
    security_name VARCHAR(200),
    isin VARCHAR(12),
    nse_symbol VARCHAR(20),
    bse_code VARCHAR(10),
    sector VARCHAR(100),
    industry VARCHAR(100),
    market_cap_category VARCHAR(20), -- LARGECAP, MIDCAP, SMALLCAP
    listing_date DATE,
    delisting_date DATE,
    delisting_reason VARCHAR(200),
    is_current BOOLEAN NOT NULL DEFAULT TRUE,
    valid_from DATE NOT NULL,
    valid_to DATE,
    load_timestamp TIMESTAMP NOT NULL DEFAULT GETDATE(),
    source_system VARCHAR(50)
)
DISTSTYLE ALL
SORTKEY(security_key);

COMMENT ON TABLE presentation.dim_security IS 'Master dimension of all securities with SCD Type 2';

-- Create index on security_id for lookups
CREATE INDEX idx_dim_security_id ON presentation.dim_security(security_id);
CREATE INDEX idx_dim_security_current ON presentation.dim_security(is_current) WHERE is_current = TRUE;

-- =====================================================
-- DIM_DATE
-- =====================================================
-- Date dimension with fiscal calendar and trading day flags

CREATE TABLE IF NOT EXISTS presentation.dim_date (
    date_key DATE PRIMARY KEY,
    year INTEGER NOT NULL,
    quarter INTEGER NOT NULL,
    month INTEGER NOT NULL,
    week INTEGER NOT NULL,
    day_of_week INTEGER NOT NULL,
    day_of_month INTEGER NOT NULL,
    day_of_year INTEGER NOT NULL,
    week_of_year INTEGER NOT NULL,
    month_name VARCHAR(20),
    day_name VARCHAR(20),
    is_weekend BOOLEAN NOT NULL,
    is_trading_day BOOLEAN NOT NULL,
    is_month_end BOOLEAN NOT NULL,
    is_quarter_end BOOLEAN NOT NULL,
    is_year_end BOOLEAN NOT NULL,
    fiscal_year INTEGER NOT NULL,
    fiscal_quarter INTEGER NOT NULL,
    fiscal_month INTEGER NOT NULL,
    previous_trading_day DATE,
    next_trading_day DATE
)
DISTSTYLE ALL
SORTKEY(date_key);

COMMENT ON TABLE presentation.dim_date IS 'Date dimension with fiscal calendar and trading day information';

-- =====================================================
-- DIM_INDEX_CONSTITUENTS
-- =====================================================
-- Tracks index membership changes over time (for survivorship-free analysis)

CREATE TABLE IF NOT EXISTS presentation.dim_index_constituents (
    constituent_key INTEGER IDENTITY(1,1) PRIMARY KEY,
    index_name VARCHAR(50) NOT NULL,
    security_key INTEGER NOT NULL,
    effective_date DATE NOT NULL,
    exit_date DATE,
    is_current BOOLEAN NOT NULL DEFAULT TRUE,
    weight DECIMAL(10,6),
    load_timestamp TIMESTAMP NOT NULL DEFAULT GETDATE()
)
DISTSTYLE ALL
SORTKEY(index_name, effective_date);

COMMENT ON TABLE presentation.dim_index_constituents IS 'Index membership history for survivorship-free analysis';

-- Create indexes for common queries
CREATE INDEX idx_dim_index_name ON presentation.dim_index_constituents(index_name);
CREATE INDEX idx_dim_index_security ON presentation.dim_index_constituents(security_key);
CREATE INDEX idx_dim_index_current ON presentation.dim_index_constituents(is_current) WHERE is_current = TRUE;

-- =====================================================
-- DIM_SECTOR
-- =====================================================
-- Sector and industry classification hierarchy

CREATE TABLE IF NOT EXISTS presentation.dim_sector (
    sector_key INTEGER IDENTITY(1,1) PRIMARY KEY,
    sector_code VARCHAR(20) NOT NULL UNIQUE,
    sector_name VARCHAR(100) NOT NULL,
    industry_code VARCHAR(20),
    industry_name VARCHAR(100),
    sub_industry_code VARCHAR(20),
    sub_industry_name VARCHAR(100),
    classification_system VARCHAR(50), -- GICS, ICB, etc.
    is_active BOOLEAN NOT NULL DEFAULT TRUE
)
DISTSTYLE ALL
SORTKEY(sector_key);

COMMENT ON TABLE presentation.dim_sector IS 'Sector and industry classification hierarchy';

-- =====================================================
-- Foreign Key Relationships (Informational)
-- =====================================================
-- Redshift doesn't enforce FKs but we document them for clarity

-- presentation.dim_index_constituents.security_key -> presentation.dim_security.security_key
-- fact tables will reference these dimension keys

COMMIT;
