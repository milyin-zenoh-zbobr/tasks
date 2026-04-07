#!/usr/bin/env sh
set -eu

ZBOBR_CMD="${ZBOBR_CMD:-zbobr}"
ZBOBR_LOOP_CMD="${ZBOBR_LOOP_CMD:-true}"
ZBOBR_LOOP_INTERVAL="${ZBOBR_LOOP_INTERVAL:-60}"
ZBOBR_CLEANUP_INTERVAL="${ZBOBR_CLEANUP_INTERVAL:-600}"

last_cleanup_ts="$(date +%s)"

while sh -c "$ZBOBR_LOOP_CMD"; do
    eval "$ZBOBR_CMD task advance"

    if eval "$ZBOBR_CMD task process --select"; then
        :
    else
        rc="$?"
        if [ "$rc" -ne 1 ]; then
            echo "task process --select failed with exit code $rc" >&2
            exit "$rc"
        fi
    fi

    now_ts="$(date +%s)"
    if [ $((now_ts - last_cleanup_ts)) -ge "$ZBOBR_CLEANUP_INTERVAL" ]; then
        if ! eval "$ZBOBR_CMD cleanup"; then
            echo "warning: cleanup failed" >&2
        fi
        last_cleanup_ts="$now_ts"
    fi

    sleep "$ZBOBR_LOOP_INTERVAL"
done
