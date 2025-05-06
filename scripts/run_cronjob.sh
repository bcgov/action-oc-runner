#!/bin/bash

set -euo pipefail

# Enhanced logging functions with timestamps
log_info() { echo "INFO: [$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
log_error() { echo "ERROR: [$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2; }
log_warn() { echo "WARN: [$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2; }
log_success() { echo "SUCCESS: [$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
log_debug() { [[ "${DEBUG:-false}" == "true" ]] && echo "DEBUG: [$(date +'%Y-%m-%d %H:%M:%S')] $*"; }

MAX_RETRIES=3  # Number of times to retry job status check

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
    echo "Usage: $0 <cronjob> <timeout> <cronjob_tail>"
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

# Enhanced job status checking with exponential backoff
check_job_status() {
    local retry_count=0
    local wait_time=2

    # Initial delay to allow job status to update
    sleep 3

    while [ $retry_count -lt $MAX_RETRIES ]; do
        local status=$(oc get job "${JOB_NAME}" -o json)
        local succeeded=$(echo "$status" | jq -r '.status.succeeded // 0')
        local failed=$(echo "$status" | jq -r '.status.failed // 0')
        local active=$(echo "$status" | jq -r '.status.active // 0')
        local conditions=$(echo "$status" | jq -r '.status.conditions // []')

        log_debug "Job status check attempt $((retry_count + 1)): succeeded=$succeeded, failed=$failed, active=$active"

        if [ "$succeeded" = "1" ]; then
            log_success "Job completed successfully"
            return 0
        elif [ "$failed" = "1" ]; then
            log_error "Job failed with status: failed=$failed"
            oc describe job "${JOB_NAME}"
            return 1
        elif [ "$active" = "1" ]; then
            log_info "Job is still running..."
        else
            log_warn "Job status unclear, will retry..."
        fi

        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $MAX_RETRIES ]; then
            # Exponential backoff with maximum of 10 seconds
            wait_time=$(( wait_time * 2 ))
            [ $wait_time -gt 10 ] && wait_time=10
            log_info "Waiting ${wait_time} seconds before next check..."
            sleep $wait_time
        fi
    done

    log_error "Job status could not be determined after $MAX_RETRIES attempts"
    oc describe job "${JOB_NAME}"
    return 1
}

check_job_status || { log_error "Job status check failed after $MAX_RETRIES attempts"; exit 1; }

# Set GitHub Actions output if necessary
if [ -n "$GITHUB_OUTPUT" ]; then
    echo "job-name=${JOB_NAME}" >> $GITHUB_OUTPUT
fi

log_info "Job successful!"
