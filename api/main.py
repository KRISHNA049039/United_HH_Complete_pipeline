"""
FastAPI Query Service for Research Data Platform V2
Provides REST API endpoints for querying Redshift with validation and caching
"""

from fastapi import FastAPI, HTTPException, Query, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
import psycopg2
from psycopg2.extras import RealDictCursor
import redis
import json
import hashlib
from datetime import datetime, date
import os
from contextlib import contextmanager
from temporal_validator import validate_query, ValidationResult
from performance_estimator import estimate_query_performance, PerformanceEstimate

# Initialize FastAPI app
app = FastAPI(
    title="Research Data Platform API",
    description="Query API for equity research data with point-in-time correctness",
    version="2.0.0"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Configuration from environment variables
REDSHIFT_HOST = os.getenv("REDSHIFT_HOST")
REDSHIFT_PORT = int(os.getenv("REDSHIFT_PORT", "5439"))
REDSHIFT_DB = os.getenv("REDSHIFT_DB", "research_platform")
REDSHIFT_USER = os.getenv("REDSHIFT_USER")
REDSHIFT_PASSWORD = os.getenv("REDSHIFT_PASSWORD")
REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
CACHE_TTL = int(os.getenv("CACHE_TTL", "86400"))  # 24 hours

# Redis client for caching
redis_client = redis.Redis(
    host=REDIS_HOST,
    port=REDIS_PORT,
    decode_responses=True
)

# =====================================================
# Database Connection Pool
# =====================================================

@contextmanager
def get_db_connection():
    """Get database connection with automatic cleanup"""
    conn = psycopg2.connect(
        host=REDSHIFT_HOST,
        port=REDSHIFT_PORT,
        database=REDSHIFT_DB,
        user=REDSHIFT_USER,
        password=REDSHIFT_PASSWORD,
        connect_timeout=10
    )
    try:
        yield conn
    finally:
        conn.close()

# =====================================================
# Request/Response Models
# =====================================================

class QueryRequest(BaseModel):
    query: str = Field(..., description="SQL query to execute")
    as_of_date: Optional[date] = Field(None, description="Point-in-time date for temporal queries")
    cache_enabled: bool = Field(True, description="Enable query result caching")
    timeout_seconds: int = Field(60, description="Query timeout in seconds", ge=1, le=300)
    skip_validation: bool = Field(False, description="Skip temporal validation (use with caution)")

class QueryValidationRequest(BaseModel):
    query: str = Field(..., description="SQL query to validate")
    as_of_date: Optional[date] = Field(None, description="Point-in-time date for temporal queries")

class QueryValidationResponse(BaseModel):
    is_valid: bool
    errors: List[str]
    warnings: List[str]
    suggestions: List[str]

class QueryEstimateRequest(BaseModel):
    query: str = Field(..., description="SQL query to estimate")

class QueryEstimateResponse(BaseModel):
    estimated_rows: int
    estimated_cost_usd: float
    should_reject: bool
    warnings: List[str]
    suggestions: List[str]

class NLQueryRequest(BaseModel):
    natural_language_query: str = Field(..., description="Natural language query")
    as_of_date: Optional[date] = Field(None, description="Point-in-time date for temporal queries")
    execute: bool = Field(False, description="Execute the generated SQL immediately")

class NLQueryResponse(BaseModel):
    natural_language_query: str
    generated_sql: str
    validation_result: Optional[Dict[str, Any]] = None
    performance_estimate: Optional[Dict[str, Any]] = None
    execution_result: Optional[Dict[str, Any]] = None

class QueryResponse(BaseModel):
    data: List[Dict[str, Any]]
    row_count: int
    execution_time_ms: int
    cached: bool = False
    query_id: Optional[str] = None

class IndexConstituentsRequest(BaseModel):
    index_name: str = Field(..., description="Index name (e.g., NIFTY50, NIFTY500)")
    as_of_date: Optional[date] = Field(None, description="Date to query constituents")

class FinancialMetricRequest(BaseModel):
    security_id: str = Field(..., description="Security identifier")
    metric_name: str = Field(..., description="Financial metric name (e.g., revenue, ebitda)")
    start_date: date
    end_date: date
    as_of_date: Optional[date] = Field(None, description="Point-in-time date")

class StockScreenRequest(BaseModel):
    min_market_cap: Optional[float] = None
    max_market_cap: Optional[float] = None
    min_roe: Optional[float] = None
    min_revenue_growth: Optional[float] = None
    min_return_6m: Optional[float] = None
    sectors: Optional[List[str]] = None

# =====================================================
# Utility Functions
# =====================================================

def generate_cache_key(query: str, params: Dict = None) -> str:
    """Generate cache key from query and parameters"""
    cache_data = {"query": query, "params": params or {}}
    cache_str = json.dumps(cache_data, sort_keys=True, default=str)
    return f"query:{hashlib.md5(cache_str.encode()).hexdigest()}"

def get_cached_result(cache_key: str) -> Optional[Dict]:
    """Get cached query result"""
    try:
        cached = redis_client.get(cache_key)
        if cached:
            return json.loads(cached)
    except Exception as e:
        print(f"Cache read error: {e}")
    return None

def set_cached_result(cache_key: str, result: Dict, ttl: int = CACHE_TTL):
    """Cache query result"""
    try:
        redis_client.setex(
            cache_key,
            ttl,
            json.dumps(result, default=str)
        )
    except Exception as e:
        print(f"Cache write error: {e}")

def execute_query(query: str, params: tuple = None, timeout: int = 60) -> List[Dict]:
    """Execute SQL query with timeout"""
    with get_db_connection() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            # Set statement timeout
            cur.execute(f"SET statement_timeout = {timeout * 1000}")
            
            # Execute query
            if params:
                cur.execute(query, params)
            else:
                cur.execute(query)
            
            # Fetch results
            results = cur.fetchall()
            return [dict(row) for row in results]

def log_query(query: str, user: str, execution_time_ms: int, status: str, error: str = None):
    """Log query execution to audit table"""
    try:
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO control.query_audit_log (
                        user_name, query_text, execution_time_ms, 
                        query_status, error_message
                    ) VALUES (%s, %s, %s, %s, %s)
                """, (user, query[:5000], execution_time_ms, status, error))
                conn.commit()
    except Exception as e:
        print(f"Query logging error: {e}")

def log_nl_translation(nl_query: str, generated_sql: str, user: str = "api_user"):
    """Log natural language query translation"""
    try:
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO control.nl_query_log (
                        user_name, nl_query, generated_sql, timestamp
                    ) VALUES (%s, %s, %s, CURRENT_TIMESTAMP)
                """, (user, nl_query[:1000], generated_sql[:5000]))
                conn.commit()
    except Exception as e:
        print(f"NL query logging error: {e}")

