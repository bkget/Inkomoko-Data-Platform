#!/bin/sh
# register_schema.sh
# One-shot script: registers the kiva_loans Avro schema in Redpanda's schema registry
# and sets FORWARD compatibility for the subject.
# Idempotent — re-registering an identical schema returns the existing ID, safe on restart.

set -e

SUBJECT="cdc.raw_data.kiva_loans-value"
SR_URL="${SCHEMA_REGISTRY_URL:-http://redpanda:8081}"

echo "[schema-registrar] Waiting for schema registry at ${SR_URL}..."
until curl -sf "${SR_URL}/subjects" > /dev/null; do
  sleep 2
done
echo "[schema-registrar] Schema registry is up."

# FORWARD compatibility: consumers on the old schema still work when new nullable fields
# are added. Breaking changes (field removal, type change) are rejected by the registry.
echo "[schema-registrar] Setting FORWARD compatibility for subject: ${SUBJECT}"
curl -sf -X PUT \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d '{"compatibility": "FORWARD"}' \
  "${SR_URL}/config/${SUBJECT}" | jq .

# Wrap the Avro schema JSON into the registry envelope: {"schema": "<escaped-json-string>"}
SCHEMA_JSON=$(cat /config/kiva_loans_avro_schema.json | jq -c '{schema: (.schema | tojson)}')

echo "[schema-registrar] Registering schema for subject: ${SUBJECT}"
RESPONSE=$(curl -sf -X POST \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d "${SCHEMA_JSON}" \
  "${SR_URL}/subjects/${SUBJECT}/versions")

echo "[schema-registrar] Done. Registry response: ${RESPONSE}"
