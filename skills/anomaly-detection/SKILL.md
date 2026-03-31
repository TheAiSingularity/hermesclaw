---
name: anomaly-detection
description: Daily database anomaly detection — runs metric queries against Postgres, flags deviations > 2σ from the 7-day baseline, and sends a summary to Slack or Telegram
license: MIT
compatibility: [macOS, Linux]
user-invocable: true
metadata:
  version: 0.1.0
  author: TheAiSingularity
  tags: [data-analysis, postgres, anomaly, monitoring, cron, slack, telegram]
  requires_tools: [memory, cron]
  required_environment_variables:
    - name: DATABASE_URL
      prompt: "Your PostgreSQL connection string (postgresql://user:pass@host:5432/dbname)"
      help_url: "https://www.postgresql.org/docs/current/libpq-connect.html#LIBPQ-CONNSTRING"
---

# anomaly-detection

This skill runs daily metric queries against your Postgres database, detects statistical anomalies, and delivers a structured report to your alert channel.

## When to invoke

- Daily on a cron schedule (recommended: 7am before business hours)
- When the user asks "any anomalies today?" or "how are our metrics?"
- After a deploy, incident, or data pipeline change

## Steps to execute

1. **Load metric configuration from memory**
   - Read MEMORY.md for: metric names, SQL queries, alert thresholds (if custom), alert channel (Slack/Telegram)
   - If no metrics are configured, ask the user to provide their key metric queries

2. **Run current-period queries**
   - Execute each metric SQL query via the Postgres MCP server
   - Record: metric name, current value, query timestamp

3. **Run baseline queries**
   - For each metric, run the same query for each of the past 7 days
   - Build a 7-day array: `[d-7, d-6, d-5, d-4, d-3, d-2, d-1]`

4. **Compute statistics using the detect.py helper**
   - Pass results to `scripts/detect.py` via stdin as JSON:
     ```json
     {"metric": "daily_revenue", "current": 24150, "baseline": [24800, 23900, 25100, 24200, 23800, 24900, 24100]}
     ```
   - The script returns:
     ```json
     {"metric": "daily_revenue", "mean": 24400, "std": 422, "z_score": -0.59, "is_anomaly": false}
     ```
   - An anomaly is flagged when `|z_score| > 2.0`

5. **Build the report**
   - Summary line: "All metrics normal" or "X anomalies detected"
   - For each metric: current value, 7-day avg, % change, anomaly flag
   - For anomalies: include possible causes from the user's mental model (stored in MEMORY.md)

6. **Deliver the report**
   - Send to the configured alert channel (Slack or Telegram)
   - For anomalies: send an immediate separate alert with higher urgency

7. **Update memory**
   - Record today's values in MEMORY.md under the metric history
   - Note any anomalies and whether they were followed by a user explanation

## Example output

```
Daily Metrics — 2026-03-31 07:00

All clear — all metrics within normal range.

DAU:             8,432   (7d avg: 8,168  ↑ 3.2%)   ✅
Revenue:        $24,150  (7d avg: $24,420 ↓ 1.1%)   ✅
New signups:       312   (7d avg:    309  ↑ 1.0%)   ✅
Activation rate:  67.3%  (7d avg:  68.1% ↓ 0.8%)   ✅
```

For anomalies:
```
ANOMALY ALERT — 2026-03-31 07:00

Revenue: $15,200 (7d avg: $24,420 — z-score: −2.8) ⚠️
This is 38% below average. Possible causes:
- Payment processor issue
- Regional outage
- Recent pricing change
Check: SELECT * FROM payment_failures WHERE created_at >= CURRENT_DATE
```

## Error handling

- If Postgres MCP is unavailable: report the connection error and skip the run
- If a query fails: skip that metric, continue with others, note the failure in the report
- If the alert channel is unavailable: save report to `/sandbox/anomaly-report-[date].json`

## Notes

- Use a read-only database role for the connection string (see guide for SQL setup)
- The `scripts/detect.py` helper handles all statistical computation — no external libraries needed in the LLM
- After 30+ daily runs, Hermes will auto-create an optimized version of this skill calibrated to your metrics
