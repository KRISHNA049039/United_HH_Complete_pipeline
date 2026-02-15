# Natural Language Query System Design

## Objective

Design a system where analysts can query the database using natural language, with automatic translation to safe SQL that prevents look-ahead bias and controls performance.

**Example Query**: "Show me midcap stocks with improving EBITDA margins and positive 6-month momentum."

---

## Complete Architecture (100 Lines)

### System Flow
```
NL Input → Intent Parser → SQL Template → SQL Generator → Temporal Validator → Performance Estimator → Execute → Results
```

### Core Components

**1. Metadata Registry** (Deterministic Mapping)
```python
metadata = {
    'midcap': {'table': 'dim_security', 'column': 'market_cap_category', 'value': 'MIDCAP'},
    'ebitda margin': {'table': 'mv_precomputed_ratios', 'column': 'ebitda_margin'},
    '6-month momentum': {'table': 'mv_rolling_returns', 'column': 'return_6m'},
    'improving': {'condition': '{metric} > LAG({metric}, 4) OVER (...)'}
}

allowed_joins = {
    ('dim_security', 'mv_precomputed_ratios'): {'on': 'security_key', 'temporal': False},
    ('dim_security', 'fact_quarterly_financials'): {'on': 'security_key', 'temporal': True}
}
```

**2. Intent Parser** (Extract Entities)
```python
def parse(nl_query):
    # "Show me midcap stocks with improving EBITDA margins"
    return {
        'intent': 'FILTER_AND_RANK',
        'filters': ['midcap'],
        'metrics': ['ebitda margin'],
        'conditions': ['improving']
    }
```

**3. SQL Template Library** (Pre-validated Patterns)
```python
templates = {
    'FILTER_AND_RANK': """
        WITH filtered AS (
            SELECT s.security_key, s.security_id, s.security_name
            FROM dim_security s
            WHERE s.is_current = TRUE {dimension_filters}
        ),
        metrics AS ({metric_calculations})
        SELECT fs.*, m.*
        FROM filtered fs {metric_joins}
        WHERE {conditions}
        ORDER BY {sort} LIMIT {limit}
    """
}
```

**4. Safe SQL Generator** (Enforce Constraints)
```python
def generate_sql(parsed_intent, as_of_date):
    # Map entities to SQL using metadata
    dimension_filters = "AND s.market_cap_category = 'MIDCAP'"
    
    metric_calculations = """
        SELECT security_key, ebitda_margin,
        LAG(ebitda_margin, 4) OVER (...) as prev_margin
        FROM mv_precomputed_ratios
    """
    
    metric_joins = "JOIN metrics m ON fs.security_key = m.security_key"
    conditions = "m.ebitda_margin > m.prev_margin"
    
    # Fill template
    sql = templates['FILTER_AND_RANK'].format(...)
    
    # Validate before returning
    validate_temporal(sql, as_of_date)
    validate_joins(sql)
    
    return sql
```

**5. Temporal Validator** (Prevent Look-ahead Bias)
```python
def validate_temporal(sql, as_of_date):
    # Check 1: Temporal tables have date filters
    if 'fact_quarterly_financials' in sql:
        assert 'publication_date' in sql, "Must filter on publication_date"
    
    # Check 2: No future dates
    dates = extract_dates(sql)
    assert all(d <= as_of_date for d in dates), "Future date detected"
    
    # Check 3: Joins have temporal alignment
    joins = extract_joins(sql)
    for join in joins:
        if requires_temporal_alignment(join):
            assert has_temporal_condition(join), "Missing temporal condition"
```

**6. Performance Estimator** (Cost Control)
```python
def estimate_performance(sql):
    explain = get_explain_plan(sql)
    rows_scanned = estimate_rows(explain)
    execution_time = estimate_time(rows_scanned)
    
    if rows_scanned > 100_000_000:
        return {'reject': True, 'reason': 'Too many rows', 'suggestions': [...]}
    
    if execution_time > 300:
        return {'reject': True, 'reason': 'Too slow', 'suggestions': [...]}
    
    return {'reject': False, 'estimated_time': execution_time}
```

