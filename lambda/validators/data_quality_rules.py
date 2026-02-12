"""
Data Quality Validation Rules for Research Data Platform
Comprehensive validation framework for all data types
"""

import pandas as pd
import numpy as np
from typing import List, Dict, Any, Optional
from dataclasses import dataclass
from datetime import datetime, date
from abc import ABC, abstractmethod

@dataclass
class ValidationResult:
    """Result of a validation rule execution"""
    rule_name: str
    status: str  # PASS, FAIL, WARNING
    message: str
    failed_count: int = 0
    total_count: int = 0
    failed_records: Optional[pd.DataFrame] = None
    timestamp: datetime = None
    
    def __post_init__(self):
        if self.timestamp is None:
            self.timestamp = datetime.now()

class DataQualityRule(ABC):
    """Base class for data quality validation rules"""
    
    def __init__(self, name: str, description: str):
        self.name = name
        self.description = description
    
    @abstractmethod
    def validate(self, df: pd.DataFrame, context: Dict[str, Any] = None) -> ValidationResult:
        """Execute validation rule on dataframe"""
        pass

# =====================================================
# Schema Validation Rules
# =====================================================

class RequiredColumnsRule(DataQualityRule):
    """Validate that required columns are present"""
    
    def __init__(self, required_columns: List[str]):
        super().__init__(
            "RequiredColumns",
            f"Check that required columns are present: {', '.join(required_columns)}"
        )
        self.required_columns = required_columns
    
    def validate(self, df: pd.DataFrame, context: Dict[str, Any] = None) -> ValidationResult:
        missing_columns = [col for col in self.required_columns if col not in df.columns]
        
        if missing_columns:
            return ValidationResult(
                rule_name=self.name,
                status="FAIL",
                message=f"Missing required columns: {', '.join(missing_columns)}",
                failed_count=len(missing_columns),
                total_count=len(self.required_columns)
            )
        
        return ValidationResult(
            rule_name=self.name,
            status="PASS",
            message="All required columns present",
            total_count=len(self.required_columns)
        )


class ColumnTypeRule(DataQualityRule):
    """Validate column data types"""
    
    def __init__(self, column_types: Dict[str, str]):
        super().__init__(
            "ColumnTypes",
            "Check that columns have expected data types"
        )
        self.column_types = column_types
    
    def validate(self, df: pd.DataFrame, context: Dict[str, Any] = None) -> ValidationResult:
        type_mismatches = []
        
        for col, expected_type in self.column_types.items():
            if col in df.columns:
                actual_type = str(df[col].dtype)
                if expected_type not in actual_type:
                    type_mismatches.append(f"{col}: expected {expected_type}, got {actual_type}")
        
        if type_mismatches:
            return ValidationResult(
                rule_name=self.name,
                status="FAIL",
                message=f"Type mismatches: {'; '.join(type_mismatches)}",
                failed_count=len(type_mismatches),
                total_count=len(self.column_types)
            )
        
        return ValidationResult(
            rule_name=self.name,
            status="PASS",
            message="All column types correct",
            total_count=len(self.column_types)
        )

class NullCheckRule(DataQualityRule):
    """Validate that required fields are non-null"""
    
    def __init__(self, non_null_columns: List[str], threshold: float = 0.0):
        super().__init__(
            "NullCheck",
            f"Check that columns have no null values: {', '.join(non_null_columns)}"
        )
        self.non_null_columns = non_null_columns
        self.threshold = threshold  # Allow some percentage of nulls
    
    def validate(self, df: pd.DataFrame, context: Dict[str, Any] = None) -> ValidationResult:
        null_violations = []
        
        for col in self.non_null_columns:
            if col in df.columns:
                null_count = df[col].isnull().sum()
                null_pct = (null_count / len(df)) * 100 if len(df) > 0 else 0
                
                if null_pct > self.threshold:
                    null_violations.append(f"{col}: {null_count} nulls ({null_pct:.2f}%)")
        
        if null_violations:
            return ValidationResult(
                rule_name=self.name,
                status="FAIL",
                message=f"Null value violations: {'; '.join(null_violations)}",
                failed_count=len(null_violations),
                total_count=len(self.non_null_columns)
            )
        
        return ValidationResult(
            rule_name=self.name,
            status="PASS",
            message="No null value violations",
            total_count=len(self.non_null_columns)
        )

