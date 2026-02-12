# FastAPI Query Service

REST API for the Research Data Platform V2, providing secure access to Redshift data with caching and validation.

## Features

- **Query Execution**: Execute SQL queries with timeout and validation
- **Point-in-Time Queries**: Built-in support for temporal correctness
- **Result Caching**: Redis-based caching with 24-hour TTL
- **Query Abstraction**: High-level endpoints for common patterns
- **Audit Logging**: All queries logged to control.query_audit_log
- **Health Checks**: Database and cache health monitoring

## API Endpoints

### Core Endpoints

#### POST /api/v1/query/execute
Execute arbitrary SQL query with caching.

**Request**:
```json
{
  "query": "SELECT * FROM presentation.fact_daily_prices LIMIT 10",
  "as_of_date": "2024-01-15",
  "cache_enabled": true,
  "timeout_seconds": 60
}
```

**Response**:
```json
{
  "data": [...],
  "row_count": 10,
  "execution_time_ms": 234,
  "cached": false,
  "query_id": "abc123..."
}
```

#### POST /api/v1/index/constituents
Get index constituents as of a specific date.

**Request**:
```json
{
  "index_name": "NIFTY50",
  "as_of_date": "2024-01-01"
}
```

#### POST /api/v1/financial/metric-series
Get time series of a financial metric.

**Request**:
```json
{
  "security_id": "RELIANCE",
  "metric_name": "revenue",
  "start_date": "2020-01-01",
  "end_date": "2023-12-31",
  "as_of_date": "2024-01-01"
}
```

#### GET /api/v1/financial/cagr
Calculate revenue CAGR.

**Query Parameters**:
- `security_id`: Security identifier
- `years`: Number of years (default: 10)
- `as_of_date`: Point-in-time date (optional)

#### POST /api/v1/stocks/screen
Screen stocks based on criteria.

**Request**:
```json
{
  "min_roe": 15.0,
  "min_revenue_growth": 10.0,
  "min_return_6m": 5.0,
  "sectors": ["Technology", "Financial Services"]
}
```

### Utility Endpoints

#### GET /health
Health check for API, database, and cache.

#### GET /api/v1/metadata/schema
Get database schema metadata.

#### POST /api/v1/cache/invalidate
Invalidate cached query results.

## Local Development

### Prerequisites

- Python 3.11+
- Redis server
- Access to Redshift cluster

### Setup

```bash
# Install dependencies
pip install -r requirements.txt

# Copy environment file
cp .env.example .env

# Edit .env with your credentials
nano .env

# Run locally
uvicorn main:app --reload --port 8000
```

### Test API

```bash
# Health check
curl http://localhost:8000/health

# Execute query
curl -X POST http://localhost:8000/api/v1/query/execute \
  -H "Content-Type: application/json" \
  -d '{
    "query": "SELECT COUNT(*) FROM presentation.dim_security",
    "cache_enabled": true
  }'
```

## Docker Deployment

### Build Image

```bash
docker build -t research-platform-api .
```

### Run Container

```bash
docker run -d \
  -p 8000:8000 \
  --env-file .env \
  --name query-api \
  research-platform-api
```

## AWS ECS Deployment

### Prerequisites

1. AWS CLI configured
2. Docker installed
3. ECS task execution role created
4. Secrets Manager configured with Redshift credentials

### Deploy

```bash
chmod +x deploy.sh
./deploy.sh
```

This will:
1. Create ECR repository
2. Build and push Docker image
3. Create ECS cluster
4. Register task definition
5. Create/update ECS service

### Configuration

Update `deploy.sh` with:
- VPC subnet IDs
- Security group IDs
- Secrets Manager ARNs

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| REDSHIFT_HOST | Redshift cluster endpoint | Required |
| REDSHIFT_PORT | Redshift port | 5439 |
| REDSHIFT_DB | Database name | research_platform |
| REDSHIFT_USER | Database user | Required |
| REDSHIFT_PASSWORD | Database password | Required |
| REDIS_HOST | Redis host | localhost |
| REDIS_PORT | Redis port | 6379 |
| CACHE_TTL | Cache TTL in seconds | 86400 |