**7. Complete API Endpoint**
```python
@app.post("/api/v1/nl/query")
def nl_query(nl_text: str, as_of_date: date = None):
    # Parse intent
    parsed = parse(nl_text)
    
    # Generate SQL
    sql = generate_sql(parsed, as_of_date or date.today())
    
    # Estimate performance
    estimate = estimate_performance(sql)
    if estimate['reject']:
        return {'error': estimate['reason'], 'suggestions': estimate['suggestions']}
    
    # Execute
    results = execute_query(sql)
    
    # Explain
    explanation = explain_query(nl_text, sql, results)
    
    return {'results': results, 'sql': sql, 'explanation': explanation}
```

### Safety Guarantees

**1. Safe SQL Translation**
- Metadata registry (no LLM hallucination)
- SQL templates (pre-validated patterns)
- Entity validation (all terms must exist in metadata)

**2. Prevent Look-ahead Bias**
- Temporal validator (automatic checks)
- Allowed joins only (pre-approved)
- Materialized views (pre-validated)

**3. Performance Control**
- Cost estimation before execution
- Hard limits (100M rows, 5 min)
- Optimization suggestions

### Example Execution

Input: "Show me midcap stocks with improving EBITDA margins and positive 6-month momentum"

Generated SQL:
```sql
WITH filtered AS (
    SELECT s.security_key, s.security_id, s.security_name
    FROM dim_security s
    WHERE s.is_current = TRUE AND s.market_cap_category = 'MIDCAP'
),
metrics AS (
    SELECT r.security_key, r.ebitda_margin,
           LAG(r.ebitda_margin, 4) OVER (PARTITION BY r.security_key ORDER BY r.reporting_period_end) as prev_margin
    FROM mv_precomputed_ratios r
),
momentum AS (
    SELECT security_key, return_6m FROM mv_rolling_returns WHERE price_date = CURRENT_DATE - 1
)
SELECT f.security_id, f.security_name, m.ebitda_margin, mom.return_6m
FROM filtered f
JOIN metrics m ON f.security_key = m.security_key
JOIN momentum mom ON f.security_key = mom.security_key
WHERE m.ebitda_margin > m.prev_margin AND mom.return_6m > 0
ORDER BY mom.return_6m DESC LIMIT 50;
```

Validation: ✓ No temporal issues, ✓ Allowed joins only, ✓ Performance OK (12K rows, 2.3s)

---

## Detailed Component Design

### High-Level Flow

```
Natural Language Input
    ↓
Intent Parser & Entity Extraction
    ↓
SQL Template Selection
    ↓
SQL Generation with Metadata
    ↓
Temporal Validator (Prevent Look-ahead Bias)
    ↓
Performance Estimator (Cost Control)
    ↓
Query Execution
    ↓
Results + Explanation
```

---

## Component 1: Intent Parser & Entity Extraction

### Purpose
Parse natural language to identify query intent and extract entities (stocks, metrics, conditions)

### Design

**Input**: "Show me midcap stocks with improving EBITDA margins and positive 6-month momentum."

**Extraction Process**:
```python
class IntentParser:
    def parse(self, nl_query: str) -> ParsedIntent:
        # Step 1: Identify query type
        intent = self.classify_intent(nl_query)
        # Result: "FILTER_AND_RANK"
        
        # Step 2: Extract entities
        entities = self.extract_entities(nl_query)
        # Result: {
        #   'filters': ['midcap', 'improving EBITDA margins', 'positive 6-month momentum'],
        #   'metrics': ['EBITDA margins', '6-month momentum'],
        #   'output': 'stocks'
        # }
        
        # Step 3: Map to database concepts
        mapped = self.map_to_schema(entities)
        # Result: {
        #   'filters': [
        #     {'table': 'dim_security', 'column': 'market_cap_category', 'value': 'MIDCAP'},
        #     {'table': 'mv_precomputed_ratios', 'column': 'ebitda_margin', 'condition': 'IMPROVING'},
        #     {'table': 'mv_rolling_returns', 'column': 'return_6m', 'condition': '> 0'}
        #   ]
        # }
        
        return ParsedIntent(intent, mapped)
```