class StringLengthRule(DataQualityRule):
    """Validate string column lengths"""
    
    def __init__(self, column_max_lengths: Dict[str, int]):
        super().__init__(
            "StringLength",
            "Check that string columns don't exceed max length"
        )
        self.column_max_lengths = column_max_lengths
    
    def validate(self, df: pd.DataFrame, context: Dict[str, Any] = None) -> ValidationResult:
        length_violations = []
        
        for col, max_length in self.column_max_lengths.items():
            if col in df.columns:
                too_long = df[df[col].str.len() > max_length]
                if len(too_long) > 0:
                    length_violations.append(f"{col}: {len(too_long)} records exceed {max_length} chars")
        
        if length_violations:
            return ValidationResult(
                rule_name=self.name,
                status="FAIL",
                message=f"String length violations: {'; '.join(length_violations)}",
                failed_count=len(length_violations),
                total_count=len(self.column_max_lengths)
            )
        
        return ValidationResult(
            rule_name=self.name,
            status="PASS",
            message="No string length violations",
            total_count=len(self.column_max_lengths)
        )


# =====================================================
# Referential Integrity Rules
# =====================================================

class ReferentialIntegrityRule(DataQualityRule):
    """Validate foreign key relationships"""
    
    def __init__(self, column: str, reference_values: set, reference_name: str):
        super().__init__(
            "ReferentialIntegrity",
            f"Check that {column} values exist in {reference_name}"
        )
        self.column = column
        self.reference_values = reference_values
        self.reference_name = reference_name
    
    def validate(self, df: pd.DataFrame, context: Dict[str, Any] = None) -> ValidationResult:
        if self.column not in df.columns:
            return ValidationResult(
                rule_name=self.name,
                status="FAIL",
                message=f"Column {self.column} not found",
                failed_count=1,
                total_count=1
            )
        
        invalid_refs = df[~df[self.column].isin(self.reference_values)]
        
        if len(invalid_refs) > 0:
            return ValidationResult(
                rule_name=self.name,
                status="FAIL",
                message=f"{len(invalid_refs)} records have invalid {self.column} references",
                failed_count=len(invalid_refs),
                total_count=len(df),
                failed_records=invalid_refs
            )
        
        return ValidationResult(
            rule_name=self.name,
            status="PASS",
            message=f"All {self.column} references are valid",
            total_count=len(df)
        )

# =====================================================
# Business Rules
# =====================================================

class PositiveValueRule(DataQualityRule):
    """Validate that numeric columns have positive values"""
    
    def __init__(self, columns: List[str], allow_zero: bool = False):
        super().__init__(
            "PositiveValue",
            f"Check that columns have positive values: {', '.join(columns)}"
        )
        self.columns = columns
        self.allow_zero = allow_zero
    
    def validate(self, df: pd.DataFrame, context: Dict[str, Any] = None) -> ValidationResult:
        violations = []
        
        for col in self.columns:
            if col in df.columns:
                if self.allow_zero:
                    invalid = df[df[col] < 0]
                else:
                    invalid = df[df[col] <= 0]
                
                if len(invalid) > 0:
                    violations.append(f"{col}: {len(invalid)} non-positive values")
        
        if violations:
            return ValidationResult(
                rule_name=self.name,
                status="FAIL",
                message=f"Positive value violations: {'; '.join(violations)}",
                failed_count=len(violations),
                total_count=len(self.columns)
            )
        
        return ValidationResult(
            rule_name=self.name,
            status="PASS",
            message="All values are positive",
            total_count=len(self.columns)
        )