## Caching Strategy

- **Cache Key**: MD5 hash of query + parameters
- **TTL**: 24 hours (configurable)
- **Invalidation**: Manual via `/api/v1/cache/invalidate`
- **Hit Rate Target**: 40-50%

## Query Timeout

- **Ad-hoc queries**: 60 seconds (default)
- **Scheduled reports**: 300 seconds (max)
- **Configurable**: Per-request timeout setting

## Security

- **Connection Pooling**: Automatic connection management
- **SQL Injection**: Parameterized queries
- **Secrets**: Stored in AWS Secrets Manager
- **Audit Logging**: All queries logged with user attribution

## Monitoring

### CloudWatch Logs

- Log Group: `/ecs/query-api`
- Includes: Request/response, errors, performance metrics

### Metrics

- Query execution time
- Cache hit rate
- Error rate
- Concurrent connections

### Alerts

Configure CloudWatch alarms for:
- High error rate (> 5%)
- Slow queries (> 5 seconds)
- Cache miss rate (> 60%)

## Performance

### Benchmarks

- Simple queries: < 100ms
- Complex queries (with MVs): 2-5 seconds
- Cache hits: < 10ms

### Optimization

1. **Use Materialized Views**: Precomputed results
2. **Enable Caching**: Reduce database load
3. **Limit Result Sets**: Use LIMIT clause
4. **Optimize Queries**: Use EXPLAIN to analyze

## Error Handling

### HTTP Status Codes

- `200`: Success
- `400`: Bad request (invalid parameters)
- `500`: Server error (query execution failed)
- `504`: Gateway timeout (query exceeded timeout)

### Error Response

```json
{
  "detail": "Error message here"
}
```

## API Documentation

Interactive API documentation available at:
- Swagger UI: `http://localhost:8000/docs`
- ReDoc: `http://localhost:8000/redoc`

## Usage Examples

### Python Client

```python
import requests

API_URL = "http://localhost:8000"

# Get NIFTY50 constituents
response = requests.post(
    f"{API_URL}/api/v1/index/constituents",
    json={
        "index_name": "NIFTY50",
        "as_of_date": "2024-01-01"
    }
)
constituents = response.json()

# Calculate revenue CAGR
response = requests.get(
    f"{API_URL}/api/v1/financial/cagr",
    params={
        "security_id": "RELIANCE",
        "years": 10
    }
)
cagr = response.json()

# Screen stocks
response = requests.post(
    f"{API_URL}/api/v1/stocks/screen",
    json={
        "min_roe": 15.0,
        "min_return_6m": 5.0,
        "sectors": ["Technology"]
    }
)
stocks = response.json()
```

### JavaScript Client

```javascript
const API_URL = "http://localhost:8000";

// Execute query
const response = await fetch(`${API_URL}/api/v1/query/execute`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    query: "SELECT * FROM presentation.mv_precomputed_ratios LIMIT 10",
    cache_enabled: true
  })
});

const data = await response.json();
console.log(data);
```

## Troubleshooting

### Connection Refused

- Check Redshift security group allows API server IP
- Verify VPC routing and NAT gateway
- Ensure Redshift cluster is available

### Slow Queries

- Check query execution plan with EXPLAIN
- Use materialized views for complex calculations
- Add appropriate indexes
- Increase timeout if needed

### Cache Issues

- Verify Redis is running: `redis-cli ping`
- Check Redis memory usage
- Clear cache if stale: POST `/api/v1/cache/invalidate`

## Cost Estimation

### ECS Fargate

- 2 tasks × 0.5 vCPU × 1 GB RAM
- ~$30-40/month

### Redis (ElastiCache)

- cache.t3.micro instance
- ~$15-20/month

### Data Transfer

- Varies by usage
- ~$10-20/month

**Total**: ~$55-80/month

## Next Steps

After deployment:
1. Configure Application Load Balancer
2. Set up SSL certificate
3. Configure Route53 DNS
4. Implement authentication (JWT)
5. Set up monitoring dashboards
6. Create client SDKs