**Key Design Decisions**:

1. **Use Metadata Registry** (not LLM for mapping)

```python
# Metadata registry maps natural language terms to database schema
metadata_registry = {
    'midcap': {
        'table': 'dim_security',
        'column': 'market_cap_category',
        'value': 'MIDCAP',
        'type': 'FILTER'
    },
    'ebitda margin': {
        'table': 'mv_precomputed_ratios',
        'column': 'ebitda_margin',
        'type': 'METRIC',
        'temporal': False
    },
    '6-month momentum': {
        'table': 'mv_rolling_returns',
        'column': 'return_6m',
        'type': 'METRIC',
        'temporal': False
    },
    'improving': {
        'type': 'CONDITION',
        'sql_template': '{metric} > LAG({metric}, 4) OVER (PARTITION BY security_key ORDER BY reporting_period_end)'
    }
}
```

**Why Metadata Registry?**
- Deterministic mapping (no LLM hallucination)
- Versioned and testable
- Can be updated by data team
- Fast lookup (no API calls)

2. **Intent Classification** (can use simple rules or small ML model)
```python
intent_patterns = {
    'FILTER_AND_RANK': ['show me', 'find', 'list', 'get'],
    'AGGREGATE': ['total', 'average', 'sum', 'count'],
    'COMPARE': ['compare', 'versus', 'vs'],
    'TREND': ['trend', 'over time', 'historical']
}
```

---

## Component 2: SQL Template Selection

### Purpose
Select appropriate SQL template based on intent and entities

### Design

**Template Library**:
```python
sql_templates = {
    'FILTER_AND_RANK': """
        WITH filtered_securities AS (
            SELECT DISTINCT s.security_key, s.security_id, s.security_name
            FROM dim_security s
            WHERE s.is_current = TRUE
              {dimension_filters}
        ),
        metrics AS (
            {metric_calculations}
        )
        SELECT 
            fs.security_id,
            fs.security_name,
            {output_columns}
        FROM filtered_securities fs
        {metric_joins}
        WHERE {metric_conditions}
        ORDER BY {sort_column} DESC
        LIMIT {limit}
    """,
    
    'AGGREGATE': """
        SELECT 
            {group_by_columns},
            {aggregate_functions}
        FROM {base_table}
        WHERE {filters}
        GROUP BY {group_by_columns}
        ORDER BY {sort_column}
    """,
    
    # More templates...
}
```

**Template Selection Logic**:
```python
def select_template(parsed_intent: ParsedIntent) -> SQLTemplate:
    # Based on intent type
    template = sql_templates[parsed_intent.intent_type]
    
    # Validate required entities present
    if not template.validate_entities(parsed_intent.entities):
        raise InvalidQueryError("Missing required information")
    
    return template
```

---

## Component 3: SQL Generation with Safety Constraints

### Purpose
Generate SQL from template while enforcing safety rules

### Design

**SQL Generator with Built-in Safety**:
```python
class SafeSQLGenerator:
    def __init__(self, metadata_registry, temporal_validator):
        self.metadata = metadata_registry
        self.temporal_validator = temporal_validator
    
    def generate(self, template: SQLTemplate, parsed_intent: ParsedIntent, 
                 as_of_date: date = None) -> GeneratedSQL:
        
        # Step 1: Build dimension filters
        dimension_filters = self._build_dimension_filters(
            parsed_intent.filters
        )
        
        # Step 2: Build metric calculations with temporal safety
        metric_calculations = self._build_metric_calculations(
            parsed_intent.metrics,
            as_of_date
        )
        
        # Step 3: Build joins (only allowed joins from metadata)
        metric_joins = self._build_safe_joins(
            parsed_intent.metrics
        )
        
        # Step 4: Build conditions
        metric_conditions = self._build_conditions(
            parsed_intent.conditions
        )
        
        # Step 5: Fill template
        sql = template.format(
            dimension_filters=dimension_filters,
            metric_calculations=metric_calculations,
            metric_joins=metric_joins,
            metric_conditions=metric_conditions,
            output_columns=self._build_output_columns(parsed_intent.metrics),
            sort_column=self._determine_sort(parsed_intent),
            limit=self._determine_limit(parsed_intent)
        )
        
        # Step 6: Validate generated SQL
        validation = self.temporal_validator.validate(sql, as_of_date)
        if not validation.is_valid:
            raise TemporalValidationError(validation.errors)
        
        return GeneratedSQL(sql, validation)
```

