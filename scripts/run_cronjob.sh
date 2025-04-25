#!/bin/bash

# Strict error handling
set -euo pipefail

# Logging functions
log_info() { echo "INFO: [$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
log_error() { echo "ERROR: [$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2; }
log_debug() { [[ "${DEBUG:-false}" == "true" ]] && echo "DEBUG: [$(date +'%Y-%m-%d %H:%M:%S')] $*"; }

# Cleanup function
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Script failed with exit code $exit_code"
    fi
    exit $exit_code
}
trap cleanup EXIT

# Input validation
if [ -z "${1:-}" ]; then
    echo "Run a job from a cronjob"
    echo "Usage: $0 <cronjobe> <timeout> <cronjob_tail>"
    exit 1
fi

# Vars and defaults
CRONJOB="$1"
TIMEOUT="${2:-10m}"
CRONJOB_TAIL="${3:-1}"

# Validate OpenShift CLI
if ! command -v oc &> /dev/null; then
    log_error "OpenShift CLI (oc) not found"
    exit 1
fi

# Create timestamped job name
JOB_NAME="${CRONJOB}--$(date +"%Y-%m-%d--%H-%M-%S")"
log_info "Creating job: ${JOB_NAME}"

# Create the job from cronjob
if ! oc create job "${JOB_NAME}" --from="cronjob/${CRONJOB}"; then
    log_error "Failed to create job from cronjob"
    exit 1
fi

# Wait for status=ready|completed - oc wait fails for overly quick jobs
log_info "Waiting for job ${JOB_NAME} to start"
timeout "${TIMEOUT}" bash -c "
while true; do
  oc get pods -l job-name=${JOB_NAME} --no-headers | awk '{print \$3}' | grep -qi 'running\|completed' && break
  sleep 5
done" || { log_error "Timeout waiting for job to start"; exit 1; }

# Follow logs
log_info "Starting log stream for job ${JOB_NAME}"
if ! oc logs -l "job-name=${JOB_NAME}" --follow --tail="${CRONJOB_TAIL}"; then
    log_error "Failed to retrieve logs"
    exit 1
fi
log_info "Log stream completed"

# Check job status
if ! oc get job "${JOB_NAME}" -o jsonpath='{.status.succeeded}' | grep -q "1"; then
    log_error "Job did not complete successfully"
    exit 1
fi

# Set output for GitHub Actions
if [ -n "$GITHUB_OUTPUT" ]; then
    echo "job-name=${JOB_NAME}" >> $GITHUB_OUTPUT
fi

log_info "Job successful!"
