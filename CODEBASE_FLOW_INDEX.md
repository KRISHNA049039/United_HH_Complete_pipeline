# Research Data Platform V2 - Codebase Flow Documentation

This documentation has been split into multiple parts for easier navigation and readability.

## Documentation Parts

### [Part 1: Entry Points & Data Flow](CODEBASE_FLOW_1.md)
- System entry points (S3 upload, API requests, scheduled jobs)
- Complete end-to-end data flow for daily price data
- 10-step pipeline visualization from data collection to analyst consumption

### [Part 2: Critical Data Strategies](CODEBASE_FLOW_2.md)
- Bi-temporal data model implementation
- Job bookmarks for incremental processing
- Idempotent pipeline design patterns
- Corporate action adjustments
- Temporal validation to prevent look-ahead bias
- Performance optimization techniques

### [Part 3: Code Organization & Implementation](CODEBASE_FLOW_3.md)
- Complete project structure
- Lambda validator implementation details
- Glue ETL job flow
- API query execution flow
- Summary of critical strategies and key files

## Quick Reference

**Complete Data Flow:**
```
Data Collection → S3 → Lambda Validator → Glue ETL → 
Redshift (Bronze → Silver → Gold) → API → Analysts
```

**Key Components:**
- Entry: `data-collection/collect_daily_prices.py`
- Validation: `lambda/validators/price_validator.py`
- ETL: `glue/daily_prices_etl.py`
- Schema: `redshift/schemas/*.sql`
- API: `api/main.py`
