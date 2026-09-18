import logging
import os
from datetime import datetime, timedelta

import psycopg
import requests
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.sensors.python import PythonSensor

log = logging.getLogger("inkomoko_pipeline")

# Default arguments applied to all tasks
default_args = {
    "owner": "inkomoko",
    "depends_on_past": False,
    "email_on_failure": False,
    "email_on_retry": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=1),
}


def _postgres_count():
    """Live source-of-truth row count in the OLTP table."""
    with psycopg.connect(
        host=os.environ.get("POSTGRES_HOST", "postgres"),
        port=os.environ.get("POSTGRES_PORT", "5432"),
        dbname=os.environ.get("POSTGRES_DB"),
        user=os.environ.get("POSTGRES_USER"),
        password=os.environ.get("POSTGRES_PASSWORD"),
        connect_timeout=5,
    ) as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM raw_data.kiva_loans;")
            return cur.fetchone()[0]


def _clickhouse_count():
    """Deduplicated, non-deleted row count in the CDC target table."""
    url = f"http://{os.environ.get('CLICKHOUSE_HOST', 'clickhouse')}:{os.environ.get('CLICKHOUSE_PORT', '8123')}/"
    response = requests.get(
        url,
        params={"query": "SELECT count() FROM raw_data.kiva_loans_raw FINAL WHERE is_deleted = 0"},
        auth=(
            os.environ.get("CLICKHOUSE_USER"),
            os.environ.get("CLICKHOUSE_PASSWORD"),
        ),
        timeout=5,
    )
    response.raise_for_status()
    return int(response.text.strip()) if response.text.strip() else 0


def _cdc_caught_up() -> bool:
    """Return True once every Postgres row has replicated into ClickHouse.
    The dbt task only proceeds once the
    Debezium -> Redpanda -> ClickHouse path has actually caught up with the
    writes produced by the ingest task.
    """
    try:
        pg_count = _postgres_count()
    except Exception as exc:  # noqa: BLE001 - a failed poll is not a terminal condition
        log.warning("CDC sensor: Postgres poll failed: %s", exc)
        return False

    try:
        ch_count = _clickhouse_count()
    except Exception as exc:  # noqa: BLE001
        log.warning("CDC sensor: ClickHouse poll failed: %s", exc)
        return False

    log.info("CDC sensor: postgres=%s clickhouse=%s", pg_count, ch_count)
    if pg_count == 0:
        return True  # nothing to replicate
    return ch_count >= pg_count


# The 15-minute schedule matches the production SLA: frequent enough to keep
# Kiva loan data close to real-time without hammering the public API.
with DAG(
    dag_id="inkomoko_kiva_pipeline",
    default_args=default_args,
    description="Polls Kiva API into Postgres, awaits CDC catch-up, then executes dbt models in ClickHouse",
    schedule_interval="*/15 * * * *",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    max_active_runs=1,
    tags=["inkomoko", "cdc", "dbt", "kiva"],
) as dag:

    # Task 1: Fetch loans from Kiva API and upsert into PostgreSQL OLTP database
    ingest_task = BashOperator(
        task_id="ingest_kiva_api_to_postgres",
        bash_command="export PATH=/home/airflow/.local/bin:$PATH && python /opt/airflow/src/ingest_api.py",
        env={
            "PATH": f"/home/airflow/.local/bin:{os.environ.get('PATH', '/usr/local/bin:/usr/bin:/bin')}",
            "DB_HOST": os.environ.get("POSTGRES_HOST", "postgres"),
            "DB_PORT": os.environ.get("POSTGRES_PORT", "5432"),
            "DB_USER": os.environ.get("POSTGRES_USER"),
            "DB_PASS": os.environ.get("POSTGRES_PASSWORD"),
            "DB_NAME": os.environ.get("POSTGRES_DB"),
            "KIVA_PAGES": os.environ.get("KIVA_PAGES", "3"),
            "KIVA_PER_PAGE": os.environ.get("KIVA_PER_PAGE", "100"),
        },
    )

    # Task 2: Wait for CDC (Debezium -> Redpanda -> ClickHouse) to replicate every
    # row written by the ingestion task before running transformations.
    wait_for_cdc = PythonSensor(
        task_id="wait_for_cdc_catch_up",
        python_callable=_cdc_caught_up,
        timeout=120,
        poke_interval=5,
        mode="poke",
        doc_md=(
            "Polls Postgres and ClickHouse every 5s until every Postgres row has "
            "been replicated into the raw CDC table. Replaces the previous "
            "arbitrary `sleep 3` which could silently run dbt against stale data."
        ),
    )

    # Task 3: Execute dbt run, dbt test and dbt source freshness against
    # ClickHouse. The freshness check enforces the loaded_at thresholds declared
    # in dbt_project/models/staging/src_kiva.yml (warn 15m / error 30m) - the
    # orchestration layer's own data-freshness gate.
    dbt_task = BashOperator(
        task_id="dbt_analytics_models",
        bash_command=(
            "mkdir -p /opt/airflow/dbt_project/logs && "
            "cd /opt/airflow/dbt_project && "
            "export PATH=/home/airflow/.local/bin:$PATH && "
            "dbt run --profiles-dir . && "
            "dbt test --profiles-dir . && "
            "dbt source freshness --profiles-dir ."
        ),
        env={
            "PATH": f"/home/airflow/.local/bin:{os.environ.get('PATH', '/usr/local/bin:/usr/bin:/bin')}",
            "CLICKHOUSE_HOST": os.environ.get("CLICKHOUSE_HOST", "clickhouse"),
            "CLICKHOUSE_PORT": os.environ.get("CLICKHOUSE_PORT", "8123"),
            "CLICKHOUSE_USER": os.environ.get("CLICKHOUSE_USER"),
            "CLICKHOUSE_PASSWORD": os.environ.get("CLICKHOUSE_PASSWORD"),
        },
    )

    # Lineage dependency
    ingest_task >> wait_for_cdc >> dbt_task