def translate_nl_to_sql(nl_query: str, as_of_date: Optional[date] = None) -> str:
    """
    Translate natural language query to SQL
    
    This is a simplified implementation. In production, this would use
    LangChain with an LLM and metadata context.
    
    For now, we implement pattern matching for common queries.
    """
    nl_lower = nl_query.lower()
    
    # Pattern: "show me [index] constituents"
    if 'constituents' in nl_lower or 'members' in nl_lower:
        index_match = re.search(r'(nifty\w+)', nl_lower)
        if index_match:
            index_name = index_match.group(1).upper()
            as_of = as_of_date or date.today()
            return f"""
                SELECT * FROM presentation.get_index_constituents('{index_name}', '{as_of}')
            """
    
    # Pattern: "revenue for [company]"
    if 'revenue' in nl_lower and ('for' in nl_lower or 'of' in nl_lower):
        return """
            SELECT 
                s.security_name,
                f.reporting_period_end,
                f.revenue
            FROM fact_quarterly_financials f
            JOIN dim_security s ON f.security_key = s.security_key
            WHERE s.is_current = TRUE
            ORDER BY f.reporting_period_end DESC
            LIMIT 20
        """
    
    # Pattern: "stocks with [criteria]"
    if 'stocks with' in nl_lower or 'companies with' in nl_lower:
        conditions = []
        
        if 'high roe' in nl_lower or 'roe >' in nl_lower:
            conditions.append("roe > 15")
        
        if 'positive momentum' in nl_lower or '6 month return' in nl_lower:
            conditions.append("return_6m > 0")
        
        if 'improving margin' in nl_lower:
            conditions.append("ebitda_margin > LAG(ebitda_margin, 4) OVER (PARTITION BY security_key ORDER BY reporting_period_end)")
        
        where_clause = " AND ".join(conditions) if conditions else "1=1"
        
        return f"""
            SELECT 
                s.security_id,
                s.security_name,
                s.sector,
                r.ebitda_margin,
                m.return_6m
            FROM dim_security s
            JOIN mv_precomputed_ratios r ON s.security_key = r.security_key
            JOIN mv_rolling_returns m ON s.security_key = m.security_key
            WHERE s.is_current = TRUE
              AND {where_clause}
            LIMIT 100
        """
    
    # Default: return error message
    raise ValueError(
        "Could not translate natural language query. "
        "Please try rephrasing or use direct SQL. "
        "Supported patterns: 'show me [index] constituents', 'revenue for [company]', 'stocks with [criteria]'"
    )

# =====================================================
# API Endpoints
# =====================================================

