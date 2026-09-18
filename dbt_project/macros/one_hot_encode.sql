{#
  one_hot_encode(column, values)

  Generates a comma-separated list of binary (0/1) one-hot encoded columns from
  a single source column. Centralizes the copy-pasted `CASE WHEN ... THEN 1
  ELSE 0 END` blocks that would otherwise be repeated once per category, so a
  category add/remove is a one-line edit in a single place.

  Acts on a row grain: each output column is 1 when the input column equals its
  configured value, 0 otherwise. Category values are emitted with standard SQL
  single quotes, which is valid across ClickHouse, Postgres, and ANSI SQL.

  Args:
    column: the source column/expression to encode (e.g. 'sector').
    values: a list of (alias, value) tuples; each tuple emits one encoded column.

  Example:
      {{ one_hot_encode('sector', [
          ('is_sector_agriculture', 'Agriculture'),
          ('is_sector_retail', 'Retail'),
      ]) }}
#}
{% macro one_hot_encode(column, values) -%}
{%- for alias, value in values %}
    CASE WHEN {{ column }} = '{{ value }}' THEN 1 ELSE 0 END AS {{ alias }}{% if not loop.last %},{% endif %}
{%- endfor %}
{%- endmacro %}