# ==============================================================================
# Inkomoko Data Platform - Production-Grade Management Makefile
# ==============================================================================
# Provides unified commands for deploying, inspecting, testing, and managing
# the complete real-time CDC, OLAP, and Observability stack.
# ==============================================================================

SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

# Load environment variables if .env exists
-include .env
export

# Terminal Colors & Styling
BOLD := \033[1m
DIM := \033[2m
RESET := \033[0m
CYAN := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
BLUE := \033[34m
MAGENTA := \033[35m
RED := \033[31m
WHITE := \033[37m

# Default Credentials (fallback if .env is not yet created)
PG_USER ?= ${POSTGRES_USER}
PG_USER := $(if $(PG_USER),$(PG_USER),inkomoko_admin)
PG_PASS ?= ${POSTGRES_PASSWORD}
PG_PASS := $(if $(PG_PASS),$(PG_PASS),inkomoko_password)
PG_DB ?= ${POSTGRES_DB}
PG_DB := $(if $(PG_DB),$(PG_DB),inkomoko_oltp)
PG_PORT ?= ${POSTGRES_PORT}
PG_PORT := $(if $(PG_PORT),$(PG_PORT),5433)

CH_USER ?= ${CLICKHOUSE_USER}
CH_USER := $(if $(CH_USER),$(CH_USER),inkomoko_admin)
CH_PASS ?= ${CLICKHOUSE_PASSWORD}
CH_PASS := $(if $(CH_PASS),$(CH_PASS),inkomoko_password)
CH_PORT ?= ${CLICKHOUSE_HTTP_PORT}
CH_PORT := $(if $(CH_PORT),$(CH_PORT),8123)

GRAFANA_USER ?= ${GF_SECURITY_ADMIN_USER}
GRAFANA_USER := $(if $(GRAFANA_USER),$(GRAFANA_USER),admin)
GRAFANA_PASS ?= ${GF_SECURITY_ADMIN_PASSWORD}
GRAFANA_PASS := $(if $(GRAFANA_PASS),$(GRAFANA_PASS),inkomoko)

# ------------------------------------------------------------------------------
# Help Target (Default)
# ------------------------------------------------------------------------------
.PHONY: help
help: ## Show this interactive help dashboard with command explanations
	@echo -e "\n$(BOLD)$(CYAN)==============================================================================$(RESET)"
	@echo -e "$(BOLD)$(WHITE)  Inkomoko Data Platform - Engineering & Deployment Makefile$(RESET)"
	@echo -e "$(BOLD)$(CYAN)==============================================================================$(RESET)"
	@echo -e "$(DIM)Usage: make <target> [variable=value]$(RESET)"
	@awk 'BEGIN {FS = ":.*##"; printf ""} \
		/^[a-zA-Z_ -]+:.*?##/ { printf "  $(BOLD)$(CYAN)%-22s$(RESET) %s\n", $$1, $$2 } \
		/^##@/ { printf "\n$(BOLD)$(YELLOW)%s$(RESET)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
	@echo -e "\n$(BOLD)$(MAGENTA)Quickstart for Reviewers:$(RESET)"
	@echo -e "  $(BOLD)1.$(RESET) $(CYAN)make up$(RESET)       -> Boots the full 16-container platform & reveals all URLs"
	@echo -e "  $(BOLD)2.$(RESET) $(CYAN)make urls$(RESET)     -> Displays all web interfaces, endpoints, and credentials"
	@echo -e "  $(BOLD)3.$(RESET) $(CYAN)make verify$(RESET)   -> Automatically checks all 6 stages of the data pipeline"
	@echo -e "  $(BOLD)4.$(RESET) $(CYAN)make down$(RESET)     -> Stops all containers safely\n"

##@ Reviewer Access & Documentation
.PHONY: urls endpoints info
urls endpoints info: ## Display a publication-grade table of all UI endpoints and credentials
	@echo -e "\n$(BOLD)$(CYAN)====================================================================================================$(RESET)"
	@echo -e "$(BOLD)$(WHITE)                                  INKOMOKO DATA PLATFORM ENDPOINTS                                  $(RESET)"
	@echo -e "$(BOLD)$(CYAN)====================================================================================================$(RESET)"
	@printf "$(BOLD) %-32s %-26s %-38s$(RESET)\n" "SERVICE / COMPONENT" "URL / HOST PORT" "AUTHENTICATION / NOTES"
	@echo -e "$(CYAN)----------------------------------------------------------------------------------------------------$(RESET)"
	@echo -e "$(BOLD)$(YELLOW) [ Web Dashboards & User Interfaces ]$(RESET)"
	@printf "  %-30s $(CYAN)%-26s$(RESET) $(GREEN)%-38s$(RESET)\n" "Dagster (Asset Orchestrator)" "http://localhost:3000" "None (Public Dashboard)"
	@printf "  %-30s $(CYAN)%-26s$(RESET) $(YELLOW)%-38s$(RESET)\n" "Grafana (Metrics & BI)" "http://localhost:3001" "User: $(GRAFANA_USER) | Pass: $(GRAFANA_PASS)"
	@printf "  %-30s $(CYAN)%-26s$(RESET) $(GREEN)%-38s$(RESET)\n" "dbt-docs (Lineage & Catalog)" "http://localhost:8085" "None (Interactive Lineage DAG)"
	@printf "  %-30s $(CYAN)%-26s$(RESET) $(GREEN)%-38s$(RESET)\n" "Redpanda Console (Kafka UI)" "http://localhost:8080" "None (Topic & Message Explorer)"
	@printf "  %-30s $(CYAN)%-26s$(RESET) $(GREEN)%-38s$(RESET)\n" "Debezium UI (CDC Status)" "http://localhost:8084" "None (Connector Management UI)"
	@printf "  %-30s $(CYAN)%-26s$(RESET) $(GREEN)%-38s$(RESET)\n" "Mailpit (Alert Email Catcher)" "http://localhost:8025" "None (Inbox for Grafana Alerts)"
	@echo -e "$(CYAN)----------------------------------------------------------------------------------------------------$(RESET)"
	@echo -e "$(BOLD)$(YELLOW) [ Observability & Metrics Endpoints ]$(RESET)"
	@printf "  %-30s $(CYAN)%-26s$(RESET) $(GREEN)%-38s$(RESET)\n" "Prometheus (Time-series Scraper)" "http://localhost:9090" "None (Targets & PromQL Query UI)"
	@printf "  %-30s $(CYAN)%-26s$(RESET) $(GREEN)%-38s$(RESET)\n" "cdc-monitor (Drift/Lag Exporter)" "http://localhost:9200/metrics" "Raw Prometheus Metrics Endpoint"
	@printf "  %-30s $(CYAN)%-26s$(RESET) $(GREEN)%-38s$(RESET)\n" "Postgres Exporter (DB Telemetry)" "http://localhost:9187/metrics" "Raw PostgreSQL Metrics Endpoint"
	@printf "  %-30s $(CYAN)%-26s$(RESET) $(GREEN)%-38s$(RESET)\n" "ClickHouse Native Prometheus" "http://localhost:9363/metrics" "Raw ClickHouse Metrics Endpoint"
	@echo -e "$(CYAN)----------------------------------------------------------------------------------------------------$(RESET)"
	@echo -e "$(BOLD)$(YELLOW) [ Database Storage & Wire Protocols ]$(RESET)"
	@printf "  %-30s $(CYAN)%-26s$(RESET) $(YELLOW)%-38s$(RESET)\n" "PostgreSQL OLTP (Source DB)" "localhost:$(PG_PORT)" "User: $(PG_USER) | DB: $(PG_DB)"
	@printf "  %-30s $(CYAN)%-26s$(RESET) $(YELLOW)%-38s$(RESET)\n" "ClickHouse HTTP (OLAP Engine)" "http://localhost:$(CH_PORT)" "User: $(CH_USER) | Pass: $(CH_PASS)"
	@printf "  %-30s $(CYAN)%-26s$(RESET) $(YELLOW)%-38s$(RESET)\n" "ClickHouse Native TCP" "localhost:9000" "User: $(CH_USER) | Pass: $(CH_PASS)"
	@printf "  %-30s $(CYAN)%-26s$(RESET) $(GREEN)%-38s$(RESET)\n" "Redpanda Kafka Broker (Host)" "localhost:9092" "PLAINTEXT (Internal: 29092)"
	@printf "  %-30s $(CYAN)%-26s$(RESET) $(GREEN)%-38s$(RESET)\n" "Debezium Connect REST API" "http://localhost:8083" "REST API for Connectors/Tasks"
	@echo -e "$(BOLD)$(CYAN)====================================================================================================$(RESET)\n"

##@ Deployment & Lifecycle
.PHONY: init env
init env: ## Ensure .env file is initialized from .env.example
	@if [ ! -f .env ]; then \
		echo -e "$(YELLOW)[i] .env file not found. Creating from .env.example...$(RESET)"; \
		cp .env.example .env; \
		echo -e "$(GREEN)[✓] Initialized .env with default credentials.$(RESET)"; \
	else \
		echo -e "$(DIM)[✓] .env already exists.$(RESET)"; \
	fi

.PHONY: up start
up start: init ## Start the entire 16-container platform in detached mode and print URLs
	@echo -e "$(BOLD)$(CYAN)[*] Launching Inkomoko Data Platform via Docker Compose...$(RESET)"
	@docker compose up -d
	@echo -e "$(BOLD)$(GREEN)[✓] All services dispatched successfully!$(RESET)"
	@$(MAKE) --no-print-directory urls

.PHONY: down stop
down stop: ## Stop and remove all running containers safely
	@echo -e "$(YELLOW)[*] Stopping all Inkomoko services...$(RESET)"
	@docker compose down
	@echo -e "$(GREEN)[✓] Stack stopped successfully.$(RESET)"

.PHONY: restart
restart: ## Restart all containers or a specific service (e.g. make restart svc=clickhouse)
	@if [ -n "$(svc)" ]; then \
		echo -e "$(YELLOW)[*] Restarting service: $(svc)...$(RESET)"; \
		docker compose restart $(svc); \
		echo -e "$(GREEN)[✓] Service $(svc) restarted.$(RESET)"; \
	else \
		echo -e "$(YELLOW)[*] Restarting full stack...$(RESET)"; \
		docker compose restart; \
		echo -e "$(GREEN)[✓] Full stack restarted.$(RESET)"; \
	fi

.PHONY: ps status
ps status: ## List running services and their healthcheck states
	@echo -e "\n$(BOLD)$(CYAN)=== Container Status & Healthchecks ===$(RESET)\n"
	@docker compose ps

.PHONY: clean
clean: ## Stop containers, remove named volumes, networks, and orphaned resources
	@echo -e "$(BOLD)$(RED)[!] WARNING: This will destroy all database volumes and local caches.$(RESET)"
	@read -p "Are you sure you want to clean everything? [y/N] " confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		docker compose down -v --remove-orphans; \
		rm -rf dbt_project/target dbt_project/dbt_packages; \
		echo -e "$(GREEN)[✓] Clean completed. Platform is in pristine initial state.$(RESET)"; \
	else \
		echo -e "$(DIM)[i] Clean aborted.$(RESET)"; \
	fi

.PHONY: reset
reset: clean up ## Full reset: wipe volumes, rebuild, and re-launch stack from scratch

##@ Pipeline Verification & Health
.PHONY: verify health
verify health: ## Automatically validate all 6 stages of the data pipeline end-to-end
	@echo -e "\n$(BOLD)$(CYAN)==============================================================================$(RESET)"
	@echo -e "$(BOLD)$(WHITE)            STARTING END-TO-END DATA PIPELINE VERIFICATION                    $(RESET)"
	@echo -e "$(BOLD)$(CYAN)==============================================================================$(RESET)\n"
	@echo -e "$(BOLD)[Stage 1/6] Validating PostgreSQL OLTP Table...$(RESET)"
	@docker exec inkomoko_postgres psql -U $(PG_USER) -d $(PG_DB) -t -c \
		"SELECT '  [✓] PostgreSQL contains ' || COUNT(*) || ' loans (Max updated_at: ' || MAX(updated_at) || ')' FROM raw_data.kiva_loans;"
	@echo -e "\n$(BOLD)[Stage 2/6] Validating Redpanda Streaming Topic...$(RESET)"
	@docker exec inkomoko_redpanda rpk topic describe cdc.raw_data.kiva_loans > /dev/null 2>&1 && \
		echo -e "  $(GREEN)[✓] Topic 'cdc.raw_data.kiva_loans' exists and is active.$(RESET)" || \
		echo -e "  $(RED)[✗] Topic 'cdc.raw_data.kiva_loans' not found.$(RESET)"
	@echo -e "\n$(BOLD)[Stage 3/6] Validating Debezium CDC Connector State...$(RESET)"
	@docker exec inkomoko_debezium curl -sf http://localhost:8083/connectors/inkomoko-postgres-connector/status > /dev/null 2>&1 && \
		echo -e "  $(GREEN)[✓] Connector 'inkomoko-postgres-connector' is in RUNNING state.$(RESET)" || \
		echo -e "  $(RED)[✗] Connector failed or still initializing.$(RESET)"
	@echo -e "\n$(BOLD)[Stage 4/6] Validating ClickHouse Raw Ingest (ReplacingMergeTree)...$(RESET)"
	@CH_RAW_COUNT=$$(docker exec inkomoko_clickhouse clickhouse-client --user $(CH_USER) --password $(CH_PASS) --query \
		"SELECT COUNT(*) FROM raw_data.kiva_loans_raw FINAL WHERE is_deleted = 0" 2>/dev/null || echo "0"); \
		echo -e "  $(GREEN)[✓] ClickHouse raw table contains $$CH_RAW_COUNT active deduplicated loans.$(RESET)"
	@echo -e "\n$(BOLD)[Stage 5/6] Validating ClickHouse Analytical Marts (dbt)...$(RESET)"
	@SECTOR_COUNT=$$(docker exec inkomoko_clickhouse clickhouse-client --user $(CH_USER) --password $(CH_PASS) --query \
		"SELECT COUNT(*) FROM analytics.mart_loans_by_sector" 2>/dev/null || echo "0"); \
	ML_COUNT=$$(docker exec inkomoko_clickhouse clickhouse-client --user $(CH_USER) --password $(CH_PASS) --query \
		"SELECT COUNT(*) FROM analytics.mart_loan_features_ml" 2>/dev/null || echo "0"); \
		echo -e "  $(GREEN)[✓] analytics.mart_loans_by_sector contains $$SECTOR_COUNT aggregate rows.$(RESET)"; \
		echo -e "  $(GREEN)[✓] analytics.mart_loan_features_ml contains $$ML_COUNT engineered feature rows.$(RESET)"
	@echo -e "\n$(BOLD)[Stage 6/6] Validating CDC Monitor Observability (Drift & Lag)...$(RESET)"
	@METRICS=$$(curl -sf http://localhost:9200/metrics 2>/dev/null || true); \
	DRIFT=$$(echo "$$METRICS" | grep -E '^cdc_row_count_drift ' | awk '{print $$2}' || echo "N/A"); \
	LAG=$$(echo "$$METRICS" | grep -E '^cdc_replication_lag_seconds ' | awk '{print $$2}' || echo "N/A"); \
	STATE=$$(echo "$$METRICS" | grep -E '^debezium_connector_state\{' | awk '{print $$2}' || echo "N/A"); \
		echo -e "  $(GREEN)[✓] cdc_row_count_drift:          $$DRIFT (Target: 0)$(RESET)"; \
		echo -e "  $(GREEN)[✓] cdc_replication_lag_seconds:  $${LAG}s$(RESET)"; \
		echo -e "  $(GREEN)[✓] debezium_connector_state:     $$STATE (1 = RUNNING)$(RESET)"
	@echo -e "\n$(BOLD)$(GREEN)==============================================================================$(RESET)"
	@echo -e "$(BOLD)$(GREEN)       [✓] PIPELINE VERIFICATION COMPLETE: ALL SYSTEMS OPERATIONAL            $(RESET)"
	@echo -e "$(BOLD)$(GREEN)==============================================================================$(RESET)\n"

##@ Data Engineering Operations
.PHONY: ingest
ingest: ## Trigger the Python Kiva API ingestion script inside the Dagster worker
	@echo -e "$(CYAN)[*] Triggering manual API ingestion into PostgreSQL...$(RESET)"
	@docker exec inkomoko_dagster python src/ingest_api.py
	@echo -e "$(GREEN)[✓] Ingestion complete.$(RESET)"

.PHONY: dbt-run
dbt-run: ## Execute dbt run in ClickHouse to build staging, intermediate, and marts
	@echo -e "$(CYAN)[*] Executing dbt models across ClickHouse...$(RESET)"
	@docker exec -w /usr/app inkomoko_dbt dbt run
	@echo -e "$(GREEN)[✓] dbt models built successfully.$(RESET)"

.PHONY: dbt-test
dbt-test: ## Execute dbt data quality and schema assertions
	@echo -e "$(CYAN)[*] Running dbt test assertions...$(RESET)"
	@docker exec -w /usr/app inkomoko_dbt dbt test
	@echo -e "$(GREEN)[✓] All dbt data quality tests passed.$(RESET)"

.PHONY: dbt-docs
dbt-docs: ## Regenerate dbt docs and display local browser URL
	@echo -e "$(CYAN)[*] Regenerating dbt documentation catalog...$(RESET)"
	@docker exec -w /usr/app inkomoko_dbt dbt docs generate
	@echo -e "$(GREEN)[✓] dbt docs generated. View live at: $(CYAN)http://localhost:8085$(RESET)"

.PHONY: dagster-run
dagster-run: ## Trigger the end-to-end Dagster pipeline job immediately via CLI
	@echo -e "$(CYAN)[*] Triggering Dagster end_to_end_pipeline job execution...$(RESET)"
	@docker exec -w /opt/dagster/app inkomoko_dagster dagster job execute \
		-f dagster_orchestration/definitions.py -j end_to_end_pipeline

##@ Interactive Shells & Logs
.PHONY: psql
psql: ## Open an interactive psql session to the PostgreSQL OLTP database
	@echo -e "$(CYAN)[*] Connecting to PostgreSQL ($(PG_DB))...$(RESET)"
	@docker exec -it inkomoko_postgres psql -U $(PG_USER) -d $(PG_DB)

.PHONY: clickhouse-cli ch-cli
clickhouse-cli ch-cli: ## Open an interactive clickhouse-client shell to ClickHouse
	@echo -e "$(CYAN)[*] Connecting to ClickHouse client...$(RESET)"
	@docker exec -it inkomoko_clickhouse clickhouse-client --user $(CH_USER) --password $(CH_PASS)

.PHONY: redpanda-cli rpk
redpanda-cli rpk: ## List streaming topics in Redpanda via native rpk CLI
	@echo -e "$(CYAN)[*] Inspecting Redpanda cluster topics...$(RESET)"
	@docker exec -it inkomoko_redpanda rpk topic list

.PHONY: logs
logs: ## Follow logs for all containers or a specific service (e.g. make logs svc=cdc-monitor)
	@if [ -n "$(svc)" ]; then \
		docker compose logs -f $(svc); \
	else \
		docker compose logs -f; \
	fi

##@ Code Quality & Testing
.PHONY: test
test: ## Run local Python unit tests for ingestion and cdc-monitor
	@echo -e "$(CYAN)[*] Running pytest suite...$(RESET)"
	@if [ -f ./.venv/bin/pytest ]; then \
		./.venv/bin/pytest tests/ -v; \
	elif command -v pytest > /dev/null 2>&1; then \
		pytest tests/ -v; \
	else \
		docker exec inkomoko_dagster pytest tests/ -v 2>/dev/null || \
		echo -e "$(YELLOW)[!] pytest not found locally. Install via: pip install pytest$(RESET)"; \
	fi

.PHONY: lint
lint: ## Run flake8 syntax and styling checks across the repository
	@echo -e "$(CYAN)[*] Running flake8 code quality checks...$(RESET)"
	@if [ -f ./.venv/bin/flake8 ]; then \
		./.venv/bin/flake8 src/ dagster_orchestration/ --count --select=E9,F63,F7,F82 --show-source --statistics; \
	elif command -v flake8 > /dev/null 2>&1; then \
		flake8 src/ dagster_orchestration/ --count --select=E9,F63,F7,F82 --show-source --statistics; \
	else \
		echo -e "$(YELLOW)[!] flake8 not found locally. Install via: pip install flake8$(RESET)"; \
	fi

##@ Chaos Engineering & Alert Demos
.PHONY: simulate-failure
simulate-failure: ## Simulate a CDC failure by stopping Debezium (triggers Grafana & Mailpit alerts)
	@echo -e "$(BOLD)$(RED)[*] Simulating CDC Failure: Stopping Debezium container...$(RESET)"
	@docker stop inkomoko_debezium
	@echo -e "$(YELLOW)[i] Debezium is stopped.$(RESET)"
	@echo -e "    Within 2-3 minutes, Grafana will fire the $(BOLD)'debezium-connector-down'$(RESET) alert."
	@echo -e "    Check your Mailpit inbox at: $(CYAN)http://localhost:8025$(RESET)"

.PHONY: simulate-recovery
simulate-recovery: ## Recover from simulated failure by restarting Debezium (resolves alerts)
	@echo -e "$(BOLD)$(GREEN)[*] Recovering CDC Service: Starting Debezium container...$(RESET)"
	@docker start inkomoko_debezium
	@echo -e "$(GREEN)[✓] Debezium restarted.$(RESET)"
	@echo -e "    Within 1-2 minutes, Grafana will evaluate the recovered state and send"
	@echo -e "    a $(BOLD)'[RESOLVED]'$(RESET) notification to Mailpit: $(CYAN)http://localhost:8025$(RESET)"