@app.get("/")
async def root():
    """API health check"""
    return {
        "service": "Research Data Platform API",
        "version": "2.0.0",
        "status": "healthy"
    }

@app.get("/health")
async def health_check():
    """Detailed health check"""
    health = {
        "api": "healthy",
        "database": "unknown",
        "cache": "unknown"
    }
    
    # Check database
    try:
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
                health["database"] = "healthy"
    except Exception as e:
        health["database"] = f"unhealthy: {str(e)}"
    
    # Check Redis
    try:
        redis_client.ping()
        health["cache"] = "healthy"
    except Exception as e:
        health["cache"] = f"unhealthy: {str(e)}"
    
    return health

@app.post("/api/v1/query/execute", response_model=QueryResponse)
async def execute_sql_query(request: QueryRequest):
    """Execute arbitrary SQL query with caching and validation"""
    
    start_time = datetime.now()
    
    # Validate query for temporal correctness
    if not request.skip_validation:
        validation_result = validate_query(request.query, request.as_of_date)
        if not validation_result.is_valid:
            raise HTTPException(
                status_code=400,
                detail={
                    "message": "Query validation failed",
                    "errors": validation_result.errors,
                    "warnings": validation_result.warnings,
                    "suggestions": validation_result.suggestions
                }
            )
        
        # Estimate query performance
        performance_estimate = estimate_query_performance(request.query)
        if performance_estimate.should_reject:
            raise HTTPException(
                status_code=400,
                detail={
                    "message": f"Query rejected: will scan {performance_estimate.estimated_rows:,} rows (limit: {100_000_000:,})",
                    "estimated_rows": performance_estimate.estimated_rows,
                    "estimated_cost_usd": performance_estimate.estimated_cost_usd,
                    "suggestions": performance_estimate.suggestions
                }
            )
    
    cache_key = generate_cache_key(request.query)
    
    # Check cache
    if request.cache_enabled:
        cached_result = get_cached_result(cache_key)
        if cached_result:
            cached_result["cached"] = True
            return cached_result
    
    try:
        # Execute query
        results = execute_query(request.query, timeout=request.timeout_seconds)
        
        # Calculate execution time
        execution_time_ms = int((datetime.now() - start_time).total_seconds() * 1000)
        
        # Prepare response
        response = {
            "data": results,
            "row_count": len(results),
            "execution_time_ms": execution_time_ms,
            "cached": False,
            "query_id": cache_key
        }
        
        # Cache result
        if request.cache_enabled:
            set_cached_result(cache_key, response)
        
        # Log query
        log_query(request.query, "api_user", execution_time_ms, "SUCCESS")
        
        return response
        
    except Exception as e:
        execution_time_ms = int((datetime.now() - start_time).total_seconds() * 1000)
        log_query(request.query, "api_user", execution_time_ms, "FAILED", str(e))
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/v1/index/constituents")
async def get_index_constituents(request: IndexConstituentsRequest):
    """Get index constituents as of a specific date"""
    
    as_of_date = request.as_of_date or date.today()
    
    query = """
        SELECT * FROM presentation.get_index_constituents(%s, %s)
    """
    
    try:
        results = execute_query(query, (request.index_name, as_of_date))
        return {
            "index_name": request.index_name,
            "as_of_date": as_of_date,
            "constituent_count": len(results),
            "constituents": results
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/v1/query/validate", response_model=QueryValidationResponse)
async def validate_sql_query(request: QueryValidationRequest):
    """Validate SQL query for temporal correctness without executing it"""
    
    validation_result = validate_query(request.query, request.as_of_date)
    
    return QueryValidationResponse(
        is_valid=validation_result.is_valid,
        errors=validation_result.errors,
        warnings=validation_result.warnings,
        suggestions=validation_result.suggestions
    )

@app.post("/api/v1/query/estimate", response_model=QueryEstimateResponse)
async def estimate_sql_query(request: QueryEstimateRequest):
    """Estimate query performance and cost without executing it"""
    
    performance_estimate = estimate_query_performance(request.query)
    
    return QueryEstimateResponse(
        estimated_rows=performance_estimate.estimated_rows,
        estimated_cost_usd=performance_estimate.estimated_cost_usd,
        should_reject=performance_estimate.should_reject,
        warnings=performance_estimate.warnings,
        suggestions=performance_estimate.suggestions
    )

@app.post("/api/v1/nl/translate", response_model=NLQueryResponse)
async def translate_natural_language_query(request: NLQueryRequest):
    """
    Translate natural language query to SQL
    
    Returns generated SQL for user review. Optionally executes if requested.
    """
    
    try:
        # Translate NL to SQL
        generated_sql = translate_nl_to_sql(request.natural_language_query, request.as_of_date)
        
        # Validate the generated SQL
        validation_result = validate_query(generated_sql, request.as_of_date)
        
        # Estimate performance
        performance_estimate = estimate_query_performance(generated_sql)
        
        # Log the translation
        log_nl_translation(request.natural_language_query, generated_sql)
        
        response_data = {
            "natural_language_query": request.natural_language_query,
            "generated_sql": generated_sql.strip(),
            "validation_result": {
                "is_valid": validation_result.is_valid,
                "errors": validation_result.errors,
                "warnings": validation_result.warnings,
                "suggestions": validation_result.suggestions
            },
            "performance_estimate": {
                "estimated_rows": performance_estimate.estimated_rows,
                "estimated_cost_usd": performance_estimate.estimated_cost_usd,
                "should_reject": performance_estimate.should_reject,
                "warnings": performance_estimate.warnings,
                "suggestions": performance_estimate.suggestions
            }
        }
        
        # Execute if requested and validation passed
        if request.execute:
            if not validation_result.is_valid:
                raise HTTPException(
                    status_code=400,
                    detail="Cannot execute query: validation failed"
                )
            
            if performance_estimate.should_reject:
                raise HTTPException(
                    status_code=400,
                    detail="Cannot execute query: estimated cost too high"
                )
            
            # Execute the query
            start_time = datetime.now()
            results = execute_query(generated_sql, timeout=60)
            execution_time_ms = int((datetime.now() - start_time).total_seconds() * 1000)
            
            response_data["execution_result"] = {
                "data": results,
                "row_count": len(results),
                "execution_time_ms": execution_time_ms
            }
            
            log_query(generated_sql, "nl_api_user", execution_time_ms, "SUCCESS")
        
        return response_data
        
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/v1/financial/metric-series")
async def get_financial_metric_series(request: FinancialMetricRequest):
    """Get time series of a financial metric"""
    
    as_of_date = request.as_of_date or date.today()
    
    query = """
        SELECT * FROM presentation.get_financial_metric_series(
            %s, %s, %s, %s, %s
        )
    """
    
    try:
        results = execute_query(
            query,
            (request.security_id, request.metric_name, 
             request.start_date, request.end_date, as_of_date)
        )
        return {
            "security_id": request.security_id,
            "metric_name": request.metric_name,
            "data_points": len(results),
            "data": results
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/v1/financial/cagr")
async def calculate_revenue_cagr(
    security_id: str = Query(..., description="Security identifier"),
    years: int = Query(10, description="Number of years for CAGR calculation"),
    as_of_date: Optional[date] = Query(None, description="Point-in-time date")
):
    """Calculate revenue CAGR"""
    
    as_of = as_of_date or date.today()
    
    query = """
        SELECT presentation.calculate_revenue_cagr(%s, %s, %s) AS cagr
    """
    
    try:
        results = execute_query(query, (security_id, years, as_of))
        return {
            "security_id": security_id,
            "years": years,
            "as_of_date": as_of,
            "cagr_pct": results[0]["cagr"] if results else None
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/v1/stocks/screen")
async def screen_stocks(request: StockScreenRequest):
    """Screen stocks based on multiple criteria"""
    
    query = """
        SELECT * FROM presentation.get_stocks_with_criteria(
            %s, %s, %s, %s, %s, %s
        )
        LIMIT 100
    """
    
    sectors_str = ','.join(request.sectors) if request.sectors else None
    
    try:
        results = execute_query(
            query,
            (request.min_market_cap, request.max_market_cap,
             request.min_roe, request.min_revenue_growth,
             request.min_return_6m, sectors_str)
        )
        return {
            "criteria": request.dict(exclude_none=True),
            "result_count": len(results),
            "stocks": results
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/v1/metadata/schema")
async def get_schema_metadata():
    """Get database schema metadata"""
    
    query = """
        SELECT 
            schemaname,
            tablename,
            'table' AS object_type
        FROM pg_tables
        WHERE schemaname IN ('presentation', 'integration')
        UNION ALL
        SELECT 
            schemaname,
            viewname AS tablename,
            'view' AS object_type
        FROM pg_views
        WHERE schemaname IN ('presentation', 'integration')
        ORDER BY schemaname, tablename
    """
    
    try:
        results = execute_query(query)
        return {
            "schemas": results
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/v1/cache/invalidate")
async def invalidate_cache(pattern: str = Query("*", description="Cache key pattern")):
    """Invalidate cached query results"""
    
    try:
        keys = redis_client.keys(f"query:{pattern}")
        if keys:
            redis_client.delete(*keys)
        return {
            "invalidated_count": len(keys),
            "pattern": pattern
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# =====================================================
# Run Application
# =====================================================

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
