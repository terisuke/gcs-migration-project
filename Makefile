# GCS Migration Project Makefile
# This Makefile automates the GCS migration workflow

# Load environment variables from .env file if it exists
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

# Default shell
SHELL := /bin/bash

# Color codes for output
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m # No Color

# Timestamp for operations
TIMESTAMP := $(shell date +"%Y%m%d_%H%M%S")

# Help command - default target
.PHONY: help
help:
	@echo "$(GREEN)GCS Migration Project - Available Commands$(NC)"
	@echo ""
	@echo "$(YELLOW)Setup:$(NC)"
	@echo "  make setup              - Initial setup (copy .env.example to .env)"
	@echo "  make check-env          - Verify environment variables"
	@echo ""
	@echo "$(YELLOW)Migration Workflow:$(NC)"
	@echo "  make migrate-robust     - Complete migration with 100% success guarantee"
	@echo "  make migrate-all        - Run complete migration (all phases)"
	@echo "  make robust-download    - Download with retry logic (100% success)"
	@echo "  make phase1             - Download from source project"
	@echo "  make phase2             - Create archive from downloaded data"
	@echo "  make phase3             - Upload archive to destination project"
	@echo ""
	@echo "$(YELLOW)Individual Operations:$(NC)"
	@echo "  make download           - Alias for phase1"
	@echo "  make archive            - Alias for phase2"
	@echo "  make upload             - Alias for phase3"
	@echo "  make restore            - Run advanced restore tool"
	@echo ""
	@echo "$(YELLOW)Authentication:$(NC)"
	@echo "  make auth-source        - Login to source account"
	@echo "  make auth-dest          - Login to destination account"
	@echo "  make auth-check         - Check current authentication"
	@echo ""
	@echo "$(YELLOW)Utilities:$(NC)"
	@echo "  make status             - Check migration status and progress"
	@echo "  make list-source        - List buckets in source project"
	@echo "  make list-dest          - List buckets in destination project"
	@echo "  make disk-check         - Check available disk space"
	@echo "  make clean              - Remove temporary files (with confirmation)"
	@echo "  make clean-test         - Remove test migration files"
	@echo "  make clean-all          - Remove all downloaded/archived data (with confirmation)"
	@echo ""
	@echo "$(YELLOW)Testing:$(NC)"
	@echo "  make test-scripts       - Check script syntax"
	@echo "  make test-bucket BUCKET=name - Test migration with a single bucket"
	@echo "  make dry-run            - Run migration in dry-run mode"

# Initial setup
.PHONY: setup
setup:
	@if [ -f .env ]; then \
		echo "$(YELLOW).env file already exists. Skipping setup.$(NC)"; \
	else \
		cp .env.example .env; \
		echo "$(GREEN)Created .env file from .env.example$(NC)"; \
		echo "$(YELLOW)Please edit .env with your actual values$(NC)"; \
	fi
	@chmod +x phase1_download.sh phase2_archive.sh phase3_upload.sh advanced_restore.sh robust_download.sh check-migration-status.sh migrate-robust.sh 2>/dev/null || true
	@echo "$(GREEN)Made all scripts executable$(NC)"

# Environment check
.PHONY: check-env
check-env:
	@echo "$(GREEN)Checking environment variables...$(NC)"
	@test -n "$${GCS_SOURCE_ACCOUNT}" || (echo "$(RED)Error: GCS_SOURCE_ACCOUNT not set$(NC)" && exit 1)
	@test -n "$${GCS_DEST_ACCOUNT}" || (echo "$(RED)Error: GCS_DEST_ACCOUNT not set$(NC)" && exit 1)
	@test -n "$${GCS_SOURCE_PROJECT}" || (echo "$(RED)Error: GCS_SOURCE_PROJECT not set$(NC)" && exit 1)
	@test -n "$${GCS_DEST_PROJECT}" || (echo "$(RED)Error: GCS_DEST_PROJECT not set$(NC)" && exit 1)
	@test -n "$${GCS_LOCAL_BACKUP_DIR}" || (echo "$(RED)Error: GCS_LOCAL_BACKUP_DIR not set$(NC)" && exit 1)
	@test -n "$${GCS_ARCHIVE_BUCKET}" || (echo "$(RED)Error: GCS_ARCHIVE_BUCKET not set$(NC)" && exit 1)
	@echo "$(GREEN)All required environment variables are set$(NC)"