**Example Generation for Our Query**:

Input: "Show me midcap stocks with improving EBITDA margins and positive 6-month momentum."

Generated SQL:
```sql
WITH filtered_securities AS (
    SELECT DISTINCT s.security_key, s.security_id, s.security_name
    FROM dim_security s
    WHERE s.is_current = TRUE
      AND s.market_cap_category = 'MIDCAP'
),
current_metrics AS (
    SELECT 
        r.security_key,
        r.ebitda_margin as current_ebitda_margin,
        LAG(r.ebitda_margin, 4) OVER (
            PARTITION BY r.security_key 
            ORDER BY r.reporting_period_end
        ) as prev_ebitda_margin,
        r.reporting_period_end
    FROM mv_precomputed_ratios r
    WHERE r.reporting_period_end = (
        SELECT MAX(reporting_period_end) 
        FROM mv_precomputed_ratios 
        WHERE security_key = r.security_key
    )
),
momentum_metrics AS (
    SELECT 
        m.security_key,
        m.return_6m
    FROM mv_rolling_returns m
    WHERE m.price_date = CURRENT_DATE - 1
)
SELECT 
    fs.security_id,
    fs.security_name,
    cm.current_ebitda_margin,
    cm.prev_ebitda_margin,
    mm.return_6m
FROM filtered_securities fs
JOIN current_metrics cm ON fs.security_key = cm.security_key
JOIN momentum_metrics mm ON fs.security_key = mm.security_key
WHERE cm.current_ebitda_margin > cm.prev_ebitda_margin
  AND mm.return_6m > 0
ORDER BY mm.return_6m DESC
LIMIT 50;
```

---

## Component 4: Temporal Validator Integration

### Purpose
Ensure generated SQL maintains point-in-time correctness

### Design

**Validation Rules Applied**:

1. **Temporal Table Check**
```python
def validate_temporal_tables(sql: str, as_of_date: date) -> List[str]:
    errors = []
    
    # Check if temporal tables have proper filters
    temporal_tables = ['fact_quarterly_financials', 'vault_financials']
    
    for table in temporal_tables:
        if table in sql:
            if 'publication_date' not in sql:
                errors.append(
                    f"Temporal table '{table}' must include publication_date filter"
                )
    
    return errors
```

2. **Join Validation**
```python
def validate_joins(sql: str) -> List[str]:
    errors = []
    
    # Parse SQL to extract joins
    joins = self._extract_joins(sql)
    
    for join in joins:
        # Check if join is in allowed list
        if not self._is_allowed_join(join.left_table, join.right_table):
            errors.append(
                f"Join between {join.left_table} and {join.right_table} not allowed"
            )
        
        # Check temporal alignment
        if self._requires_temporal_alignment(join):
            if not self._has_temporal_condition(join):
                errors.append(
                    f"Join requires temporal alignment condition"
                )
    
    return errors
```

3. **Allowed Joins Registry**
```python
# Only allow pre-approved joins
allowed_joins = {
    ('dim_security', 'fact_daily_prices'): {
        'condition': 'security_key',
        'temporal_required': False
    },
    ('dim_security', 'fact_quarterly_financials'): {
        'condition': 'security_key',
        'temporal_required': True,
        'temporal_condition': 'f.publication_date <= {as_of_date}'
    },
    ('fact_daily_prices', 'mv_rolling_returns'): {
        'condition': 'security_key AND price_date',
        'temporal_required': False
    }
}
```

**Why This Prevents Look-ahead Bias**:
- All joins must be pre-approved
- Temporal joins require explicit date conditions
- Materialized views are pre-validated for temporal correctness
- No ad-hoc joins allowed

---

## Component 5: Performance Estimator

