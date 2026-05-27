# Prod Trading Dashboard

Live intraday trading dashboard for algorithmic strategy monitoring.

## Architecture

```
Zerodha / Dhan feeds → Redis db=1 (market data)
Colo strategy log    → dashboard_worker_prod.py → Redis db=1 (positions)
Signal sync          → Redis db=0 (signals from colo)
Stock feeder         → Redis db=2 (lot sizes, LTP)
Redis db=1           → trading_dashboard_colo_prod_final.py (Streamlit, port 8501)
```

## Files

| File | Purpose |
|------|---------|
| `dashboard_worker_prod.py` | Reads colo log via SSH, parses fills, calculates slippage, publishes positions to Redis |
| `trading_dashboard_colo_prod_final.py` | Streamlit dashboard — reads Redis, shows positions, PnL, slippage |
| `generate_eod.py` | Runs at 3:44 PM — generates EOD CSV with overnight positions and prev_close |
| `signal_sync.py` | Syncs signals from colo Redis → local Redis db=0 every 5s |
| `dashboard_manage_prod.sh` | Start/stop/restart/status for worker + dashboard |

## Usage

```bash
# Start both services
./dashboard_manage_prod.sh start

# Stop both
./dashboard_manage_prod.sh stop

# Restart
./dashboard_manage_prod.sh restart

# Check status
./dashboard_manage_prod.sh status
```

## Dashboard KPIs

| KPI | Description |
|-----|-------------|
| NET EXPOSURE | Net open position value (Cr/L) |
| GROSS EXPOSURE | Total abs position value |
| CARRY PNL | PnL from overnight positions (qty_overnight × (LTP - prev_close)) |
| DAY PNL | PnL from today's intraday fills |
| EXPENSES | Transaction costs (negative) |
| NET PNL | CARRY + DAY - EXPENSES |
| MEDIAN SLIPPAGE | Median execution slippage in bps |

## Slippage Calculation

```
BUY:  slip = (mid_at_fill - fill_price) / mid_at_fill × 10000  bps
SELL: slip = (fill_price - mid_at_fill) / mid_at_fill × 10000  bps
Positive = good execution
```

- Mid price captured from `operator()::EXECUTION_STRATEGY_LIVE` log line just before fill
- 5-minute window: first fill defines window, all fills within 5 min use same mid
- Weighted avg: `Σ(qty_i × slip_i) / Σ(qty_i)` across all fills per symbol
- Slippage log saved to `/data/Dashboard/snapshots/slippage_log_YYYYMMDD.csv` on colo

## Cron Schedule

```
45 8  * * 1-5  refresh_tokens.sh
15 9  * * 1-5  start_feeds.sh
15 9  * * 1-5  signal_sync.py
16 9  * * 1-5  dashboard_manage_prod.sh start
16 9  * * 1-5  algo_alert_monitor_prod.py
40 15 * * 1-5  stop_feeds.sh
44 15 * * 1-5  generate_eod.py
45 15 * * 1-5  dashboard_manage_prod.sh stop
```

## Redis Layout

| DB | Owner | Key Pattern |
|----|-------|-------------|
| 0 | fo_realtime_feeder + signals | `fo:index_spot:*`, `obstrategy:signal:latest:*` |
| 1 | dashboard_worker_prod | `dashboard:positions:latest2`, `slippage:log:*` |
| 2 | stock_realtime_feeder | `fo:stock_spot:*`, `fo:stock_option:*` |

## Contract Rollover

When a futures contract expires (e.g. May → June), the worker automatically:
1. Detects EOD token not in today's token_map
2. Finds nearest active future for same symbol
3. Maps overnight position to new contract token

## Key Notes

- Slippage only calculated for **today's fills** — carry positions show `—`
- When no fills today, `qty_today_buy = 0` (yesterday's fills moved to overnight)
- Expenses display as **negative** (cost)
- `M.M` symbol from colo normalized to `M&M`
