"""
Temporal Validator for Research Data Platform
Ensures queries maintain point-in-time correctness and prevent look-ahead bias
"""

import re
from typing import List, Dict, Optional, Tuple
from datetime import date
from dataclasses import dataclass

@dataclass
class ValidationResult:
    """Result of temporal validation"""
    is_valid: bool
    errors: List[str]
    warnings: List[str]
    suggestions: List[str]

class TemporalValidator:
    """
    Validates SQL queries for temporal correctness
    
    Validation Rules:
    1. Temporal tables must include as_of_date or publication_date filters
    2. Joins between tables with different temporal granularities must align
    3. No future-dated data can be referenced relative to analysis date
    4. Window functions must not look forward in time
    """
    
    # Tables that require temporal filtering
    TEMPORAL_TABLES = {
        'fact_quarterly_financials': {
            'temporal_columns': ['publication_date', 'as_of_date'],
            'granularity': 'quarterly'
        },
        'vault_financials': {
            'temporal_columns': ['publication_date', 'valid_from', 'valid_to'],
            'granularity': 'event'
        },
        'dim_security': {
            'temporal_columns': ['valid_from', 'valid_to'],
            'granularity': 'scd'
        },
        'dim_index_constituents': {
            'temporal_columns': ['effective_date', 'exit_date'],
            'granularity': 'event'
        }
    }

    
    def __init__(self):
        """Initialize temporal validator"""
        self.errors = []
        self.warnings = []
        self.suggestions = []
    
    def validate(self, query: str, as_of_date: Optional[date] = None) -> ValidationResult:
        """
        Validate query for temporal correctness
        
        Args:
            query: SQL query to validate
            as_of_date: Point-in-time date for the query
            
        Returns:
            ValidationResult with errors, warnings, and suggestions
        """
        self.errors = []
        self.warnings = []
        self.suggestions = []
        
        # Normalize query
        query_lower = query.lower()
        
        # Extract table references
        tables = self._extract_tables(query_lower)
        
        # Check temporal table filtering
        self._check_temporal_filters(query_lower, tables, as_of_date)
        
        # Check join conditions
        self._check_join_conditions(query_lower, tables)
        
        # Check window functions
        self._check_window_functions(query_lower)
        
        # Check for future data references
        if as_of_date:
            self._check_future_references(query_lower, as_of_date)
        
        return ValidationResult(
            is_valid=len(self.errors) == 0,
            errors=self.errors,
            warnings=self.warnings,
            suggestions=self.suggestions
        )

    
    def _extract_tables(self, query: str) -> List[str]:
        """Extract table names from query"""
        tables = []
        
        # Pattern to match FROM and JOIN clauses
        from_pattern = r'from\s+(\w+\.)?(\w+)'
        join_pattern = r'join\s+(\w+\.)?(\w+)'
        
        # Find all FROM clauses
        for match in re.finditer(from_pattern, query):
            table_name = match.group(2)
            if table_name not in ['select', 'where', 'group', 'order', 'having']:
                tables.append(table_name)
        
        # Find all JOIN clauses
        for match in re.finditer(join_pattern, query):
            table_name = match.group(2)
            if table_name not in ['select', 'where', 'group', 'order', 'having']:
                tables.append(table_name)
        
        return list(set(tables))
    
    def _check_temporal_filters(self, query: str, tables: List[str], as_of_date: Optional[date]):
        """Check that temporal tables have appropriate date filters"""
        for table in tables:
            if table in self.TEMPORAL_TABLES:
                table_config = self.TEMPORAL_TABLES[table]
                temporal_cols = table_config['temporal_columns']
                
                # Check if any temporal column is filtered
                has_filter = False
                for col in temporal_cols:
                    if col in query:
                        has_filter = True
                        break
                
                if not has_filter:
                    self.errors.append(
                        f"Temporal table '{table}' must include a filter on one of: {', '.join(temporal_cols)}"
                    )
                    self.suggestions.append(
                        f"Add WHERE clause: {temporal_cols[0]} <= '{as_of_date or 'CURRENT_DATE'}'"
                    )

    
    def _check_join_conditions(self, query: str, tables: List[str]):
        """Check joins between temporal tables have proper alignment"""
        temporal_tables_in_query = [t for t in tables if t in self.TEMPORAL_TABLES]
        
        if len(temporal_tables_in_query) > 1:
            # Check for joins between fact_daily_prices and fact_quarterly_financials
            if 'fact_daily_prices' in tables and 'fact_quarterly_financials' in tables:
                # Check if publication_date <= price_date condition exists
                if not re.search(r'publication_date\s*<=\s*price_date', query):
                    self.errors.append(
                        "Join between fact_daily_prices and fact_quarterly_financials "
                        "must include temporal alignment"
                    )
                    self.suggestions.append(
                        "Add condition: AND f.publication_date <= p.price_date"
                    )
            
            # Check for joins with dim_index_constituents
            if 'dim_index_constituents' in tables:
                if not re.search(r'effective_date\s*<=', query) and not re.search(r'exit_date\s*>', query):
                    self.warnings.append(
                        "Join with dim_index_constituents should include effective_date and exit_date checks"
                    )
                    self.suggestions.append(
                        "Add conditions: AND ic.effective_date <= <date> AND (ic.exit_date IS NULL OR ic.exit_date > <date>)"
                    )
    
    def _check_window_functions(self, query: str):
        """Check that window functions don't look forward in time"""
        # Pattern to match LEAD function
        lead_pattern = r'lead\s*\('
        
        if re.search(lead_pattern, query):
            self.warnings.append(
                "LEAD window function detected - ensure it doesn't create look-ahead bias"
            )
            self.suggestions.append(
                "Verify that LEAD is only used for forward-looking calculations that are valid"
            )
        
        # Check for window functions with ROWS BETWEEN ... FOLLOWING
        following_pattern = r'rows\s+between.*following'
        
        if re.search(following_pattern, query):
            self.warnings.append(
                "Window function with FOLLOWING detected - may create look-ahead bias"
            )

    
    def _check_future_references(self, query: str, as_of_date: date):
        """Check that query doesn't reference future data"""
        # Pattern to match date literals
        date_pattern = r"'(\d{4}-\d{2}-\d{2})'"
        
        for match in re.finditer(date_pattern, query):
            date_str = match.group(1)
            try:
                query_date = date.fromisoformat(date_str)
                if query_date > as_of_date:
                    self.errors.append(
                        f"Query references future date '{date_str}' which is after as_of_date '{as_of_date}'"
                    )
            except ValueError:
                pass  # Invalid date format, skip
        
        # Check for CURRENT_DATE or NOW() which might reference future data
        if 'current_date' in query or 'now()' in query:
            if as_of_date and as_of_date < date.today():
                self.warnings.append(
                    f"Query uses CURRENT_DATE but as_of_date is '{as_of_date}' - may cause look-ahead bias"
                )
                self.suggestions.append(
                    f"Replace CURRENT_DATE with '{as_of_date}'"
                )

def validate_query(query: str, as_of_date: Optional[date] = None) -> ValidationResult:
    """
    Convenience function to validate a query
    
    Args:
        query: SQL query to validate
        as_of_date: Point-in-time date for the query
        
    Returns:
        ValidationResult with validation details
    """
    validator = TemporalValidator()
    return validator.validate(query, as_of_date)