### Purpose
Prevent expensive queries from executing

### Design

**Cost Estimation Logic**:
```python
class PerformanceEstimator:
    def estimate(self, sql: str) -> QueryEstimate:
        # Step 1: Parse query plan
        explain_plan = self._get_explain_plan(sql)
        
        # Step 2: Estimate rows scanned
        rows_scanned = self._estimate_rows_scanned(explain_plan)
        
        # Step 3: Estimate execution time
        estimated_time = self._estimate_execution_time(
            rows_scanned,
            explain_plan.complexity
        )
        
        # Step 4: Estimate cost
        estimated_cost = self._estimate_cost(
            rows_scanned,
            estimated_time
        )
        
        # Step 5: Check against limits
        if rows_scanned > self.max_rows_scanned:
            return QueryEstimate(
                should_reject=True,
                reason=f"Query will scan {rows_scanned:,} rows (limit: {self.max_rows_scanned:,})",
                suggestions=self._generate_suggestions(sql)
            )
        
        if estimated_time > self.max_execution_time:
            return QueryEstimate(
                should_reject=True,
                reason=f"Query estimated to take {estimated_time}s (limit: {self.max_execution_time}s)",
                suggestions=self._generate_suggestions(sql)
            )
        
        return QueryEstimate(
            should_reject=False,
            estimated_time=estimated_time,
            estimated_cost=estimated_cost
        )
```

**Performance Limits**:
```python
performance_limits = {
    'max_rows_scanned': 100_000_000,  # 100M rows
    'max_execution_time': 300,  # 5 minutes
    'max_result_size': 1_000_000,  # 1M rows
    'max_joins': 5,
    'max_subqueries': 3
}
```

**Optimization Suggestions**:
```python
def _generate_suggestions(self, sql: str) -> List[str]:
    suggestions = []
    
    # Check if materialized view can be used
    if 'fact_quarterly_financials' in sql:
        if self._can_use_materialized_view(sql):
            suggestions.append(
                "Use mv_precomputed_ratios instead of fact_quarterly_financials "
                "for 5-10x speedup"
            )
    
    # Check if date filter is missing
    if not self._has_date_filter(sql):
        suggestions.append(
            "Add date range filter to reduce rows scanned"
        )
    
    # Check if result limit is missing
    if not self._has_limit(sql):
        suggestions.append(
            "Add LIMIT clause to control result size"
        )
    
    return suggestions
```

---

## Component 6: Query Explanation Generator

### Purpose
Explain what the query does in natural language

### Design

**Explanation Generator**:
```python
class QueryExplainer:
    def explain(self, nl_query: str, generated_sql: str, 
                results: pd.DataFrame) -> Explanation:
        
        explanation = {
            'original_query': nl_query,
            'interpretation': self._generate_interpretation(nl_query),
            'data_sources': self._identify_data_sources(generated_sql),
            'filters_applied': self._explain_filters(generated_sql),
            'metrics_calculated': self._explain_metrics(generated_sql),
            'temporal_correctness': self._explain_temporal(generated_sql),
            'result_summary': self._summarize_results(results)
        }
        
        return Explanation(explanation)
    
    def _generate_interpretation(self, nl_query: str) -> str:
        return (
            "I interpreted your query as: Find securities classified as midcap, "
            "where the EBITDA margin in the most recent quarter is higher than "
            "4 quarters ago, and the 6-month price return is positive."
        )
    
    def _explain_temporal(self, sql: str) -> str:
        return (
            "This query uses data as of yesterday's close. "
            "Financial metrics are from the most recently published quarter. "
            "No look-ahead bias detected."
        )
```

**Example Explanation**:
```
Original Query: "Show me midcap stocks with improving EBITDA margins and positive 6-month momentum."

Interpretation:
I found 23 midcap stocks where:
- EBITDA margin improved from Q4 2023 to Q1 2024
- 6-month price return (as of yesterday) is positive

Data Sources:
- dim_security: For midcap classification
- mv_precomputed_ratios: For EBITDA margins
- mv_rolling_returns: For 6-month returns

Temporal Correctness:
✓ Using most recent published financials (Q1 2024, published May 15)
✓ Using yesterday's closing prices
✓ No look-ahead bias detected

Performance:
- Rows scanned: 12,450
- Execution time: 2.3 seconds
- Cost: $0.02
```