class PriceChangeRule(DataQualityRule):
    """Validate that price changes are within reasonable bounds"""
    
    def __init__(self, price_column: str, max_change_pct: float = 50.0, 
                 security_id_column: str = 'security_id', date_column: str = 'price_date'):
        super().__init__(
            "PriceChange",
            f"Check that price changes don't exceed {max_change_pct}%"
        )
        self.price_column = price_column
        self.max_change_pct = max_change_pct
        self.security_id_column = security_id_column
        self.date_column = date_column
    
    def validate(self, df: pd.DataFrame, context: Dict[str, Any] = None) -> ValidationResult:
        if self.price_column not in df.columns:
            return ValidationResult(
                rule_name=self.name,
                status="FAIL",
                message=f"Column {self.price_column} not found",
                failed_count=1,
                total_count=1
            )
        
        # Calculate day-over-day price changes
        df_sorted = df.sort_values([self.security_id_column, self.date_column])
        df_sorted['pct_change'] = df_sorted.groupby(self.security_id_column)[self.price_column].pct_change() * 100
        
        # Find outliers
        outliers = df_sorted[abs(df_sorted['pct_change']) > self.max_change_pct]
        
        if len(outliers) > 0:
            # Check if corporate actions explain the changes (from context)
            corp_actions = context.get('corporate_actions', set()) if context else set()
            
            # Filter out explained outliers
            unexplained = outliers[~outliers[self.security_id_column].isin(corp_actions)]
            
            if len(unexplained) > 0:
                return ValidationResult(
                    rule_name=self.name,
                    status="FAIL",
                    message=f"{len(unexplained)} unexplained price changes > {self.max_change_pct}%",
                    failed_count=len(unexplained),
                    total_count=len(df),
                    failed_records=unexplained[[self.security_id_column, self.date_column, 
                                               self.price_column, 'pct_change']]
                )
        
        return ValidationResult(
            rule_name=self.name,
            status="PASS",
            message="All price changes within acceptable range",
            total_count=len(df)
        )


class BalanceSheetBalanceRule(DataQualityRule):
    """Validate that balance sheet balances (Assets = Liabilities + Equity)"""
    
    def __init__(self, assets_col: str = 'total_assets', 
                 liabilities_col: str = 'total_liabilities',
                 equity_col: str = 'total_equity',
                 tolerance_pct: float = 1.0):
        super().__init__(
            "BalanceSheetBalance",
            "Check that Assets = Liabilities + Equity"
        )
        self.assets_col = assets_col
        self.liabilities_col = liabilities_col
        self.equity_col = equity_col
        self.tolerance_pct = tolerance_pct
    
    def validate(self, df: pd.DataFrame, context: Dict[str, Any] = None) -> ValidationResult:
        required_cols = [self.assets_col, self.liabilities_col, self.equity_col]
        missing = [col for col in required_cols if col not in df.columns]
        
        if missing:
            return ValidationResult(
                rule_name=self.name,
                status="FAIL",
                message=f"Missing columns: {', '.join(missing)}",
                failed_count=len(missing),
                total_count=len(required_cols)
            )
        
        # Calculate difference
        df['balance_check'] = df[self.assets_col] - (df[self.liabilities_col] + df[self.equity_col])
        df['balance_pct_diff'] = (df['balance_check'] / df[self.assets_col].abs()) * 100
        
        # Find imbalances
        imbalanced = df[abs(df['balance_pct_diff']) > self.tolerance_pct]
        
        if len(imbalanced) > 0:
            return ValidationResult(
                rule_name=self.name,
                status="FAIL",
                message=f"{len(imbalanced)} records have balance sheet imbalances > {self.tolerance_pct}%",
                failed_count=len(imbalanced),
                total_count=len(df),
                failed_records=imbalanced
            )
        
        return ValidationResult(
            rule_name=self.name,
            status="PASS",
            message="All balance sheets balance within tolerance",
            total_count=len(df)
        )

class RangeCheckRule(DataQualityRule):
    """Validate that values are within expected ranges"""
    
    def __init__(self, column: str, min_value: float, max_value: float):
        super().__init__(
            "RangeCheck",
            f"Check that {column} is between {min_value} and {max_value}"
        )
        self.column = column
        self.min_value = min_value
        self.max_value = max_value
    
    def validate(self, df: pd.DataFrame, context: Dict[str, Any] = None) -> ValidationResult:
        if self.column not in df.columns:
            return ValidationResult(
                rule_name=self.name,
                status="FAIL",
                message=f"Column {self.column} not found",
                failed_count=1,
                total_count=1
            )
        
        out_of_range = df[(df[self.column] < self.min_value) | (df[self.column] > self.max_value)]
        
        if len(out_of_range) > 0:
            return ValidationResult(
                rule_name=self.name,
                status="FAIL",
                message=f"{len(out_of_range)} values outside range [{self.min_value}, {self.max_value}]",
                failed_count=len(out_of_range),
                total_count=len(df),
                failed_records=out_of_range
            )
        
        return ValidationResult(
            rule_name=self.name,
            status="PASS",
            message=f"All {self.column} values within range",
            total_count=len(df)
        )


