# Source Data Ingestion Guide

## Overview

This document explains how data flows from source systems into the Research Data Platform V2, including all data collection methods, automation scripts, and ingestion patterns.

---

## Table of Contents

1. [Data Sources Overview](#data-sources-overview)
2. [Data Collection Methods](#data-collection-methods)
3. [Ingestion Scripts](#ingestion-scripts)
4. [File Formats & Standards](#file-formats--standards)
5. [Automation & Scheduling](#automation--scheduling)
6. [Monitoring & Alerts](#monitoring--alerts)

---

## 1. Data Sources Overview

### Internal Data Collection (Your Team)

Since all data sources are managed by your internal team, you have full control over:
- Data collection timing
- Data format and quality
- Upload schedules
- Source system access

### Data Source Types

| Data Type | Source | Frequency | Volume | Collection Method |
|-----------|--------|-----------|--------|-------------------|
| **Daily Prices** | NSE/BSE APIs | Daily | 3,000 securities | Automated Script |
| **Quarterly Financials** | Company Filings | Quarterly | ~240K rows | Manual + Script |
| **FII/DII Flows** | NSE/BSE Reports | Daily | 3,000 securities | Automated Script |
| **Corporate Actions** | Exchange Announcements | As announced | ~50/month | Manual Upload |
| **Index Constituents** | Index Provider | Monthly | ~500 securities | Manual Upload |
| **Macro Data** | RBI/MOSPI APIs | Monthly | ~100 indicators | Automated Script |

---

## 2. Data Collection Methods

### Method 1: Automated Python Scripts (Recommended)

**Use For:** Daily prices, FII/DII flows, macro data

**Location:** `data-collection/` folder

**How It Works:**
```
Scheduled Script → Collect from API → Transform → Upload to S3 → Automatic Processing
```

### Method 2: Manual Upload

**Use For:** Quarterly financials, corporate actions, one-time loads

**How It Works:**
```
Analyst Prepares File → Upload via AWS Console/CLI → Automatic Processing
```

### Method 3: Lambda-Based Collection (Advanced)

**Use For:** Real-time data, scheduled collection without infrastructure

**How It Works:**
```
EventBridge Schedule → Lambda Function → Collect Data → Upload to S3 → Automatic Processing
```

---

## 3. Ingestion Scripts

### Script 1: Daily Prices Collection

**File:** `data-collection/collect_daily_prices.py`

```python
#!/usr/bin/env python3
"""
Daily Market Prices Collection Script

Purpose: Collect daily OHLCV data from NSE/BSE
Schedule: Daily at 6:30 PM IST (after market close)
Output: CSV file uploaded to S3
Trigger: Automatic processing via S3 event
"""

import boto3
import pandas as pd
import requests
from datetime import datetime
import logging
import json

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# AWS Configuration
S3_BUCKET = 'itus-data-lake'
S3_PREFIX = 'raw/prices'

# Initialize AWS clients
s3 = boto3.client('s3')
sns = boto3.client('sns')

class PriceDataCollector:
    """Collect daily price data from NSE/BSE"""
    
    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0',
            'Accept': 'application/json'
        })
    
    def collect_nse_data(self, index='NIFTY 50'):
        """
        Collect data from NSE API
        
        NSE provides free APIs for market data:
        - Equity indices
        - Stock quotes
        - Historical data
        """
        try:
            # NSE API endpoint
            url = f"https://www.nseindia.com/api/equity-stockIndices?index={index.replace(' ', '%20')}"
            
            # Get data
            response = self.session.get(url, timeout=30)
            response.raise_for_status()
            
            data = response.json()
            
            # Extract relevant fields
            records = []
            for item in data.get('data', []):
                records.append({
                    'security_id': item['symbol'],
                    'price_date': datetime.now().strftime('%Y-%m-%d'),
                    'open': float(item.get('open', 0)),
                    'high': float(item.get('dayHigh', 0)),
                    'low': float(item.get('dayLow', 0)),
                    'close': float(item.get('lastPrice', 0)),
                    'volume': int(item.get('totalTradedVolume', 0)),
                    'turnover': float(item.get('totalTradedValue', 0)),
                    'source': 'NSE'
                })
            
            logger.info(f"Collected {len(records)} records from NSE {index}")
            return pd.DataFrame(records)
            
        except Exception as e:
            logger.error(f"Error collecting NSE data: {e}")
            raise
    
    def collect_bse_data(self):
        """
        Collect data from BSE
        
        Note: BSE requires registration for API access
        Alternative: Download CSV from BSE website
        """
        try:
            # BSE provides daily bhav copy (CSV file)
            date_str = datetime.now().strftime('%d%m%y')
            url = f"https://www.bseindia.com/download/BhavCopy/Equity/EQ{date_str}_CSV.ZIP"
            
            # Download and extract
            # Implementation depends on BSE data format
            
            logger.info("Collected data from BSE")
            return pd.DataFrame()  # Placeholder
            
        except Exception as e:
            logger.error(f"Error collecting BSE data: {e}")
            return pd.DataFrame()
    
    def validate_data(self, df):
        """Validate collected data before upload"""
        
        issues = []
        
        # Check required columns
        required_cols = ['security_id', 'price_date', 'open', 'high', 'low', 'close', 'volume']
        missing_cols = [col for col in required_cols if col not in df.columns]
        if missing_cols:
            issues.append(f"Missing columns: {missing_cols}")
        
        # Check for nulls
        null_counts = df[required_cols].isnull().sum()
        if null_counts.any():
            issues.append(f"Null values found: {null_counts[null_counts > 0].to_dict()}")
        
        # Check price ranges
        if (df['close'] <= 0).any():
            issues.append(f"Invalid prices found: {len(df[df['close'] <= 0])} records")
        
        # Check high >= low
        if (df['high'] < df['low']).any():
            issues.append(f"High < Low found: {len(df[df['high'] < df['low']])} records")
        
        if issues:
            logger.warning(f"Validation issues: {issues}")
            return False, issues
        
        logger.info("Data validation passed")
        return True, []
    
    def upload_to_s3(self, df, data_type='prices'):
        """Upload data to S3"""
        
        try:
            # Generate S3 key
            today = datetime.now()
            s3_key = f"{S3_PREFIX}/{today.year}/{today.month:02d}/{today.day:02d}/nse_prices_{today.strftime('%Y%m%d')}.csv"
            
            # Convert to CSV
            csv_buffer = df.to_csv(index=False)
            
            # Upload to S3
            s3.put_object(
                Bucket=S3_BUCKET,
                Key=s3_key,
                Body=csv_buffer,
                Metadata={
                    'source': 'nse_api',
                    'collection_time': datetime.now().isoformat(),
                    'record_count': str(len(df)),
                    'collector': 'automated_script'
                },
                ContentType='text/csv'
            )
            
            logger.info(f"✓ Uploaded to s3://{S3_BUCKET}/{s3_key}")
            logger.info(f"✓ {len(df)} records uploaded")
            logger.info(f"✓ S3 event will trigger Lambda validator in ~30 seconds")
            
            return s3_key
            
        except Exception as e:
            logger.error(f"Error uploading to S3: {e}")
            raise
    
    def send_notification(self, success, message, s3_key=None):
        """Send SNS notification about collection status"""
        
        try:
            subject = "✓ Daily Price Collection Success" if success else "✗ Daily Price Collection Failed"
            
            body = f"""
Daily Price Data Collection Report

Status: {'SUCCESS' if success else 'FAILED'}
Timestamp: {datetime.now().isoformat()}
Message: {message}
"""
            if s3_key:
                body += f"\nS3 Location: s3://{S3_BUCKET}/{s3_key}"
            
            # Uncomment when SNS topic is configured
            # sns.publish(
            #     TopicArn='arn:aws:sns:us-east-1:123456789012:data-collection-alerts',
            #     Subject=subject,
            #     Message=body
            # )
            
            logger.info(f"Notification sent: {subject}")
            
        except Exception as e:
            logger.error(f"Error sending notification: {e}")

def main():
    """Main execution function"""
    
    logger.info("=" * 60)
    logger.info("Starting Daily Price Data Collection")
    logger.info("=" * 60)
    
    collector = PriceDataCollector()
    
    try:
        # Collect data from NSE
        logger.info("Step 1: Collecting data from NSE...")
        df_nse = collector.collect_nse_data('NIFTY 50')
        
        # Optionally collect from other indices
        # df_nifty500 = collector.collect_nse_data('NIFTY 500')
        # df = pd.concat([df_nse, df_nifty500]).drop_duplicates(subset=['security_id'])
        
        df = df_nse
        
        # Validate data
        logger.info("Step 2: Validating data...")
        is_valid, issues = collector.validate_data(df)
        
        if not is_valid:
            raise ValueError(f"Data validation failed: {issues}")
        
        # Upload to S3
        logger.info("Step 3: Uploading to S3...")
        s3_key = collector.upload_to_s3(df)
        
        # Send success notification
        collector.send_notification(
            success=True,
            message=f"Successfully collected and uploaded {len(df)} records",
            s3_key=s3_key
        )
        
        logger.info("=" * 60)
        logger.info("Daily Price Collection Completed Successfully")
        logger.info("=" * 60)
        
        return 0
        
    except Exception as e:
        logger.error(f"Collection failed: {e}")
        
        # Send failure notification
        collector.send_notification(
            success=False,
            message=str(e)
        )
        
        return 1

if __name__ == '__main__':
    exit(main())
```

**Setup Instructions:**

```bash
# 1. Install dependencies
pip install boto3 pandas requests

# 2. Configure AWS credentials
aws configure
# Enter your AWS Access Key ID
# Enter your AWS Secret Access Key
# Default region: us-east-1

# 3. Test the script
python collect_daily_prices.py

# 4. Schedule with cron (Linux/Mac)
crontab -e
# Add line: 30 18 * * * /usr/bin/python3 /path/to/collect_daily_prices.py >> /var/log/price_collection.log 2>&1

# 5. Or schedule with Task Scheduler (Windows)
# - Open Task Scheduler
# - Create Basic Task
# - Trigger: Daily at 6:30 PM
# - Action: Start a program
# - Program: python.exe
# - Arguments: C:\path\to\collect_daily_prices.py
```

---

### Script 2: FII/DII Flows Collection

**File:** `data-collection/collect_fii_dii_flows.py`

```python
#!/usr/bin/env python3
"""
FII/DII Institutional Flows Collection

Purpose: Collect daily institutional flow data
Schedule: Daily at 7:00 PM IST
Source: NSE reports
"""

import boto3
import pandas as pd
import requests
from datetime import datetime
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

S3_BUCKET = 'itus-data-lake'
s3 = boto3.client('s3')

def collect_fii_dii_data():
    """
    Collect FII/DII flow data from NSE
    
    NSE publishes daily FII/DII activity reports
    """
    try:
        # NSE FII/DII data endpoint
        url = "https://www.nseindia.com/api/fiidiiTrading"
        
        headers = {
            'User-Agent': 'Mozilla/5.0',
            'Accept': 'application/json'
        }
        
        response = requests.get(url, headers=headers, timeout=30)
        response.raise_for_status()
        
        data = response.json()
        
        # Parse data
        records = []
        for item in data.get('data', []):
            records.append({
                'flow_date': datetime.now().strftime('%Y-%m-%d'),
                'category': item.get('category'),
                'buy_value': float(item.get('buyValue', 0)),
                'sell_value': float(item.get('sellValue', 0)),
                'net_value': float(item.get('netValue', 0))
            })
        
        df = pd.DataFrame(records)
        logger.info(f"Collected {len(df)} FII/DII flow records")
        
        return df
        
    except Exception as e:
        logger.error(f"Error collecting FII/DII data: {e}")
        raise

def upload_flows_to_s3(df):
    """Upload flows data to S3"""
    
    today = datetime.now()
    s3_key = f"raw/flows/{today.year}/{today.month:02d}/{today.day:02d}/fii_dii_flows_{today.strftime('%Y%m%d')}.csv"
    
    s3.put_object(
        Bucket=S3_BUCKET,
        Key=s3_key,
        Body=df.to_csv(index=False),
        ContentType='text/csv'
    )
    
    logger.info(f"✓ Uploaded to s3://{S3_BUCKET}/{s3_key}")

def main():
    logger.info("Starting FII/DII Flows Collection")
    
    df = collect_fii_dii_data()
    upload_flows_to_s3(df)
    
    logger.info("FII/DII Flows Collection Completed")

if __name__ == '__main__':
    main()
```

---

### Script 3: Macro Data Collection

**File:** `data-collection/collect_macro_data.py`

```python
#!/usr/bin/env python3
"""
Macro Economic Data Collection

Purpose: Collect macro indicators from RBI/MOSPI
Schedule: Monthly (1st of month)
Sources:
- RBI Database on Indian Economy (DBIE)
- Ministry of Statistics (MOSPI)
- World Bank Open Data
"""

import boto3
import pandas as pd
import requests
from datetime import datetime
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

S3_BUCKET = 'itus-data-lake'
s3 = boto3.client('s3')

class MacroDataCollector:
    """Collect macro economic indicators"""
    
    def collect_rbi_data(self):
        """
        Collect data from RBI DBIE
        
        RBI provides APIs for:
        - Interest rates (Repo, Reverse Repo)
        - Inflation (CPI, WPI)
        - Exchange rates
        - Money supply
        """
        try:
            # RBI DBIE API
            # Note: Requires registration at https://dbie.rbi.org.in/
            
            indicators = {
                'repo_rate': 'REPO_RATE_ID',
                'cpi_inflation': 'CPI_ID',
                'usd_inr': 'EXCHANGE_RATE_ID'
            }
            
            records = []
            
            for indicator_name, indicator_id in indicators.items():
                # API call to RBI
                # url = f"https://dbie.rbi.org.in/api/data?indicator={indicator_id}"
                # response = requests.get(url)
                # data = response.json()
                
                # Placeholder - implement based on actual RBI API
                records.append({
                    'indicator_name': indicator_name,
                    'indicator_date': datetime.now().strftime('%Y-%m-01'),
                    'value': 0.0,  # Replace with actual value
                    'source': 'RBI'
                })
            
            logger.info(f"Collected {len(records)} RBI indicators")
            return pd.DataFrame(records)
            
        except Exception as e:
            logger.error(f"Error collecting RBI data: {e}")
            return pd.DataFrame()
    
    def collect_world_bank_data(self):
        """
        Collect data from World Bank Open Data API
        
        World Bank provides free APIs for:
        - GDP growth
        - Unemployment
        - Trade data
        """
        try:
            # World Bank API
            country_code = 'IND'  # India
            indicators = ['NY.GDP.MKTP.KD.ZG']  # GDP growth
            
            records = []
            
            for indicator in indicators:
                url = f"https://api.worldbank.org/v2/country/{country_code}/indicator/{indicator}?format=json&date=2020:2024"
                
                response = requests.get(url, timeout=30)
                data = response.json()
                
                if len(data) > 1:
                    for item in data[1]:
                        records.append({
                            'indicator_name': item['indicator']['value'],
                            'indicator_date': f"{item['date']}-01-01",
                            'value': float(item['value']) if item['value'] else None,
                            'source': 'WorldBank'
                        })
            
            logger.info(f"Collected {len(records)} World Bank indicators")
            return pd.DataFrame(records)
            
        except Exception as e:
            logger.error(f"Error collecting World Bank data: {e}")
            return pd.DataFrame()
    
    def upload_to_s3(self, df):
        """Upload macro data to S3"""
        
        today = datetime.now()
        s3_key = f"raw/macro/{today.year}/{today.month:02d}/macro_data_{today.strftime('%Y%m')}.csv"
        
        s3.put_object(
            Bucket=S3_BUCKET,
            Key=s3_key,
            Body=df.to_csv(index=False),
            ContentType='text/csv'
        )
        
        logger.info(f"✓ Uploaded to s3://{S3_BUCKET}/{s3_key}")

def main():
    logger.info("Starting Macro Data Collection")
    
    collector = MacroDataCollector()
    
    # Collect from multiple sources
    df_rbi = collector.collect_rbi_data()
    df_wb = collector.collect_world_bank_data()
    
    # Combine
    df = pd.concat([df_rbi, df_wb], ignore_index=True)
    
    # Upload
    collector.upload_to_s3(df)
    
    logger.info(f"Macro Data Collection Completed: {len(df)} indicators")

if __name__ == '__main__':
    main()
```

**Macro Data Sources:**

| Indicator | Source | API/URL | Frequency |
|-----------|--------|---------|-----------|
| Repo Rate | RBI | https://dbie.rbi.org.in/ | Monthly |
| CPI Inflation | MOSPI | https://mospi.gov.in/ | Monthly |
| GDP Growth | World Bank | https://api.worldbank.org/ | Quarterly |
| USD/INR | RBI | https://dbie.rbi.org.in/ | Daily |
| Crude Oil Price | EIA | https://www.eia.gov/opendata/ | Daily |
| Gold Price | World Gold Council | Manual | Daily |

---

### Script 4: Manual Upload Helper

**File:** `data-collection/manual_upload.py`

```python
#!/usr/bin/env python3
"""
Manual Upload Helper

Purpose: Help analysts upload files to S3 with proper formatting
Use For: Quarterly financials, corporate actions, one-time loads
"""

import boto3
import pandas as pd
from datetime import datetime
import sys
import os

S3_BUCKET = 'itus-data-lake'
s3 = boto3.client('s3')

def upload_file(local_file, data_type, date=None):
    """
    Upload file to S3 with proper path structure
    
    Args:
        local_file: Path to local file
        data_type: Type of data (prices, financials, flows, corporate_actions)
        date: Date for the data (YYYY-MM-DD), defaults to today
    """
    
    if not os.path.exists(local_file):
        print(f"Error: File not found: {local_file}")
        return False
    
    # Parse date
    if date is None:
        dt = datetime.now()
    else:
        dt = datetime.strptime(date, '%Y-%m-%d')
    
    # Generate S3 key based on data type
    if data_type == 'financials':
        quarter = f"Q{(dt.month-1)//3 + 1}"
        s3_key = f"raw/financials/{dt.year}/{quarter}/{os.path.basename(local_file)}"
    else:
        s3_key = f"raw/{data_type}/{dt.year}/{dt.month:02d}/{dt.day:02d}/{os.path.basename(local_file)}"
    
    # Upload
    try:
        s3.upload_file(
            local_file,
            S3_BUCKET,
            s3_key,
            ExtraArgs={
                'Metadata': {
                    'upload_time': datetime.now().isoformat(),
                    'uploaded_by': 'manual_upload_script'
                }
            }
        )
        
        print(f"✓ Successfully uploaded to s3://{S3_BUCKET}/{s3_key}")
        print(f"✓ Automatic processing will begin shortly")
        print(f"✓ Check CloudWatch logs for processing status")
        
        return True
        
    except Exception as e:
        print(f"✗ Upload failed: {e}")
        return False

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: python manual_upload.py <file> <data_type> [date]")
        print("Example: python manual_upload.py financials_q1.csv financials 2024-03-31")
        print("Data types: prices, financials, flows, corporate_actions")
        sys.exit(1)
    
    local_file = sys.argv[1]
    data_type = sys.argv[2]
    date = sys.argv[3] if len(sys.argv) > 3 else None
    
    upload_file(local_file, data_type, date)
```

**Usage:**
```bash
# Upload quarterly financials
python manual_upload.py Q1_2024_financials.csv financials 2024-03-31

# Upload corporate actions
python manual_upload.py corporate_actions_jan.csv corporate_actions 2024-01-31

# Upload historical prices
python manual_upload.py historical_2020.csv prices 2020-12-31
```

---

## 4. File Formats & Standards

### Standard CSV Format

All CSV files must follow this format:

```csv
# Header row required
# UTF-8 encoding
# Comma delimiter
# No special characters in field names
# Date format: YYYY-MM-DD
# Numbers: No commas, use decimal point

security_id,price_date,open,high,low,close,volume
RELIANCE,2024-01-01,2450.50,2475.00,2440.00,2470.25,5234567
TCS,2024-01-01,3650.00,3675.50,3640.00,3670.00,2345678
```

### Data Type Specifications

#### 1. Daily Prices
```csv
security_id,price_date,open,high,low,close,volume,turnover,source
RELIANCE,2024-01-01,2450.50,2475.00,2440.00,2470.25,5234567,12950000000,NSE
```

#### 2. Quarterly Financials
```csv
security_id,reporting_period_end,publication_date,metric_name,metric_value
RELIANCE,2023-12-31,2024-01-15,revenue,250000
RELIANCE,2023-12-31,2024-01-15,ebitda,45000
```

#### 3. FII/DII Flows
```csv
security_id,flow_date,fii_buy,fii_sell,dii_buy,dii_sell
RELIANCE,2024-01-01,1500000000,1200000000,800000000,750000000
```

#### 4. Corporate Actions
```csv
security_id,action_type,ex_date,record_date,payment_date,adjustment_factor,details
RELIANCE,SPLIT,2024-01-15,2024-01-10,2024-01-20,0.5,"1:2 stock split"
```

#### 5. Macro Data
```csv
indicator_name,indicator_date,value,source
repo_rate,2024-01-01,6.50,RBI
cpi_inflation,2024-01-01,5.20,MOSPI
```

---

## 5. Automation & Scheduling

### Cron Schedule (Linux/Mac)

```bash
# Edit crontab
crontab -e

# Add these lines:

# Daily prices - 6:30 PM IST (13:00 UTC)
30 13 * * * /usr/bin/python3 /home/user/data-collection/collect_daily_prices.py >> /var/log/price_collection.log 2>&1

# FII/DII flows - 7:00 PM IST (13:30 UTC)
0 14 * * * /usr/bin/python3 /home/user/data-collection/collect_fii_dii_flows.py >> /var/log/flows_collection.log 2>&1

# Macro data - 1st of every month at 9:00 AM IST (3:30 UTC)
30 3 1 * * /usr/bin/python3 /home/user/data-collection/collect_macro_data.py >> /var/log/macro_collection.log 2>&1
```

### Task Scheduler (Windows)

```powershell
# Create scheduled task for daily prices
$action = New-ScheduledTaskAction -Execute "python.exe" -Argument "C:\data-collection\collect_daily_prices.py"
$trigger = New-ScheduledTaskTrigger -Daily -At 6:30PM
Register-ScheduledTask -TaskName "DailyPriceCollection" -Action $action -Trigger $trigger
```

### Lambda + EventBridge (Serverless)

```yaml
# serverless.yml or SAM template
functions:
  collectDailyPrices:
    handler: collect_daily_prices.lambda_handler
    events:
      - schedule:
          rate: cron(30 13 * * ? *)  # 6:30 PM IST daily
          description: Collect daily market prices
    environment:
      S3_BUCKET: itus-data-lake
```

---

## 6. Monitoring & Alerts

### CloudWatch Metrics

```python
# Publish custom metrics from collection scripts
import boto3

cloudwatch = boto3.client('cloudwatch')

cloudwatch.put_metric_data(
    Namespace='ResearchDataPlatform/DataCollection',
    MetricData=[
        {
            'MetricName': 'RecordsCollected',
            'Value': len(df),
            'Unit': 'Count',
            'Dimensions': [
                {'Name': 'DataType', 'Value': 'prices'},
                {'Name': 'Source', 'Value': 'NSE'}
            ]
        },
        {
            'MetricName': 'CollectionDuration',
            'Value': duration_seconds,
            'Unit': 'Seconds'
        }
    ]
)
```

### SNS Alerts

```python
# Send alert on collection failure
sns = boto3.client('sns')

sns.publish(
    TopicArn='arn:aws:sns:us-east-1:123456789012:data-collection-alerts',
    Subject='Data Collection Failed',
    Message=f'Failed to collect {data_type} data: {error_message}'
)
```

### Monitoring Dashboard

Create CloudWatch dashboard to monitor:
- Files uploaded per day
- Collection success rate
- Data volume trends
- Processing latency
- Error rates

---

## Summary

**Data Flow:**
```
Your Team's Scripts → S3 Upload → S3 Event → Lambda Validator → Glue ETL → Redshift
```

**Key Points:**
1. ✅ All data sources controlled by your team
2. ✅ S3 is the handoff point for automatic processing
3. ✅ Multiple collection methods (automated, manual, serverless)
4. ✅ Standard file formats ensure consistency
5. ✅ Comprehensive monitoring and alerting

**Next Steps:**
1. Set up `data-collection/` folder with scripts
2. Configure AWS credentials
3. Test each script manually
4. Set up automation (cron/Task Scheduler/Lambda)
5. Monitor CloudWatch for processing status