---

## Complete System Integration

### API Endpoint Design

```python
@app.post("/api/v1/nl/query")
async def natural_language_query(request: NLQueryRequest):
    """
    Execute natural language query with safety checks
    """
    
    # Step 1: Parse intent
    parser = IntentParser(metadata_registry)
    parsed_intent = parser.parse(request.nl_query)
    
    # Step 2: Select template
    template = select_template(parsed_intent)
    
    # Step 3: Generate SQL
    generator = SafeSQLGenerator(metadata_registry, temporal_validator)
    generated_sql = generator.generate(
        template, 
        parsed_intent,
        as_of_date=request.as_of_date or date.today()
    )
    
    # Step 4: Estimate performance
    estimator = PerformanceEstimator()
    estimate = estimator.estimate(generated_sql.sql)
    
    if estimate.should_reject:
        return {
            'status': 'REJECTED',
            'reason': estimate.reason,
            'suggestions': estimate.suggestions
        }
    
    # Step 5: Execute query
    results = execute_query(generated_sql.sql)
    
    # Step 6: Generate explanation
    explainer = QueryExplainer()
    explanation = explainer.explain(
        request.nl_query,
        generated_sql.sql,
        results
    )
    
    # Step 7: Return results with explanation
    return {
        'status': 'SUCCESS',
        'results': results.to_dict('records'),
        'generated_sql': generated_sql.sql,
        'explanation': explanation,
        'performance': {
            'execution_time': estimate.estimated_time,
            'rows_scanned': estimate.rows_scanned,
            'cost': estimate.estimated_cost
        }
    }
```

---

## Safety Mechanisms Summary

### 1. Prevent Invalid Joins

**Mechanism**: Allowed Joins Registry
```python
# Only pre-approved joins allowed
if join not in allowed_joins:
    raise InvalidJoinError("Join not allowed")
```

**Why Safe**:
- No ad-hoc joins
- All joins reviewed by data architect
- Temporal requirements enforced

### 2. Prevent Look-ahead Bias

**Mechanism**: Temporal Validator + Metadata
```python
# All temporal tables must have date filters
if is_temporal_table(table) and not has_date_filter(sql):
    raise TemporalValidationError()
```

**Why Safe**:
- Automatic temporal validation
- Materialized views pre-validated
- as_of_date parameter required

### 3. Control Query Performance

**Mechanism**: Performance Estimator
```python
# Reject expensive queries
if rows_scanned > max_rows_scanned:
    raise PerformanceError("Query too expensive")
```

**Why Safe**:
- Cost estimation before execution
- Hard limits on rows scanned
- Suggestions for optimization

---

## Metadata Registry Design

### Schema

```python
metadata_schema = {
    'terms': {
        'term_id': 'unique identifier',
        'natural_language': 'midcap',
        'synonyms': ['mid cap', 'medium cap', 'mid-cap'],
        'table': 'dim_security',
        'column': 'market_cap_category',
        'value': 'MIDCAP',
        'type': 'FILTER | METRIC | CONDITION',
        'temporal': True/False,
        'description': 'Securities with market cap between $2B and $10B'
    },
    'allowed_joins': {
        'join_id': 'unique identifier',
        'left_table': 'dim_security',
        'right_table': 'fact_daily_prices',
        'join_condition': 'security_key',
        'temporal_required': False,
        'temporal_condition': None,
        'approved_by': 'data_architect',
        'approved_date': '2024-01-15'
    },
    'query_templates': {
        'template_id': 'unique identifier',
        'intent_type': 'FILTER_AND_RANK',
        'sql_template': '...',
        'required_entities': ['filters', 'metrics'],
        'optional_entities': ['sort', 'limit']
    }
}
```

### Management

