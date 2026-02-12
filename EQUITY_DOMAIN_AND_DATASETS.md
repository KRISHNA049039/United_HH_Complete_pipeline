# Equity Domain Concepts and Datasets

## Overview

This document provides a comprehensive guide to equity market concepts and all datasets used in the Research Data Platform V2. It serves as a reference for understanding financial terminology, data structures, and domain-specific calculations.

---

## Table of Contents

1. [Equity Market Fundamentals](#equity-market-fundamentals)
2. [Dataset Catalog](#dataset-catalog)
3. [Financial Metrics and Ratios](#financial-metrics-and-ratios)
4. [Corporate Actions](#corporate-actions)
5. [Market Microstructure](#market-microstructure)
6. [Data Relationships](#data-relationships)

---

## 1. Equity Market Fundamentals

### What is an Equity?

An equity (or stock) represents ownership in a company. When you buy equity shares, you become a partial owner of the company and have a claim on its assets and earnings.

### Key Equity Concepts

#### Security Identification

**ISIN (International Securities Identification Number)**
- 12-character alphanumeric code
- Uniquely identifies a security globally
- Example: `INE002A01018` (Reliance Industries)

**NSE Symbol**
- Trading symbol on National Stock Exchange
- Example: `RELIANCE`, `TCS`, `INFY`

**BSE Code**
- Numeric code on Bombay Stock Exchange
- Example: `500325` (Reliance Industries)

---

#### Market Capitalization

Market cap = Share Price × Total Outstanding Shares

**Categories:**
- **Large Cap**: Top 100 companies by market cap
- **Mid Cap**: 101st to 250th companies
- **Small Cap**: 251st company onwards

---

#### Price Data (OHLCV)

**Open**: First traded price of the day
**High**: Highest price during the day
**Low**: Lowest price during the day
**Close**: Last traded price of the day
**Volume**: Number of shares traded

---

#### Returns

**Simple Return**
```
Return = (Price_end - Price_start) / Price_start × 100
```

**Log Return** (for compounding)
```
Log Return = ln(Price_end / Price_start)
```

**Annualized Return**
```
Annualized = (1 + Return)^(252/days) - 1
```
Note: 252 = typical trading days per year

---

#### Volatility

**Standard Deviation of Returns**
- Measures price fluctuation
- Higher volatility = higher risk
- Typically calculated over 20 or 60 days

**Beta**
- Measures stock's volatility relative to market
- Beta > 1: More volatile than market
- Beta < 1: Less volatile than market

---

### Indian Market Structure

#### Exchanges
- **NSE (National Stock Exchange)**: Primary exchange
- **BSE (Bombay Stock Exchange)**: Oldest exchange in Asia

#### Market Indices
- **NIFTY 50**: Top 50 companies by market cap
- **NIFTY 500**: Broader market index
- **SENSEX**: BSE's 30-stock index

#### Trading Hours
- Pre-open: 9:00 AM - 9:15 AM IST
- Normal: 9:15 AM - 3:30 PM IST
- Post-close: 3:40 PM - 4:00 PM IST

---

## 2. Dataset Catalog

### 2.1 Price Data

#### fact_daily_prices

**Purpose**: Daily OHLCV data for all securities

**Schema**:
```sql
CREATE TABLE presentation.fact_daily_prices (
    price_key BIGINT PRIMARY KEY,
    security_key INTEGER,
    date_key DATE,
    price_date DATE,
    
    -- OHLCV data (adjusted for corporate actions)
    open_price DECIMAL(18,4),
    high_price DECIMAL(18,4),
    low_price DECIMAL(18,4),
    close_price DECIMAL(18,4),
    volume BIGINT,
    turnover DECIMAL(18,2),
    
    -- Calculated metrics
    price_change DECIMAL(18,4),
    price_change_pct DECIMAL(10,4),
    
    -- Technical indicators
    vwap DECIMAL(18,4),  -- Volume Weighted Average Price
    
    load_timestamp TIMESTAMP
);
```

**Data Frequency**: Daily
**Historical Coverage**: 2000-present
**Update Schedule**: Daily at 6:00 PM IST (after market close)
**Source**: NSE/BSE market data feeds

**Sample Data**:
```
security_id | price_date  | open    | high    | low     | close   | volume
RELIANCE    | 2024-01-15  | 2450.50 | 2475.00 | 2440.00 | 2470.25 | 5000000
TCS         | 2024-01-15  | 3650.00 | 3680.50 | 3640.00 | 3675.75 | 2500000
```

**Key Features**:
- Adjusted for corporate actions (splits, dividends)
- Includes delisted securities (survivorship-free)
- Trading day calendar aligned with NSE holidays

---

### 2.2 Financial Statements

#### fact_quarterly_financials

**Purpose**: Quarterly financial statements (P&L, Balance Sheet, Cash Flow)

**Schema**:
```sql
CREATE TABLE presentation.fact_quarterly_financials (
    financial_key BIGINT PRIMARY KEY,
    security_key INTEGER,
    reporting_period_end DATE,
    publication_date DATE,  -- CRITICAL for point-in-time
    
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
    eps DECIMAL(10,4),  -- Earnings Per Share
    
    -- Balance Sheet
    total_assets DECIMAL(18,2),
    current_assets DECIMAL(18,2),
    non_current_assets DECIMAL(18,2),
    total_liabilities DECIMAL(18,2),
    current_liabilities DECIMAL(18,2),
    non_current_liabilities DECIMAL(18,2),
    total_equity DECIMAL(18,2),
    
    -- Cash Flow Statement
    operating_cash_flow DECIMAL(18,2),
    investing_cash_flow DECIMAL(18,2),
    financing_cash_flow DECIMAL(18,2),
    free_cash_flow DECIMAL(18,2),
    
    load_timestamp TIMESTAMP
);
```

**Data Frequency**: Quarterly
**Historical Coverage**: 2010-present
**Update Schedule**: Within 48 hours of company filing
**Source**: Company filings, BSE/NSE announcements

**Key Metrics Explained**:

**EBITDA** (Earnings Before Interest, Tax, Depreciation, Amortization)
- Operating profitability measure
- Excludes financing and accounting decisions

**EBIT** (Earnings Before Interest and Tax)
- Operating profit after depreciation
- Shows core business profitability

**EPS** (Earnings Per Share)
```
EPS = Net Income / Weighted Average Shares Outstanding
```

**Free Cash Flow**
```
FCF = Operating Cash Flow - Capital Expenditures
```

---

### 2.3 Institutional Flows

#### fact_daily_flows

**Purpose**: Daily institutional investor buying/selling activity

**Schema**:
```sql
CREATE TABLE presentation.fact_daily_flows (
    flow_key BIGINT PRIMARY KEY,
    security_key INTEGER,
    flow_date DATE,
    
    -- FII (Foreign Institutional Investors)
    fii_buy_value DECIMAL(18,2),
    fii_sell_value DECIMAL(18,2),
    net_fii_flow DECIMAL(18,2),
    
    -- DII (Domestic Institutional Investors)
    dii_buy_value DECIMAL(18,2),
    dii_sell_value DECIMAL(18,2),
    net_dii_flow DECIMAL(18,2),
    
    -- Retail
    retail_buy_value DECIMAL(18,2),
    retail_sell_value DECIMAL(18,2),
    net_retail_flow DECIMAL(18,2),
    
    load_timestamp TIMESTAMP
);
```

**Data Frequency**: Daily
**Historical Coverage**: 2015-present
**Update Schedule**: Daily at 7:00 PM IST
**Source**: NSE/BSE institutional activity reports

**Key Concepts**:

**FII (Foreign Institutional Investors)**
- Foreign mutual funds, pension funds, hedge funds
- Significant market movers
- Net buying typically bullish signal

**DII (Domestic Institutional Investors)**
- Indian mutual funds, insurance companies
- Often counter-balance FII flows
- Long-term investors

**Net Flow**
```
Net Flow = Buy Value - Sell Value
```
- Positive = Net buying (bullish)
- Negative = Net selling (bearish)

---

### 2.4 Corporate Actions

#### corporate_actions

**Purpose**: Track stock splits, dividends, bonuses, and other corporate events

**Schema**:
```sql
CREATE TABLE integration.corporate_actions (
    action_id INTEGER PRIMARY KEY,
    security_id VARCHAR(50),
    action_type VARCHAR(20),  -- SPLIT, DIVIDEND, BONUS, RIGHTS, MERGER
    ex_date DATE,             -- Date when action takes effect
    record_date DATE,
    payment_date DATE,
    
    -- Split details
    split_ratio_from INTEGER,  -- 1:2 split = from:1, to:2
    split_ratio_to INTEGER,
    
    -- Dividend details
    dividend_amount DECIMAL(18,4),  -- Per share
    
    -- Bonus details
    bonus_ratio_from INTEGER,  -- 1:1 bonus = from:1, to:1
    bonus_ratio_to INTEGER,
    
    -- Calculated adjustment factor
    adjustment_factor DECIMAL(18,10),
    
    details VARCHAR(MAX)
);
```

**Data Frequency**: Event-driven
**Historical Coverage**: 2000-present
**Update Schedule**: Real-time as announced
**Source**: Company announcements, exchange circulars

---

## 3. Financial Metrics and Ratios

### 3.1 Profitability Ratios

#### Gross Margin
```sql
Gross Margin % = (Gross Profit / Revenue) × 100
```
**Interpretation**: Percentage of revenue retained after direct costs
**Good Range**: 30-50% (varies by industry)

#### EBITDA Margin
```sql
EBITDA Margin % = (EBITDA / Revenue) × 100
```
**Interpretation**: Operating profitability before financing
**Good Range**: 15-25% (varies by industry)

#### Net Margin
```sql
Net Margin % = (Net Income / Revenue) × 100
```
**Interpretation**: Bottom-line profitability
**Good Range**: 10-20% (varies by industry)

#### ROA (Return on Assets)
```sql
ROA % = (Net Income / Total Assets) × 100
```
**Interpretation**: How efficiently assets generate profit
**Good Range**: > 5%

#### ROE (Return on Equity)
```sql
ROE % = (Net Income / Total Equity) × 100
```
**Interpretation**: Return generated for shareholders
**Good Range**: > 15%

---

### 3.2 Leverage Ratios

#### Debt-to-Equity
```sql
D/E = Total Liabilities / Total Equity
```
**Interpretation**: Financial leverage
**Good Range**: < 2.0 (varies by industry)

#### Equity Ratio
```sql
Equity Ratio % = (Total Equity / Total Assets) × 100
```
**Interpretation**: Proportion of assets financed by equity
**Good Range**: > 40%

---

### 3.3 Valuation Ratios

#### P/E Ratio (Price-to-Earnings)
```sql
P/E = Market Price per Share / Earnings per Share
```
**Interpretation**: How much investors pay for each rupee of earnings
**Typical Range**: 15-25 (varies by sector)

#### P/B Ratio (Price-to-Book)
```sql
P/B = Market Price per Share / Book Value per Share
```
**Interpretation**: Market value vs accounting value
**Typical Range**: 1-3

#### EV/EBITDA (Enterprise Value to EBITDA)
```sql
EV/EBITDA = (Market Cap + Debt - Cash) / EBITDA
```
**Interpretation**: Valuation independent of capital structure
**Typical Range**: 8-15

---

### 3.4 Growth Metrics

#### Revenue Growth (YoY)
```sql
Revenue Growth % = ((Revenue_current - Revenue_4q_ago) / Revenue_4q_ago) × 100
```

#### Earnings Growth (YoY)
```sql
Earnings Growth % = ((EPS_current - EPS_4q_ago) / EPS_4q_ago) × 100
```

---

## 4. Corporate Actions

### 4.1 Stock Split

**Definition**: Division of existing shares into multiple shares

**Example**: 1:2 Split
- Before: 1 share at ₹1000
- After: 2 shares at ₹500 each
- Total value unchanged

**Price Adjustment**:
```sql
Adjustment Factor = split_ratio_from / split_ratio_to
Historical Price = Unadjusted Price × Adjustment Factor
```

**Impact**:
- Increases liquidity
- Makes stock more affordable
- No change in market cap

---

### 4.2 Dividend

**Definition**: Cash distribution to shareholders

**Types**:
- **Cash Dividend**: Direct cash payment
- **Stock Dividend**: Additional shares instead of cash

**Ex-Date**: Date when stock trades without dividend

**Price Adjustment**:
```sql
Adjustment Factor = (Price - Dividend) / Price
Historical Price = Unadjusted Price × Adjustment Factor
```

**Example**:
- Stock trading at ₹100
- Dividend of ₹10 declared
- On ex-date, stock opens at ₹90
- Historical prices adjusted by factor 0.9

---

### 4.3 Bonus Issue

**Definition**: Free additional shares to existing shareholders

**Example**: 1:1 Bonus
- Before: 1 share at ₹1000
- After: 2 shares at ₹500 each
- Similar to stock split

**Price Adjustment**:
```sql
Adjustment Factor = bonus_from / (bonus_from + bonus_to)
```

---

### 4.4 Rights Issue

**Definition**: Offer to buy additional shares at discounted price

**Example**: 1:5 Rights at ₹800
- Existing shareholders can buy 1 new share for every 5 held
- At price of ₹800 (below market price)

**Theoretical Ex-Rights Price (TERP)**:
```sql
TERP = (Market Price × Existing Shares + Rights Price × New Shares) / Total Shares
```

---

## 5. Market Microstructure

### 5.1 Order Types

**Market Order**: Execute immediately at best available price
**Limit Order**: Execute only at specified price or better
**Stop Loss**: Trigger market order when price reaches threshold

### 5.2 Trading Mechanisms

**Continuous Trading**: 9:15 AM - 3:30 PM
- Orders matched continuously
- Price-time priority

**Auction Sessions**:
- Pre-open (9:00-9:15 AM): Determine opening price
- Post-close (3:40-4:00 PM): Closing price determination

### 5.3 Circuit Breakers

**Individual Stock Limits**:
- 5%, 10%, 20% price bands
- Trading halted if breached

**Market-Wide Limits**:
- 10% decline: 45-minute halt
- 15% decline: 1.75-hour halt
- 20% decline: Trading suspended for day

---

## 6. Data Relationships

### 6.1 Dimension Tables

#### dim_security

**Purpose**: Master list of all securities with SCD Type 2

**Key Fields**:
- `security_key`: Surrogate key
- `security_id`: Business key (NSE symbol)
- `isin`: International identifier
- `sector`, `industry`: Classification
- `market_cap_category`: LARGECAP, MIDCAP, SMALLCAP
- `valid_from`, `valid_to`: SCD Type 2 tracking
- `is_current`: Current version flag

**SCD Type 2 Example**:
```
security_key | security_id | sector      | valid_from | valid_to   | is_current
1            | RELIANCE    | Energy      | 2020-01-01 | 2023-06-30 | FALSE
2            | RELIANCE    | Diversified | 2023-07-01 | NULL       | TRUE
```

---

#### dim_date

**Purpose**: Date dimension with fiscal calendar

**Key Fields**:
- `date_key`: Date (primary key)
- `year`, `quarter`, `month`: Calendar hierarchy
- `is_trading_day`: TRUE for NSE trading days
- `is_weekend`, `is_month_end`, `is_quarter_end`
- `fiscal_year`, `fiscal_quarter`: Indian fiscal year (Apr-Mar)
- `previous_trading_day`, `next_trading_day`: Navigation

**Usage**:
```sql
-- Get last trading day of month
SELECT date_key 
FROM dim_date 
WHERE is_month_end = TRUE 
  AND is_trading_day = TRUE;
```

---

#### dim_index_constituents

**Purpose**: Track index membership over time (survivorship-free)

**Key Fields**:
- `index_name`: NIFTY50, NIFTY500, etc.
- `security_key`: Reference to dim_security
- `effective_date`: When security joined index
- `exit_date`: When security left index (NULL if current)
- `is_current`: Current member flag
- `weight`: Percentage weight in index

**Survivorship Bias Prevention**:
```sql
-- Get NIFTY50 constituents as of 2020-01-01
SELECT s.security_id
FROM dim_index_constituents ic
JOIN dim_security s ON ic.security_key = s.security_key
WHERE ic.index_name = 'NIFTY50'
  AND ic.effective_date <= '2020-01-01'
  AND (ic.exit_date IS NULL OR ic.exit_date > '2020-01-01');
```

---

### 6.2 Vault Tables (Integration Layer)

#### vault_financials

**Purpose**: Bi-temporal storage of financial statements

**Key Concepts**:

**Valid Time**: When the data was true in reality
- `reporting_period_end`: Quarter end date

**Transaction Time**: When we learned about the data
- `publication_date`: When company published results

**System Time**: When data entered our system
- `valid_from`, `valid_to`: Version tracking

**Restatement Handling**:
```
vault_key | security_id | period_end | pub_date   | revenue | valid_from | is_current
1         | TCS         | 2023-12-31 | 2024-01-15 | 50000   | 2024-01-15 | FALSE
2         | TCS         | 2023-12-31 | 2024-02-01 | 51000   | 2024-02-01 | TRUE
```
Company restated Q4 revenue from 50000 to 51000

---

### 6.3 Fact Tables (Presentation Layer)

#### Star Schema Design

```
        dim_date
            |
            |
        fact_daily_prices ---- dim_security
            |
            |
    dim_index_constituents
```

**Benefits**:
- Optimized for analytics
- Simple join patterns
- Fast aggregations

---

### 6.4 Materialized Views

#### mv_precomputed_ratios

**Purpose**: Pre-calculate financial ratios for fast queries

**Refresh Schedule**: Daily at 7:00 AM IST

**Contents**:
- All profitability ratios
- Leverage ratios
- YoY growth metrics

**Performance Benefit**: 10x faster than calculating on-the-fly

---

#### mv_rolling_returns

**Purpose**: Pre-calculate returns for multiple time periods

**Contents**:
- 1-day, 1-week, 1-month, 3-month, 6-month, 1-year, 3-year returns
- 20-day volatility
- Volume metrics

**Usage**:
```sql
-- Find top performers (6-month return)
SELECT security_name, return_6m_pct
FROM mv_rolling_returns
WHERE price_date = CURRENT_DATE
ORDER BY return_6m_pct DESC
LIMIT 10;
```

---

## Summary

### Dataset Overview

| Dataset | Records | Frequency | History | Purpose |
|---------|---------|-----------|---------|---------|
| fact_daily_prices | ~500M | Daily | 2000-present | Price/volume data |
| fact_quarterly_financials | ~50K | Quarterly | 2010-present | Financial statements |
| fact_daily_flows | ~10M | Daily | 2015-present | Institutional flows |
| corporate_actions | ~5K | Event | 2000-present | Splits, dividends |
| dim_security | ~3K | SCD Type 2 | All time | Security master |
| dim_date | ~9K | Static | 2000-2030 | Date dimension |
| dim_index_constituents | ~10K | Event | 2010-present | Index membership |

### Key Domain Concepts

1. **Equity Fundamentals**: Ownership, market cap, returns, volatility
2. **Financial Statements**: P&L, Balance Sheet, Cash Flow
3. **Corporate Actions**: Splits, dividends, bonuses - require price adjustments
4. **Institutional Flows**: FII/DII activity as market sentiment indicator
5. **Temporal Correctness**: Point-in-time queries prevent look-ahead bias
6. **Survivorship Bias**: Include delisted stocks for accurate backtesting

### Critical Data Strategies

1. **Bi-Temporal Model**: Track both valid time and transaction time
2. **Corporate Action Adjustments**: Maintain price continuity
3. **SCD Type 2**: Track dimension changes over time
4. **Survivorship-Free**: Include all securities, even delisted
5. **Point-in-Time Queries**: Use publication_date for temporal correctness

---

## Glossary

**OHLCV**: Open, High, Low, Close, Volume
**EBITDA**: Earnings Before Interest, Tax, Depreciation, Amortization
**EPS**: Earnings Per Share
**P/E**: Price-to-Earnings ratio
**ROE**: Return on Equity
**ROA**: Return on Assets
**FII**: Foreign Institutional Investors
**DII**: Domestic Institutional Investors
**NSE**: National Stock Exchange
**BSE**: Bombay Stock Exchange
**ISIN**: International Securities Identification Number
**SCD**: Slowly Changing Dimension
**YoY**: Year-over-Year
**QoQ**: Quarter-over-Quarter
**VWAP**: Volume Weighted Average Price
**Market Cap**: Market Capitalization
**Free Float**: Shares available for public trading
**Circuit Breaker**: Trading halt mechanism
**Ex-Date**: Date when corporate action takes effect
