CREATE DATABASE IF NOT EXISTS raw_data;
CREATE DATABASE IF NOT EXISTS analytics;

-- 1. Kafka Engine Table: Connects directly to Redpanda to consume CDC events.
-- `updated_at` is carried through even though it isn't used by any dbt model,
-- because it is what lets cdc-monitor compute a real, row-level CDC freshness
-- lag (now() - max(source_updated_at)) instead of a synthetic sleep/heuristic.
-- posted_date/updated_at are declared Nullable(Int64), NOT String or DateTime.
-- `__ts_ms` is Debezium's per-event message timestamp (ms epoch), emitted by the
-- connector's ExtractNewRecordState transform (add.fields=op,ts_ms). It is used
-- as the ReplacingMergeTree version below so concurrent updates to the same row
-- resolve to the LATEST event instead of whatever write happened to land in the
-- same second (the previous `now()`-based version had second granularity and
-- could silently drop a legitimate update occurring within the same second).
CREATE TABLE IF NOT EXISTS raw_data.kafka_kiva_loans_cdc (
    id Int32,
    name Nullable(String),
    status Nullable(String),
    funded_amount Nullable(String),
    loan_amount Nullable(String),
    activity Nullable(String),
    sector Nullable(String),
    country Nullable(String),
    town Nullable(String),
    posted_date Nullable(Int64),
    updated_at Nullable(Int64),
    __op Nullable(String),
    __deleted Nullable(String),
    __ts_ms Nullable(Int64)
) ENGINE = Kafka
SETTINGS kafka_broker_list = 'redpanda:29092',
         kafka_topic_list = 'cdc.raw_data.kiva_loans',
         kafka_group_name = 'clickhouse_consumer_group',
         kafka_format = 'AvroConfluent',
         format_avro_schema_registry_url = 'http://redpanda:8081';

-- 2. Raw Table: ReplacingMergeTree handles duplicates and updates naturally in ClickHouse.
-- PARTITION BY toYYYYMM(posted_date) bounds part count to one per calendar month
-- (Kiva loan history spans years, not decades) and enables cheap partition-level
-- operations (TTL/drop/backfill) as volume grows -- see docs/design-report.md
-- for the full ClickHouse table-design rationale.
-- A 5-year TTL on posted_date keeps the warehouse bounded: loans older than that
-- are expired out of the raw table automatically, matching a micro-finance
-- analytics horizon while keeping partitions cheap to merge.
CREATE TABLE IF NOT EXISTS raw_data.kiva_loans_raw (
    id Int64,
    name String,
    status String,
    funded_amount Float64,
    loan_amount Float64,
    activity String,
    sector String,
    country String,
    town String,
    posted_date DateTime,
    source_updated_at DateTime,
    _op String,
    is_deleted UInt8,
    _version UInt64
) ENGINE = ReplacingMergeTree(_version)
PARTITION BY toYYYYMM(posted_date)
ORDER BY (id)
TTL posted_date + INTERVAL 5 YEAR;

-- 3. Materialized View: Moves data from Kafka stream into the Raw Table instantly
CREATE MATERIALIZED VIEW IF NOT EXISTS raw_data.kiva_loans_mv TO raw_data.kiva_loans_raw AS
SELECT
    toInt64(id) AS id,
    ifNull(name, '') AS name,
    ifNull(status, '') AS status,
    toFloat64OrZero(ifNull(funded_amount, '0')) AS funded_amount,
    toFloat64OrZero(ifNull(loan_amount, '0')) AS loan_amount,
    ifNull(activity, '') AS activity,
    ifNull(sector, '') AS sector,
    ifNull(country, '') AS country,
    ifNull(town, '') AS town,
    toDateTime(fromUnixTimestamp64Micro(ifNull(posted_date, 0))) AS posted_date,
    toDateTime(fromUnixTimestamp64Micro(ifNull(updated_at, 0))) AS source_updated_at,
    ifNull(__op, '') AS _op,
    if(__deleted = 'true', 1, 0) AS is_deleted,
    toUInt64(ifNull(__ts_ms, 0)) AS _version
FROM raw_data.kafka_kiva_loans_cdc;