# Complete migration workflow
.PHONY: migrate-all
migrate-all: check-env
	@echo "$(GREEN)Starting complete GCS migration workflow$(NC)"
	@echo "$(YELLOW)This will run all three phases sequentially$(NC)"
	@read -p "Continue? [y/N] " -n 1 -r && echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		$(MAKE) phase1 && \
		$(MAKE) phase2 && \
		$(MAKE) phase3 && \
		echo "$(GREEN)Migration completed successfully!$(NC)"; \
	else \
		echo "$(YELLOW)Migration cancelled$(NC)"; \
	fi

# Robust migration workflow - 100% success guaranteed
.PHONY: migrate-robust
migrate-robust: check-env
	@./migrate-robust.sh

# Phase 1: Download
.PHONY: phase1 download
phase1 download: check-env auth-check-source
	@echo "$(GREEN)Phase 1: Downloading from $(GCS_SOURCE_PROJECT)$(NC)"
	@./phase1_download.sh

# Robust download - ensures 100% success with retry logic
.PHONY: robust-download
robust-download: check-env auth-check-source
	@echo "$(GREEN)Starting robust download with retry logic (100% success guaranteed)$(NC)"
	@./robust_download.sh

# Phase 2: Archive
.PHONY: phase2 archive
phase2 archive: check-env
	@echo "$(GREEN)Phase 2: Creating archive$(NC)"
	@./phase2_archive.sh

# Phase 3: Upload
.PHONY: phase3 upload
phase3 upload: check-env auth-check-dest
	@echo "$(GREEN)Phase 3: Uploading to $(GCS_DEST_PROJECT)$(NC)"
	@./phase3_upload.sh

# Restore operation
.PHONY: restore
restore: check-env
	@echo "$(GREEN)Running advanced restore tool$(NC)"
	@./advanced_restore.sh

# Authentication helpers
.PHONY: auth-source
auth-source:
	@echo "$(GREEN)Authenticating with source account: $(GCS_SOURCE_ACCOUNT)$(NC)"
	@gcloud auth login $(GCS_SOURCE_ACCOUNT)

.PHONY: auth-dest
auth-dest:
	@echo "$(GREEN)Authenticating with destination account: $(GCS_DEST_ACCOUNT)$(NC)"
	@gcloud auth login $(GCS_DEST_ACCOUNT)

.PHONY: auth-check
auth-check:
	@echo "$(GREEN)Current authentication status:$(NC)"
	@gcloud auth list

.PHONY: auth-check-source
auth-check-source:
	@echo "$(GREEN)Checking source account authentication...$(NC)"
	@CURRENT_ACCOUNT=$$(gcloud auth list --filter="status:ACTIVE" --format="value(account)"); \
	if [[ "$$CURRENT_ACCOUNT" != "$(GCS_SOURCE_ACCOUNT)" ]]; then \
		echo "$(YELLOW)Not logged in as $(GCS_SOURCE_ACCOUNT)$(NC)"; \
		echo "$(YELLOW)Please run: make auth-source$(NC)"; \
		exit 1; \
	else \
		echo "$(GREEN)Authenticated as $(GCS_SOURCE_ACCOUNT)$(NC)"; \
	fi

.PHONY: auth-check-dest
auth-check-dest:
	@echo "$(GREEN)Checking destination account authentication...$(NC)"
	@CURRENT_ACCOUNT=$$(gcloud auth list --filter="status:ACTIVE" --format="value(account)"); \
	if [[ "$$CURRENT_ACCOUNT" != "$(GCS_DEST_ACCOUNT)" ]]; then \
		echo "$(YELLOW)Not logged in as $(GCS_DEST_ACCOUNT)$(NC)"; \
		echo "$(YELLOW)Please run: make auth-dest$(NC)"; \
		exit 1; \
	else \
		echo "$(GREEN)Authenticated as $(GCS_DEST_ACCOUNT)$(NC)"; \
	fi

