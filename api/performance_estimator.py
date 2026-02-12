"""
Performance Estimator for Research Data Platform
Estimates query cost and resource usage before execution
"""

import re
from typing import Dict, Optional, List
from dataclasses import dataclass

@dataclass
class PerformanceEstimate:
    """Query performance estimate"""
    estimated_rows: int
    estimated_cost_usd: float
    should_reject: bool
    warnings: List[str]
    suggestions: List[str]

class PerformanceEstimator:
    """
    Estimates query performance and cost
    
    Uses heuristics to estimate:
    - Number of rows that will be scanned
    - Query execution cost
    - Whether query should be rejected
    """
    
    # Table size estimates (approximate row counts)
    TABLE_SIZES = {
        'fact_daily_prices': 20_000_000,  # 20M rows (3000 securities * 20 years * 250 days)
        'fact_quarterly_financials': 240_000,  # 240K rows (3000 securities * 20 years * 4 quarters)
        'fact_institutional_flows': 15_000_000,  # 15M rows
        'vault_financials': 500_000,  # 500K rows with versions
        'dim_security': 5_000,  # 5K securities
        'dim_date': 10_000,  # 10K dates
        'dim_index_constituents': 50_000,  # 50K records
        'mv_precomputed_ratios': 240_000,
        'mv_rolling_returns': 20_000_000,
        'mv_current_index_constituents': 3_000
    }
    
    # Cost per million rows scanned (approximate)
    COST_PER_MILLION_ROWS = 0.005  # $0.005 per million rows
    
    # Rejection threshold
    MAX_ROWS_WITHOUT_APPROVAL = 100_000_000  # 100M rows

    
    def __init__(self):
        """Initialize performance estimator"""
        self.warnings = []
        self.suggestions = []
    
    def estimate(self, query: str) -> PerformanceEstimate:
        """
        Estimate query performance
        
        Args:
            query: SQL query to estimate
            
        Returns:
            PerformanceEstimate with cost and recommendations
        """
        self.warnings = []
        self.suggestions = []
        
        query_lower = query.lower()
        
        # Extract tables
        tables = self._extract_tables(query_lower)
        
        # Estimate rows scanned
        estimated_rows = self._estimate_rows_scanned(query_lower, tables)
        
        # Calculate cost
        estimated_cost = (estimated_rows / 1_000_000) * self.COST_PER_MILLION_ROWS
        
        # Check if should reject
        should_reject = estimated_rows > self.MAX_ROWS_WITHOUT_APPROVAL
        
        # Generate warnings and suggestions
        self._generate_recommendations(query_lower, tables, estimated_rows)
        
        return PerformanceEstimate(
            estimated_rows=estimated_rows,
            estimated_cost_usd=round(estimated_cost, 4),
            should_reject=should_reject,
            warnings=self.warnings,
            suggestions=self.suggestions
        )

    
    def _extract_tables(self, query: str) -> List[str]:
        """Extract table names from query"""
        tables = []
        
        # Pattern to match FROM and JOIN clauses
        from_pattern = r'from\s+(?:\w+\.)?(\w+)'
        join_pattern = r'join\s+(?:\w+\.)?(\w+)'
        
        # Find all FROM clauses
        for match in re.finditer(from_pattern, query):
            table_name = match.group(1)
            if table_name not in ['select', 'where', 'group', 'order', 'having']:
                tables.append(table_name)
        
        # Find all JOIN clauses
        for match in re.finditer(join_pattern, query):
            table_name = match.group(1)
            if table_name not in ['select', 'where', 'group', 'order', 'having']:
                tables.append(table_name)
        
        return list(set(tables))
    
    def _estimate_rows_scanned(self, query: str, tables: List[str]) -> int:
        """Estimate number of rows that will be scanned"""
        total_rows = 0
        
        for table in tables:
            if table in self.TABLE_SIZES:
                base_rows = self.TABLE_SIZES[table]
                
                # Apply selectivity based on WHERE clause
                selectivity = self._estimate_selectivity(query, table)
                
                estimated_table_rows = int(base_rows * selectivity)
                total_rows += estimated_table_rows
        
        return total_rows

    
    def _estimate_selectivity(self, query: str, table: str) -> float:
        """
        Estimate selectivity (fraction of rows returned) based on WHERE clause
        
        Returns value between 0.0 and 1.0
        """
        # Default: full table scan
        selectivity = 1.0
        
        # Check for date range filters (most common optimization)
        if 'where' in query:
            # Date range with BETWEEN
            if 'between' in query and any(col in query for col in ['date', 'period']):
                # Estimate based on date range
                if '1 year' in query or '12 month' in query:
                    selectivity = 0.05  # 5% of data
                elif '3 year' in query or '36 month' in query:
                    selectivity = 0.15  # 15% of data
                elif '5 year' in query or '60 month' in query:
                    selectivity = 0.25  # 25% of data
                else:
                    selectivity = 0.1  # Default 10% for date range
            
            # Single security filter
            elif 'security_key' in query and '=' in query:
                selectivity = 0.0003  # 1 out of 3000 securities
            
            # Index filter
            elif 'index_name' in query and '=' in query:
                if 'nifty50' in query:
                    selectivity = 0.017  # 50/3000
                elif 'nifty500' in query:
                    selectivity = 0.167  # 500/3000
                else:
                    selectivity = 0.05  # Default index
            
            # Sector filter
            elif 'sector' in query and '=' in query:
                selectivity = 0.1  # ~10% per sector
            
            # Multiple conditions (AND)
            and_count = query.count(' and ')
            if and_count > 0:
                # Each AND condition reduces selectivity
                selectivity = selectivity * (0.5 ** and_count)
        
        return max(selectivity, 0.0001)  # Minimum 0.01% selectivity

    
    def _generate_recommendations(self, query: str, tables: List[str], estimated_rows: int):
        """Generate performance warnings and suggestions"""
        
        # Check for full table scans on large tables
        large_tables = ['fact_daily_prices', 'fact_quarterly_financials', 'mv_rolling_returns']
        for table in tables:
            if table in large_tables:
                if 'where' not in query:
                    self.warnings.append(
                        f"Full table scan detected on large table '{table}'"
                    )
                    self.suggestions.append(
                        f"Add date range filter to {table} to reduce rows scanned"
                    )
        
        # Check if materialized view could be used
        if 'fact_quarterly_financials' in tables and any(
            metric in query for metric in ['margin', 'ratio', 'roe', 'roa']
        ):
            if 'mv_precomputed_ratios' not in tables:
                self.suggestions.append(
                    "Consider using mv_precomputed_ratios instead of calculating ratios from fact_quarterly_financials"
                )
        
        if 'fact_daily_prices' in tables and any(
            term in query for term in ['return', 'momentum', 'lag(']
        ):
            if 'mv_rolling_returns' not in tables:
                self.suggestions.append(
                    "Consider using mv_rolling_returns for precomputed returns instead of calculating from prices"
                )
        
        # Check for expensive operations
        if 'cross join' in query:
            self.warnings.append(
                "CROSS JOIN detected - this can be very expensive"
            )
        
        if estimated_rows > 10_000_000:
            self.warnings.append(
                f"Query will scan approximately {estimated_rows:,} rows"
            )
            self.suggestions.append(
                "Consider running this query during off-hours or as a scheduled batch job"
            )
        
        # Check for missing LIMIT clause on large result sets
        if 'limit' not in query and estimated_rows > 100_000:
            self.suggestions.append(
                "Add LIMIT clause to restrict result set size"
            )

def estimate_query_performance(query: str) -> PerformanceEstimate:
    """
    Convenience function to estimate query performance
    
    Args:
        query: SQL query to estimate
        
    Returns:
        PerformanceEstimate with cost and recommendations
    """
    estimator = PerformanceEstimator()
    return estimator.estimate(query)
