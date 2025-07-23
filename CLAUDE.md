# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Google Cloud Storage (GCS) migration tool that transfers data between two GCP projects:
- **Source**: `yolov8environment` project (managed by cor-jp.com)
- **Destination**: `u-dake` project (managed by u-dake.com)

The project uses environment variables for configuration and Makefile for workflow automation.

## Quick Start

```bash
# 1. Setup environment
make setup              # Creates .env from .env.example
# Edit .env with your actual values

# 2. Run complete migration with 100% success guarantee
make migrate-robust     # Runs all phases with retry logic

# 3. Check status at any time
make status            # Shows migration progress and next steps
```

## Key Features

### Robust Download with Retry Logic
- **Empty Bucket Handling**: Automatically detects and skips empty buckets
- **Retry Mechanism**: Up to 5 retries per bucket with 10-second delays
- **100% Success Guarantee**: Won't proceed until all buckets are processed
- **Progress Tracking**: Real-time status updates and comprehensive logging

### Environment-based Configuration
All hardcoded values replaced with environment variables:
```bash
GCS_SOURCE_ACCOUNT      # Source Google account
GCS_DEST_ACCOUNT        # Destination Google account
GCS_SOURCE_PROJECT      # Source GCP project ID
GCS_DEST_PROJECT        # Destination GCP project ID
GCS_LOCAL_BACKUP_DIR    # Local backup directory
GCS_ARCHIVE_BUCKET      # Destination bucket name
```

### Makefile Automation
Complete workflow management with single commands:
```bash
make migrate-robust     # Complete migration with retry logic
make robust-download    # Download with empty bucket handling
make phase2            # Create archives
make phase3            # Upload to destination
make status            # Check migration status
```

## Architecture and Code Structure

### Core Scripts

1. **robust_download.sh**: Enhanced download with retry logic
   - Detects empty buckets and skips them
   - Retries failed downloads up to 5 times
   - Creates comprehensive download summary
   - Tracks status: SUCCESS, SKIPPED_EMPTY, FAILED

2. **phase1_download.sh**: Standard download script
   - Downloads all buckets from source project
   - Creates timestamped backup directory
   - Uses gsutil with parallel processing disabled for macOS

3. **phase2_archive.sh**: Archive creation
   - Auto-detects latest backup from latest_backup_path.txt
   - Supports multiple compression levels
   - Creates metadata files with checksums
   - Handles empty directories (.empty files)

4. **phase3_upload.sh**: Upload to destination
   - Uploads archives to destination bucket
   - Supports parallel composite uploads
   - Includes retry logic for large files

5. **check-migration-status.sh**: Status monitoring
   - Shows environment variable configuration
   - Displays authentication status
   - Reports download progress and statistics
   - Suggests next actions

### Migration Flow

```
1. Robust Download (make robust-download)
   ↓
   - Check each bucket for content
   - Skip empty buckets
   - Retry failed downloads
   - Create download summary
   
2. Archive Creation (make phase2)
   ↓
   - Auto-detect latest backup
   - Compress with selected level
   - Include empty directories
   
3. Upload to Destination (make phase3)
   ↓
   - Switch to destination account
   - Upload archives to GCS
   - Verify upload success
```

### Empty Bucket Handling

The robust_download.sh script handles empty buckets gracefully:
1. Checks if bucket has any objects before download
2. Creates empty directory with .empty marker file
3. Records as SKIPPED_EMPTY in status file
4. Counts as successful processing

### Key Implementation Details

- **Error Handling**: All scripts use `set -euo pipefail` for strict error handling
- **macOS Compatibility**: Uses `GSUtil:parallel_process_count=1` to avoid multiprocessing errors
- **Path Spaces**: Properly handles paths with spaces using `set -a; source .env; set +a`
- **Logging**: Color-coded output with timestamps and status tracking
- **State Persistence**: Uses latest_backup_path.txt for workflow continuity

## Common Issues and Solutions

### Empty Buckets Causing Failures
**Problem**: gsutil fails when downloading empty buckets
**Solution**: robust_download.sh checks for empty buckets and skips them

### macOS Multiprocessing Errors
**Problem**: "Exception in thread Thread-3" errors on macOS
**Solution**: All scripts use `-o "GSUtil:parallel_process_count=1"`

### Path Spaces in Environment Variables
**Problem**: Paths with spaces cause export errors
**Solution**: Use `set -a; source .env; set +a` instead of `export $(grep...)`

### Authentication Between Phases
**Problem**: Need to switch accounts between download and upload
**Solution**: Makefile includes auth-check-source and auth-check-dest

## Testing and Validation

```bash
# Test with single bucket
make test-bucket BUCKET=bucket-name

# Check current status
make status

# Verify environment setup
make check-env

# List buckets in both projects
make list-source
make list-dest
```

## Maintenance Commands

```bash
# Run lint and typecheck (if configured)
# Add these commands to CLAUDE.md when available:
# npm run lint
# npm run typecheck
```

## Security Notes

- Never commit .env files (included in .gitignore)
- Archive bucket must be created before phase3
- Requires Storage Admin role in both projects
- Credentials are managed via gcloud auth