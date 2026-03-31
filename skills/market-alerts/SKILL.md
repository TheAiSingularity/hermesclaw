---
name: market-alerts
description: Market price monitoring and alerts — checks your watchlist against thresholds, sends Telegram alerts on breaches, generates daily pre-market briefings, and tracks trade notes in memory
license: MIT
compatibility: [macOS, Linux, Windows]
user-invocable: true
metadata:
  version: 0.1.0
  author: TheAiSingularity
  tags: [trading, finance, alerts, telegram, cron, monitoring]
  requires_tools: [web_search, web_extract, memory, cron]
  required_environment_variables:
    - name: TELEGRAM_BOT_TOKEN
      prompt: "Your Telegram bot token (from @BotFather)"
      help_url: "https://core.telegram.org/bots/tutorial"
---

# market-alerts

This skill monitors your watchlist for price threshold breaches, sends Telegram alerts, and generates daily pre-market briefings. Trade notes and strategy observations are stored in MEMORY.md for future reference.

## When to invoke

- On a cron schedule during market hours (every 15 minutes, 9:30am–4pm ET)
- For daily pre-market briefing (9:25am ET weekdays)
- When the user explicitly asks to check their watchlist
- When the user wants to record a trade note

## Steps to execute

### Mode 1: Real-time monitoring check (cron)

1. **Load watchlist and thresholds from memory**
   - Read MEMORY.md for: ticker symbols, alert thresholds (high/low per ticker), alert preferences
   - If no watchlist is configured, ask the user to set one before proceeding

2. **Fetch current prices**
   - Use `web_extract` to get current prices for each ticker
   - Preferred sources: finance.yahoo.com, Google Finance, or similar public price feeds
   - Use `scripts/monitor.py` to parse price data and compute threshold status

3. **Check thresholds**
   - For each ticker: compare current price to high and low thresholds
   - A breach = price is above high threshold OR below low threshold

4. **Send Telegram alert on breach**
   - Alert format: see Output Format section below
   - Include: ticker, current price, threshold breached, % from threshold, relevant context from MEMORY.md (e.g., "your thesis was X", "last time this happened Y")
   - Do NOT send duplicate alerts for the same breach within 60 minutes (track in memory)

5. **Update memory**
   - Record last check timestamp and prices in MEMORY.md
   - Track breach history

### Mode 2: Pre-market briefing

1. Fetch pre-market prices for all watchlist tickers
2. Fetch overnight/morning news relevant to each ticker (via `web_search`)
3. Check MEMORY.md for any open position notes or pending thesis items
4. Generate structured briefing (see Output Format)
5. Send to Telegram

### Mode 3: Record trade note

When the user says "record trade" or "save my thesis":
1. Extract: ticker, direction (long/short), entry price, thesis, target, stop
2. Save to MEMORY.md under "Trade journal"
3. Confirm to user

## Output format

**Threshold breach alert:**
```
ALERT — [TICKER] [direction] breach
[TIME]

[TICKER]: $[PRICE] ([+/-]%% from threshold)
Your [high/low] threshold: $[THRESHOLD]

From your notes: [relevant trade context from MEMORY.md, if any]

RSI/momentum context: [brief technical note from web data if available]
```

**Pre-market briefing:**
```
Pre-market — [DATE] [TIME]

[TICKER]: $[PRE-MKT PRICE] ([+/-]%% vs yesterday)
  Context: [1-line news or catalyst]

[TICKER]: ...

Open positions from your notes:
• [TICKER] long entry $[X] — [brief thesis]

Today's macro: [1-2 sentences on scheduled events: FOMC, jobs data, earnings]
```

**Trade note confirmation:**
```
Trade recorded:
[TICKER] [LONG/SHORT] | Entry: $[X] | Target: $[Y] | Stop: $[Z]
Thesis: [summary]
```

## Error handling

- If price fetch fails for a ticker: skip it, note in output, retry next cycle
- If Telegram delivery fails: save alert to `/sandbox/alert-[timestamp].txt`
- If all price sources are unreachable: log the failure and stop the cron check gracefully

## Notes

- This skill is for monitoring and analysis only — it does not place orders
- Never store API keys or brokerage credentials in memory
- The `scripts/monitor.py` helper handles price parsing and threshold comparison as JSON — no fragile string parsing in the LLM
- After 3 months of use, Hermes will auto-create a personalized `MarketAlert` skill that knows your trading style and typical reaction patterns
