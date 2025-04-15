#!/bin/bash

# Exit on any error
set -eu

# Check required parameters
if [ -z "${1:-}" ]; then
    echo "Run a job from a cronjob"
    echo "Usage: $0 <cronjobe> <timeout> <cronjob_tail>"
    exit 1
fi

# Vars and defaults
CRONJOB="$1"
TIMEOUT="${2:-10m}"
CRONJOB_TAIL="${3:-1}"

# Create timestamped job name
JOB_NAME="${CRONJOB}--$(date +"%Y-%m-%d--%H-%M-%S")"

# Create the job from cronjob
oc create job ${JOB_NAME} --from=cronjob/${CRONJOB}

# Wait for status=ready|completed - oc wait fails for overly quick jobs
timeout ${TIMEOUT} bash -c "
while true; do
  oc get pods -l job-name=${JOB_NAME} --no-headers | awk '{print \$3}' | grep -qi 'running\|completed' && break
  sleep 5
done" || { echo "Timeout waiting for job to start"; exit 1; }

# Follow logs
echo -e "\n\n--- Start logs for job ${JOB_NAME} ---"
oc logs -l job-name=${JOB_NAME} --follow --tail=${CRONJOB_TAIL}
echo -e "--- End logs ---\n\n"

# Set output for GitHub Actions
if [ -n "$GITHUB_OUTPUT" ]; then
    echo "job-name=${JOB_NAME}" >> $GITHUB_OUTPUT
fi

echo "Job successful!"
