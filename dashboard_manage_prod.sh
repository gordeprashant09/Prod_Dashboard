#!/bin/bash
# dashboard_manage_prod.sh
# ========================
# Manages dashboard_worker_prod.py and trading_dashboard_colo_prod_final.py
# Usage:
#   ./dashboard_manage_prod.sh start   — start both (weekdays only)
#   ./dashboard_manage_prod.sh stop    — stop both
#   ./dashboard_manage_prod.sh restart — restart both
#   ./dashboard_manage_prod.sh status  — check if running
#
# Cron setup (add via crontab -e):
#   30 8  * * 1-5  /home/report/devstudio/Prashant/Live_Dashboard/Prod/dashboard_manage_prod.sh start
#   0  16 * * 1-5  /home/report/devstudio/Prashant/Live_Dashboard/Prod/dashboard_manage_prod.sh stop
#   @reboot        /home/report/devstudio/Prashant/Live_Dashboard/Prod/dashboard_manage_prod.sh start

# ── CONFIG ────────────────────────────────────────────────────
BASE_DIR="/home/report/devstudio/Prashant/Live_Dashboard/Prod"
VENV_PYTHON="/home/report/devstudio/Prashant/Live_Dashboard/venv/bin/python3"
STREAMLIT="/home/report/devstudio/Prashant/Live_Dashboard/venv/bin/streamlit"
WORKER_SCRIPT="$BASE_DIR/dashboard_worker_prod.py"
DASHBOARD_SCRIPT="$BASE_DIR/trading_dashboard_colo_prod_final.py"
WORKER_LOG="$BASE_DIR/worker_prod.log"
DASHBOARD_LOG="$BASE_DIR/dashboard_prod.log"
STREAMLIT_PORT=8501

# ── HELPERS ───────────────────────────────────────────────────
is_weekday() {
    day=$(date +%u)  # 1=Mon ... 7=Sun
    [ "$day" -le 5 ]
}

is_running() {
    pgrep -f "$1" > /dev/null 2>&1
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# ── START ─────────────────────────────────────────────────────
start() {
    if ! is_weekday; then
        log "Today is weekend — skipping start"
        exit 0
    fi

    log "=== Starting Prod Dashboard Services ==="

    # Start worker
    if is_running "dashboard_worker_prod.py"; then
        log "Worker already running (PID=$(pgrep -f dashboard_worker_prod.py))"
    else
        log "Starting dashboard_worker_prod.py..."
        cd "$BASE_DIR"
        nohup "$VENV_PYTHON" "$WORKER_SCRIPT" >> "$WORKER_LOG" 2>&1 &
        sleep 2
        if is_running "dashboard_worker_prod.py"; then
            log "Worker started (PID=$(pgrep -f dashboard_worker_prod.py)) ✅"
        else
            log "Worker failed to start ❌ — check $WORKER_LOG"
        fi
    fi

    # Start dashboard
    if is_running "trading_dashboard_colo_prod_final.py"; then
        log "Dashboard already running (PID=$(pgrep -f trading_dashboard_colo_prod_final.py))"
    else
        log "Starting trading_dashboard_colo_prod_final.py on port $STREAMLIT_PORT..."
        cd "$BASE_DIR"
        nohup "$STREAMLIT" run "$DASHBOARD_SCRIPT" \
            --server.port "$STREAMLIT_PORT" \
            --server.headless true \
            >> "$DASHBOARD_LOG" 2>&1 &
        sleep 3
        if is_running "trading_dashboard_colo_prod_final.py"; then
            log "Dashboard started (PID=$(pgrep -f trading_dashboard_colo_prod_final.py)) ✅"
            log "Access at: http://localhost:$STREAMLIT_PORT"
        else
            log "Dashboard failed to start ❌ — check $DASHBOARD_LOG"
        fi
    fi

    log "=== Start complete ==="
}

# ── STOP ──────────────────────────────────────────────────────
stop() {
    log "=== Stopping Prod Dashboard Services ==="

    if is_running "dashboard_worker_prod.py"; then
        pkill -f "dashboard_worker_prod.py"
        log "Worker stopped ✅"
    else
        log "Worker was not running"
    fi

    if is_running "trading_dashboard_colo_prod_final.py"; then
        pkill -f "trading_dashboard_colo_prod_final.py"
        log "Dashboard stopped ✅"
    else
        log "Dashboard was not running"
    fi

    log "=== Stop complete ==="
}

# ── RESTART ───────────────────────────────────────────────────
restart() {
    log "=== Restarting Prod Dashboard Services ==="
    stop
    sleep 3
    # bypass weekday check on restart
    cd "$BASE_DIR"
    nohup "$VENV_PYTHON" "$WORKER_SCRIPT" >> "$WORKER_LOG" 2>&1 &
    sleep 2
    nohup "$STREAMLIT" run "$DASHBOARD_SCRIPT" \
        --server.port "$STREAMLIT_PORT" \
        --server.headless true \
        >> "$DASHBOARD_LOG" 2>&1 &
    sleep 3
    status
}

# ── STATUS ────────────────────────────────────────────────────
status() {
    log "=== Prod Dashboard Services Status ==="
    if is_running "dashboard_worker_prod.py"; then
        log "Worker    : RUNNING (PID=$(pgrep -f dashboard_worker_prod.py)) ✅"
    else
        log "Worker    : STOPPED ❌"
    fi

    if is_running "trading_dashboard_colo_prod_final.py"; then
        log "Dashboard : RUNNING (PID=$(pgrep -f trading_dashboard_colo_prod_final.py)) ✅"
        log "URL       : http://localhost:$STREAMLIT_PORT"
    else
        log "Dashboard : STOPPED ❌"
    fi
}

# ── MAIN ──────────────────────────────────────────────────────
case "$1" in
    start)   start ;;
    stop)    stop ;;
    restart) restart ;;
    status)  status ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
