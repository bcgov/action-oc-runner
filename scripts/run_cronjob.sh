#!/bin/bash

# Strict error handling
set -euo pipefail
IFS=$'\n\t'

# Logging functions
log_info() { echo "INFO: [$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
log_error() { echo "ERROR: [$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2; }
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
check_job_status() {
    local retry_count=0
    while [ $retry_count -lt $MAX_RETRIES ]; do
        local status=$(oc get job "${JOB_NAME}" -o json)
        local succeeded=$(echo "$status" | jq -r '.status.succeeded // 0')
        local failed=$(echo "$status" | jq -r '.status.failed // 0')
        local active=$(echo "$status" | jq -r '.status.active // 0')

        log_debug "Job status: succeeded=$succeeded, failed=$failed, active=$active"

        if [ "$succeeded" = "1" ]; then
            return 0
        elif [ "$failed" = "1" ]; then
            return 1
        fi

        retry_count=$((retry_count + 1))
        [ $retry_count -lt $MAX_RETRIES ] && sleep 2
    done
    return 1
}

check_job_status || { log_error "Job status check failed after $MAX_RETRIES attempts"; exit 1; }

# Handle GitHub Actions output
set_github_output() {
    local name="$1"
    local value="$2"
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        echo "${name}=${value}" >> "$GITHUB_OUTPUT"
        log_debug "Set GitHub output ${name}=${value}"
    else
        log_debug "GITHUB_OUTPUT not set, skipping output generation"
    fi
}

# Set the job name as output
set_github_output "job-name" "${JOB_NAME}"

log_info "Job successful!"
