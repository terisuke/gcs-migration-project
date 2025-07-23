# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Google Cloud Storage (GCS) migration tool that transfers data between two GCP projects:
- **Source**: `yolov8environment` project (managed by cor-jp.com)
- **Destination**: `u-dake` project (managed by u-dake.com)

The project consists of shell scripts that handle a three-phase migration process due to different Google account ownership.

## Key Commands

### Testing Scripts
```bash
# Make scripts executable
chmod +x phase1_download.sh phase2_archive.sh phase3_upload.sh advanced_restore.sh

# Dry run or test individual functions (scripts don't have built-in test mode)
# Test by running with modified LOCAL_DOWNLOAD_DIR or commenting out actual operations
```

### Running the Migration
```bash
# Phase 1: Download (requires cor-jp.com account)
gcloud auth login company@cor-jp.com
./phase1_download.sh

# Phase 2: Archive (local operation)
./phase2_archive.sh

# Phase 3: Upload (requires u-dake.com account)
gcloud auth login company@u-dake.com
./phase3_upload.sh
```

### Validation Commands
```bash
# Check current gcloud authentication
gcloud auth list

# List buckets in source project
gcloud storage buckets list --project=yolov8environment

# List buckets in destination project
gcloud storage buckets list --project=u-dake

# Check disk space before running
df -h
```

## Architecture and Code Structure

### Migration Flow
1. **phase1_download.sh**: Downloads all GCS buckets from yolov8environment to local storage
   - Creates timestamped backup directory
   - Uses gsutil parallel downloads (-m flag)
   - Logs progress to download_progress.log
   - Handles errors gracefully with continue-on-error approach

2. **phase2_archive.sh**: Creates compressed archive of downloaded data
   - Offers compression options (none, standard, maximum)
   - Calculates checksums for verification
   - Provides size estimates before archiving

3. **phase3_upload.sh**: Uploads archive to u-dake project
   - Supports parallel composite uploads for large files
   - Targets 'archive' bucket by default
   - Includes retry logic for network interruptions

4. **advanced_restore.sh**: Interactive restoration tool
   - Allows selective restoration of specific buckets
   - Can restore to different project/location
   - Includes preview mode for safety

### Key Implementation Details

- **Error Handling**: All scripts use `set -euo pipefail` for strict error handling
- **Logging**: Color-coded output with log functions (log_info, log_warn, log_error)
- **Progress Tracking**: Phase 1 creates download_progress.log for resumability
- **Large File Support**: Uses gsutil parallel composite upload for files >150MB
- **Authentication**: Requires manual gcloud auth login between phases due to account separation

### Important Paths and Variables
- Default download location: `/Users/teradakousuke/Library/Mobile Documents/com~apple~CloudDocs/Cor.inc/U-DAKE/GCS`
- Archive naming: `yolov8environment_backup_YYYYMMDD_HHMMSS.tar.gz`
- Target bucket in u-dake: `gs://archive/`

## Development Guidelines

### Script Modifications
- Maintain the three-phase separation due to authentication requirements
- Preserve color-coded logging for user clarity
- Keep interactive prompts for destructive operations
- Test with small buckets first before full migration

### Common Issues
- **Disk Space**: Ensure 2x data size available (original + archive)
- **Authentication**: Must switch accounts between Phase 1 and Phase 3
- **Network**: Large transfers may timeout - scripts include retry logic
- **Permissions**: Requires Storage Admin role in both projects