#!/usr/bin/env bash
# Pull the deploy branch, sync dependencies, restart the service, check /health.
# Release a version from your machine with: git push origin main:deploy
# Called by the webhook receiver (see hooks.json) or by hand: sudo -u iicu-mcp ./deploy.sh
#
# The body lives in main() so bash has read the whole script before `git pull`
# can replace this file underneath it.
set -euo pipefail

main() {
    local repo_dir="${IICU_REPO_DIR:-/opt/intervals-icu-mcp}"
    local branch="${IICU_BRANCH:-deploy}"
    local service="${IICU_SERVICE:-intervals-icu-mcp}"
    local port="${IICU_PORT:-8000}"

    # One deploy at a time; a second webhook during a running deploy just waits.
    exec 9>"${repo_dir}/.git/deploy.lock"
    flock 9

    cd "$repo_dir"
    git fetch --quiet origin "$branch"
    if [[ "$(git rev-parse HEAD)" == "$(git rev-parse "origin/${branch}")" ]]; then
        echo "deploy: already at $(git rev-parse --short HEAD), nothing to do"
        return 0
    fi

    git pull --ff-only --quiet origin "$branch"
    uv sync --frozen --no-dev
    sudo /usr/bin/systemctl restart "$service"

    # Give the server a moment, then probe the same /health route the Docker image uses.
    for _ in 1 2 3 4 5; do
        sleep 2
        if .venv/bin/python -m intervals_icu_mcp.healthcheck --host 127.0.0.1 --port "$port"; then
            echo "deploy: now at $(git rev-parse --short HEAD), healthy"
            return 0
        fi
    done
    echo "deploy: $(git rev-parse --short HEAD) deployed but /health failed" >&2
    return 1
}

main "$@"
