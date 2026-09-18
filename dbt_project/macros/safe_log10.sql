{#
  safe_log10(column, decimals=4)

  Applies a base-10 logarithmic transformation that is safe for zero-valued
  inputs by shifting the value up by +1 before taking the log (the standard
  `log1p`-style shift used to de-skew right-tailed distributions). Used by the
  ML feature mart on the loan amount columns; centralizes the transformation so
  the shift rationale lives in exactly one place.

  Docs: https://clickhouse.com/docs/en/sql-reference/functions/math-functions#log10

  Example:
      {{ safe_log10('loan_amount') }} AS log_loan_amount
#}
{% macro safe_log10(column, decimals=4) -%}
    ROUND(log10({{ column }} + 1), {{ decimals }})
{%- endmacro %}