import logging
import os
import time

import psycopg
import requests

# Logging (structured enough for Airflow task logs)
formatter = logging.Formatter("%(asctime)s %(levelname)s %(name)s: %(message)s")
logger = logging.getLogger("inkomoko_ingestion")
logger.setLevel(logging.INFO)
if not logger.handlers:
    handler = logging.StreamHandler()
    handler.setLevel(logging.INFO)
    handler.setFormatter(formatter)
    logger.addHandler(handler)

# Database configuration - all credentials are injected from the environment
# (.env) by the orchestrator; no secrets are hardcoded or defaulted in source.
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5433")
DB_USER = os.getenv("DB_USER")
DB_PASS = os.getenv("DB_PASS")
DB_NAME = os.getenv("DB_NAME")

KIVA_API_URL = "https://api.kivaws.org/v1/loans/search.json"

# How many pages (and records per page) to pull per run. Tunable via env so the
# backfill depth is configurable without touching code.
KIVA_PAGES = int(os.getenv("KIVA_PAGES", "3"))
KIVA_PER_PAGE = int(os.getenv("KIVA_PER_PAGE", "100"))

KIVA_HEADERS = {
    # Kiva's API uses a Web Application Firewall which blocks requests that use
    # the default Python requests library signature to prevent bot spam, so we
    # present a standard browser User-Agent header.
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36",
    "Accept": "application/json",
}

_session = requests.Session()
_session.headers.update(KIVA_HEADERS)


def fetch_loans(page=1, per_page=KIVA_PER_PAGE):
    """Fetch loan data from Kiva's public REST API."""
    logger.info("Fetching page %s from Kiva API...", page)
    params = {
        "status": "funded",
        "per_page": per_page,
        "page": page,
    }

    # Exponential backoff retry
    for attempt in range(3):
        try:
            response = _session.get(KIVA_API_URL, params=params, timeout=10)
            response.raise_for_status()
            data = response.json()
            return data.get("loans", [])
        except requests.exceptions.RequestException as e:
            logger.warning("Attempt %d failed: %s", attempt + 1, e)
            time.sleep(2 ** attempt)

    raise Exception("Failed to fetch data from API after multiple attempts.")


def get_db_connection():
    """Establish connection to PostgreSQL."""
    return psycopg.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASS
    )


def upsert_loans(conn, loans):
    """
    Idempotent insert into PostgreSQL.
    If loan ID exists, update it to simulate changes for CDC.
    """
    if not loans:
        return 0

    # Extract only the fields we need, safely handling missing keys
    values = []
    for loan in loans:
        location = loan.get("location", {})
        values.append((
            loan.get("id"),
            loan.get("name"),
            loan.get("status"),
            loan.get("funded_amount"),
            loan.get("loan_amount"),
            loan.get("activity"),
            loan.get("sector"),
            location.get("country"),
            location.get("town"),
            loan.get("posted_date")
        ))

    # Refresh every mutable column on conflict, not just a subset, so that any
    # upstream change (name, sector, activity, ...) is faithfully propagated
    # through CDC. updated_at is always bumped so Debezium emits an event even
    # for a genuine no-op re-ingest, keeping the raw CDC stream alive.
    upsert_query = """
        INSERT INTO raw_data.kiva_loans
        (id, name, status, funded_amount, loan_amount, activity, sector, country, town, posted_date)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        ON CONFLICT (id) DO UPDATE SET
            name = EXCLUDED.name,
            status = EXCLUDED.status,
            funded_amount = EXCLUDED.funded_amount,
            loan_amount = EXCLUDED.loan_amount,
            activity = EXCLUDED.activity,
            sector = EXCLUDED.sector,
            country = EXCLUDED.country,
            town = EXCLUDED.town,
            posted_date = EXCLUDED.posted_date,
            updated_at = CURRENT_TIMESTAMP;
    """

    # Errors MUST propagate (rollback then re-raise) so that Airflow marks the
    # task as failed instead of continuing with a silently empty write.
    try:
        with conn.cursor() as cur:
            cur.executemany(upsert_query, values)
        conn.commit()
        return len(values)
    except Exception:
        conn.rollback()
        raise


def main():
    logger.info("Starting Inkomoko Data Ingestion Job... (pages=%s, per_page=%s)",
                KIVA_PAGES, KIVA_PER_PAGE)
    conn = get_db_connection()

    try:
        total_ingested = 0
        for page in range(1, KIVA_PAGES + 1):
            loans = fetch_loans(page=page)
            if not loans:
                break

            inserted_count = upsert_loans(conn, loans)
            total_ingested += inserted_count
            logger.info("Successfully upserted %s records.", inserted_count)

        logger.info("Job complete! Total records upserted: %s", total_ingested)

    finally:
        conn.close()


if __name__ == "__main__":
    main()
