{#
  safe_ratio(numerator, denominator, decimals=2, scale=1)

  Divides two expressions behind a NULLIF guard against divide-by-zero, applies
  an optional multiplicative scale, and rounds to the requested precision.
  Centralizes the `X / NULLIF(Y, 0)` boilerplate that appears across the
  intermediate and mart layers, and prevents ClickHouse from producing the
  `inf`/`NaN` values a raw division emits when the denominator is zero.

  Args:
    numerator:   the numerator expression (e.g. 'funded_amount' or 'SUM(funded_amount)').
    denominator: the denominator expression (e.g. 'loan_amount' or 'SUM(loan_amount)').
    decimals:    rounding precision (default 2).
    scale:       optional multiplier applied inside ROUND (default 1); pass 100
                 to express the result as a percentage.

  Example:
      {{ safe_ratio('funded_amount', 'loan_amount', 2, 100) }} AS funding_percentage
#}
{% macro safe_ratio(numerator, denominator, decimals=2, scale=1) -%}
    ROUND({{ numerator }} / NULLIF({{ denominator }}, 0){% if scale != 1 %} * {{ scale }}{% endif %}, {{ decimals }})
{%- endmacro %}