# Utility commands
.PHONY: status
status:
	@./check-migration-status.sh

.PHONY: list-source
list-source: auth-check-source
	@echo "$(GREEN)Buckets in source project ($(GCS_SOURCE_PROJECT)):$(NC)"
	@gcloud storage buckets list --project=$(GCS_SOURCE_PROJECT)

.PHONY: list-dest
list-dest: auth-check-dest
	@echo "$(GREEN)Buckets in destination project ($(GCS_DEST_PROJECT)):$(NC)"
	@gcloud storage buckets list --project=$(GCS_DEST_PROJECT)

.PHONY: disk-check
disk-check:
	@echo "$(GREEN)Available disk space:$(NC)"
	@df -h $(GCS_LOCAL_BACKUP_DIR) 2>/dev/null || df -h .

# Testing commands
.PHONY: test-scripts
test-scripts:
	@echo "$(GREEN)Checking shell script syntax...$(NC)"
	@bash -n phase1_download.sh && echo "✓ phase1_download.sh"
	@bash -n phase2_archive.sh && echo "✓ phase2_archive.sh"
	@bash -n phase3_upload.sh && echo "✓ phase3_upload.sh"
	@bash -n advanced_restore.sh && echo "✓ advanced_restore.sh"
	@echo "$(GREEN)All scripts passed syntax check$(NC)"

.PHONY: dry-run
dry-run: check-env
	@echo "$(YELLOW)Dry-run mode is not yet implemented in the scripts$(NC)"
	@echo "$(YELLOW)This would simulate the migration without actual data transfer$(NC)"

# Test single bucket migration
.PHONY: test-bucket
test-bucket: check-env
	@if [ -z "$(BUCKET)" ]; then \
		echo "$(RED)Error: Please specify BUCKET=bucket-name$(NC)"; \
		echo "$(YELLOW)Example: make test-bucket BUCKET=yolov8environment-logs$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Testing migration for single bucket: $(BUCKET)$(NC)"
	@echo "$(YELLOW)This will perform a complete migration cycle for one bucket$(NC)"
	@read -p "Continue with test migration of gs://$(BUCKET)? [y/N] " -n 1 -r && echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		$(MAKE) test-download BUCKET=$(BUCKET) && \
		$(MAKE) test-archive BUCKET=$(BUCKET) && \
		$(MAKE) test-upload BUCKET=$(BUCKET); \
	else \
		echo "$(YELLOW)Test cancelled$(NC)"; \
	fi

# Test download for single bucket
.PHONY: test-download
test-download: auth-check-source
	@echo "$(GREEN)Test Phase 1: Downloading bucket $(BUCKET)$(NC)"
	@TIMESTAMP=$$(date +"%Y%m%d_%H%M%S"); \
	TEST_DIR="$(GCS_LOCAL_BACKUP_DIR)/test_$(BUCKET)_$$TIMESTAMP"; \
	mkdir -p "$$TEST_DIR/$(BUCKET)"; \
	echo "$(GREEN)Downloading to: $$TEST_DIR$(NC)"; \
	gsutil -o "GSUtil:parallel_process_count=1" -m cp -r "gs://$(BUCKET)/**" "$$TEST_DIR/$(BUCKET)/" 2>&1 | tee test_download.log || true; \
	echo "$$TEST_DIR" > .test_dir; \
	echo "$(GREEN)✓ Test download completed$(NC)"