```python
class MetadataRegistry:
    def add_term(self, term: Term):
        """Add new natural language term"""
        # Validate term
        # Check for conflicts
        # Store in database
        pass
    
    def add_allowed_join(self, join: AllowedJoin):
        """Add new allowed join (requires approval)"""
        # Validate join
        # Check temporal requirements
        # Require architect approval
        pass
    
    def update_template(self, template: QueryTemplate):
        """Update query template"""
        # Validate template
        # Test with sample queries
        # Version control
        pass
```

---

## Testing Strategy

### 1. Unit Tests

```python
def test_intent_parser():
    parser = IntentParser(metadata_registry)
    
    # Test entity extraction
    result = parser.parse("Show me midcap stocks")
    assert result.filters == [{'market_cap_category': 'MIDCAP'}]
    
    # Test synonym handling
    result = parser.parse("Show me mid cap stocks")
    assert result.filters == [{'market_cap_category': 'MIDCAP'}]
```

### 2. Integration Tests

```python
def test_end_to_end_query():
    nl_query = "Show me midcap stocks with improving EBITDA margins"
    
    # Generate SQL
    sql = nl_to_sql(nl_query)
    
    # Validate temporal correctness
    validation = temporal_validator.validate(sql)
    assert validation.is_valid
    
    # Execute query
    results = execute_query(sql)
    assert len(results) > 0
```

### 3. Temporal Correctness Tests

```python
def test_no_look_ahead_bias():
    # Query with as_of_date in past
    nl_query = "Show me stocks with high P/E ratios"
    as_of_date = date(2020, 1, 1)
    
    sql = nl_to_sql(nl_query, as_of_date)
    
    # Verify no data after as_of_date is used
    assert 'publication_date <= 2020-01-01' in sql
```

### 4. Performance Tests

```python
def test_performance_limits():
    # Query that would scan too many rows
    nl_query = "Show me all stocks for all dates"
    
    with pytest.raises(PerformanceError):
        nl_to_sql(nl_query)
```

---

## Monitoring and Improvement

### Metrics to Track

```python
nl_query_metrics = {
    'success_rate': 0.85,  # 85% of queries succeed
    'avg_execution_time': 3.2,  # seconds
    'temporal_validation_failures': 0.02,  # 2% fail temporal check
    'performance_rejections': 0.05,  # 5% rejected for performance
    'user_satisfaction': 4.2  # out of 5
}
```

### Feedback Loop

```python
@app.post("/api/v1/nl/feedback")
async def submit_feedback(feedback: NLQueryFeedback):
    """
    Collect feedback to improve system
    """
    # Store feedback
    store_feedback(feedback)
    
    # If query failed, analyze why
    if feedback.success == False:
        analyze_failure(feedback.nl_query, feedback.error)
    
    # If query succeeded but result was wrong
    if feedback.result_correct == False:
        flag_for_review(feedback.nl_query, feedback.generated_sql)
```

---

## Summary

### Key Design Principles

1. **Safety First**: Multiple validation layers prevent invalid queries
2. **Deterministic**: Metadata registry ensures consistent mapping
3. **Transparent**: Always show generated SQL and explanation
4. **Controllable**: Performance limits prevent expensive queries
5. **Improvable**: Feedback loop enables continuous improvement

### How It Addresses Requirements

**1. Natural Language → Safe SQL**
- Metadata registry maps terms to schema
- SQL templates ensure correct structure
- Validation before execution

**2. Prevent Invalid Joins & Look-ahead Bias**
- Allowed joins registry (pre-approved only)
- Temporal validator checks all queries
- Materialized views pre-validated

**3. Control Query Performance**
- Performance estimator before execution
- Hard limits on rows scanned
- Optimization suggestions

### Implementation Phases

**Phase 1** (MVP): 
- Metadata registry
- 5 query templates
- Basic intent parser
- Temporal validator integration

**Phase 2** (Enhancement):
- More templates (10+)
- Synonym handling
- Query explanation
- Feedback loop

**Phase 3** (Advanced):
- LLM integration for complex queries
- Auto-suggest queries
- Query optimization
- Personalized templates

---

**Document Version**: 1.0
**Last Updated**: 2024-01-15
**Status**: Design Proposal