# =====================================================
# Completeness Rules
# =====================================================

class RecordCountRule(DataQualityRule):
    """Validate expected number of records"""
    
    def __init__(self, expected_count: int, tolerance_pct: float = 10.0):
        super().__init__(
            "RecordCount",
            f"Check that record count is approximately {expected_count}"
        )
        self.expected_count = expected_count
        self.tolerance_pct = tolerance_pct
    
    def validate(self, df: pd.DataFrame, context: Dict[str, Any] = None) -> ValidationResult:
        actual_count = len(df)
        diff_pct = abs((actual_count - self.expected_count) / self.expected_count) * 100
        
        if diff_pct > self.tolerance_pct:
            return ValidationResult(
                rule_name=self.name,
                status="FAIL",
                message=f"Record count {actual_count} differs from expected {self.expected_count} by {diff_pct:.1f}%",
                failed_count=1,
                total_count=1
            )
        
        return ValidationResult(
            rule_name=self.name,
            status="PASS",
            message=f"Record count {actual_count} within tolerance of expected {self.expected_count}",
            total_count=1
        )

class DateGapRule(DataQualityRule):
    """Validate that there are no unexpected gaps in date sequences"""
    
    def __init__(self, date_column: str, security_id_column: str = 'security_id',
                 max_gap_days: int = 5):
        super().__init__(
            "DateGap",
            f"Check for date gaps > {max_gap_days} days"
        )
        self.date_column = date_column
        self.security_id_column = security_id_column
        self.max_gap_days = max_gap_days
    
    def validate(self, df: pd.DataFrame, context: Dict[str, Any] = None) -> ValidationResult:
        if self.date_column not in df.columns:
            return ValidationResult(
                rule_name=self.name,
                status="FAIL",
                message=f"Column {self.date_column} not found",
                failed_count=1,
                total_count=1
            )
        
        # Convert to datetime if needed
        df[self.date_column] = pd.to_datetime(df[self.date_column])
        
        # Sort by security and date
        df_sorted = df.sort_values([self.security_id_column, self.date_column])
        
        # Calculate gaps
        df_sorted['date_diff'] = df_sorted.groupby(self.security_id_column)[self.date_column].diff().dt.days
        
        # Find large gaps
        large_gaps = df_sorted[df_sorted['date_diff'] > self.max_gap_days]
        
        if len(large_gaps) > 0:
            return ValidationResult(
                rule_name=self.name,
                status="WARNING",
                message=f"{len(large_gaps)} date gaps > {self.max_gap_days} days found",
                failed_count=len(large_gaps),
                total_count=len(df),
                failed_records=large_gaps[[self.security_id_column, self.date_column, 'date_diff']]
            )
        
        return ValidationResult(
            rule_name=self.name,
            status="PASS",
            message="No significant date gaps found",
            total_count=len(df)
        )

# =====================================================
# Consistency Rules
# =====================================================

class DuplicateCheckRule(DataQualityRule):
    """Validate that there are no duplicate records"""
    
    def __init__(self, key_columns: List[str]):
        super().__init__(
            "DuplicateCheck",
            f"Check for duplicates on: {', '.join(key_columns)}"
        )
        self.key_columns = key_columns
    
    def validate(self, df: pd.DataFrame, context: Dict[str, Any] = None) -> ValidationResult:
        missing = [col for col in self.key_columns if col not in df.columns]
        
        if missing:
            return ValidationResult(
                rule_name=self.name,
                status="FAIL",
                message=f"Missing key columns: {', '.join(missing)}",
                failed_count=len(missing),
                total_count=len(self.key_columns)
            )
        
        duplicates = df[df.duplicated(subset=self.key_columns, keep=False)]
        
        if len(duplicates) > 0:
            return ValidationResult(
                rule_name=self.name,
                status="FAIL",
                message=f"{len(duplicates)} duplicate records found",
                failed_count=len(duplicates),
                total_count=len(df),
                failed_records=duplicates
            )
        
        return ValidationResult(
            rule_name=self.name,
            status="PASS",
            message="No duplicate records found",
            total_count=len(df)
        )