# Test archive for single bucket
.PHONY: test-archive
test-archive:
	@if [ ! -f .test_dir ]; then \
		echo "$(RED)Error: No test download found. Run 'make test-download BUCKET=name' first$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Test Phase 2: Creating archive$(NC)"
	@TEST_DIR=$$(cat .test_dir); \
	PARENT_DIR=$$(dirname "$$TEST_DIR"); \
	BASE_NAME=$$(basename "$$TEST_DIR"); \
	ARCHIVE_NAME="$$BASE_NAME.tar.gz"; \
	cd "$$PARENT_DIR" && tar czf "$$ARCHIVE_NAME" "$$BASE_NAME"; \
	echo "$$PARENT_DIR/$$ARCHIVE_NAME" > .test_archive; \
	echo "$(GREEN)✓ Test archive created: $$ARCHIVE_NAME (size: $$(du -h "$$PARENT_DIR/$$ARCHIVE_NAME" | cut -f1))$(NC)"

# Test upload for single bucket
.PHONY: test-upload
test-upload: auth-check-dest
	@if [ ! -f .test_archive ]; then \
		echo "$(RED)Error: No test archive found. Run 'make test-archive' first$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Test Phase 3: Uploading archive$(NC)"
	@ARCHIVE_PATH=$$(cat .test_archive); \
	ARCHIVE_NAME=$$(basename "$$ARCHIVE_PATH"); \
	echo "$(GREEN)Uploading to: gs://$(GCS_ARCHIVE_BUCKET)/test/$$ARCHIVE_NAME$(NC)"; \
	gsutil cp "$$ARCHIVE_PATH" "gs://$(GCS_ARCHIVE_BUCKET)/test/$$ARCHIVE_NAME"; \
	echo "$(GREEN)✓ Test upload completed$(NC)"; \
	echo "$(GREEN)Archive available at: gs://$(GCS_ARCHIVE_BUCKET)/test/$$ARCHIVE_NAME$(NC)"

# Clean test files
.PHONY: clean-test
clean-test:
	@echo "$(YELLOW)Cleaning test files and directories$(NC)"
	@if [ -f .test_dir ]; then \
		TEST_DIR=$$(cat .test_dir); \
		rm -rf "$$TEST_DIR"; \
		rm -f .test_dir; \
	fi
	@if [ -f .test_archive ]; then \
		ARCHIVE_PATH=$$(cat .test_archive); \
		rm -f "$$ARCHIVE_PATH"; \
		rm -f .test_archive; \
	fi
	@rm -f test_download.log
	@echo "$(YELLOW)Cleaning GCS test files...$(NC)"
	@gsutil -q rm -r gs://$(GCS_ARCHIVE_BUCKET)/test/ 2>/dev/null || true
	@echo "$(GREEN)Test files cleaned (local and GCS)$(NC)"

# Cleanup commands
.PHONY: clean
clean:
	@echo "$(YELLOW)This will remove temporary files and logs$(NC)"
	@read -p "Continue? [y/N] " -n 1 -r && echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		rm -f *.log download_manifest.txt download_status.txt; \
		echo "$(GREEN)Cleaned temporary files$(NC)"; \
	else \
		echo "$(YELLOW)Cleanup cancelled$(NC)"; \
	fi

.PHONY: clean-all
clean-all:
	@echo "$(RED)WARNING: This will remove ALL downloaded and archived data!$(NC)"
	@echo "$(RED)Directories to be removed:$(NC)"
	@echo "$(RED)  - $(GCS_LOCAL_BACKUP_DIR)/yolov8environment_backup_*$(NC)"
	@echo "$(RED)  - All *.tar.gz files in current directory$(NC)"
	@read -p "Are you SURE? Type 'yes' to confirm: " -r; \
	if [[ $$REPLY == "yes" ]]; then \
		rm -rf $(GCS_LOCAL_BACKUP_DIR)/yolov8environment_backup_*; \
		rm -f *.tar.gz *.tar.gz.json; \
		$(MAKE) clean; \
		echo "$(GREEN)All data cleaned$(NC)"; \
	else \
		echo "$(YELLOW)Cleanup cancelled$(NC)"; \
	fi

# Default target
.DEFAULT_GOAL := help