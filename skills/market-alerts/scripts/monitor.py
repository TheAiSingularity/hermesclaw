#!/usr/bin/env python3
"""
market-alerts/scripts/monitor.py

Parses price data and computes threshold breach status.

Usage:
    echo '{
        "watchlist": [
            {"ticker": "NVDA", "price": 823.50, "high_threshold": 950, "low_threshold": 820},
            {"ticker": "TSLA", "price": 245.00, "high_threshold": 280, "low_threshold": 220}
        ]
    }' | python3 monitor.py

Output:
    {
        "results": [
            {
                "ticker": "NVDA",
                "price": 823.50,
                "high_threshold": 950,
                "low_threshold": 820,
                "breach": "low",
                "pct_from_threshold": -0.4,
                "alert": true
            },
            {
                "ticker": "TSLA",
                "price": 245.00,
                "high_threshold": 280,
                "low_threshold": 220,
                "breach": null,
                "pct_from_threshold": null,
                "alert": false
            }
        ],
        "alert_count": 1,
        "alerts": [...]
    }
"""

import json
import sys


def check_thresholds(ticker: str, price: float, high: float, low: float) -> dict:
    result = {
        "ticker": ticker,
        "price": price,
        "high_threshold": high,
        "low_threshold": low,
        "breach": None,
        "pct_from_threshold": None,
        "alert": False,
    }

    if price >= high:
        pct = (price - high) / high * 100
        result["breach"] = "high"
        result["pct_from_threshold"] = round(pct, 2)
        result["alert"] = True
    elif price <= low:
        pct = (price - low) / low * 100
        result["breach"] = "low"
        result["pct_from_threshold"] = round(pct, 2)
        result["alert"] = True

    return result


def main():
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(json.dumps({"error": f"Invalid JSON input: {e}"}))
        sys.exit(1)

    watchlist = data.get("watchlist", [])
    results = []

    for item in watchlist:
        ticker = item.get("ticker", "UNKNOWN")
        price = item.get("price")
        high = item.get("high_threshold")
        low = item.get("low_threshold")

        if price is None or high is None or low is None:
            results.append({"ticker": ticker, "error": "missing price or threshold data"})
            continue

        results.append(check_thresholds(ticker, float(price), float(high), float(low)))

    alerts = [r for r in results if r.get("alert")]
    output = {
        "results": results,
        "alert_count": len(alerts),
        "alerts": alerts,
    }

    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
