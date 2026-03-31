#!/usr/bin/env python3
"""
anomaly-detection/scripts/detect.py

Reads metric baseline data from stdin (JSON), computes z-scores,
and outputs an anomaly report as JSON to stdout.

Usage:
    echo '{"metric": "revenue", "current": 15200, "baseline": [24800, 23900, 25100, 24200, 23800, 24900, 24100]}' \
        | python3 detect.py

    echo '{"metrics": [...]}' | python3 detect.py --batch

Input (single metric):
    {
        "metric": "metric_name",
        "current": 15200,
        "baseline": [24800, 23900, 25100, 24200, 23800, 24900, 24100]
    }

Input (batch):
    {
        "metrics": [
            {"metric": "revenue", "current": 15200, "baseline": [...]},
            {"metric": "dau", "current": 8432, "baseline": [...]}
        ]
    }

Output (single):
    {
        "metric": "revenue",
        "current": 15200,
        "mean": 24400.0,
        "std": 422.3,
        "z_score": -2.18,
        "is_anomaly": true,
        "pct_change": -37.7
    }
"""

import json
import math
import sys


def compute_stats(current: float, baseline: list) -> dict:
    if not baseline:
        return {"error": "empty baseline"}

    n = len(baseline)
    mean = sum(baseline) / n
    variance = sum((x - mean) ** 2 for x in baseline) / n
    std = math.sqrt(variance)

    if std == 0:
        z_score = 0.0
    else:
        z_score = (current - mean) / std

    pct_change = ((current - mean) / mean * 100) if mean != 0 else 0.0

    return {
        "mean": round(mean, 2),
        "std": round(std, 2),
        "z_score": round(z_score, 2),
        "is_anomaly": abs(z_score) > 2.0,
        "pct_change": round(pct_change, 1),
    }


def process_single(data: dict) -> dict:
    result = {
        "metric": data.get("metric", "unknown"),
        "current": data.get("current"),
    }
    # Accept "history" as an alias for "baseline"
    baseline = data.get("baseline") or data.get("history", [])
    stats = compute_stats(data["current"], baseline)
    result.update(stats)
    return result


def main():
    batch_mode = "--batch" in sys.argv

    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(json.dumps({"error": f"Invalid JSON input: {e}"}))
        sys.exit(1)

    # Handle bare list input: [{...}, {...}]
    if isinstance(data, list):
        results = [process_single(m) for m in data]
        anomalies = [r for r in results if r.get("is_anomaly")]
        output = {
            "results": results,
            "anomaly_count": len(anomalies),
            "anomalies": anomalies,
        }
    elif batch_mode or "metrics" in data:
        metrics = data.get("metrics", [])
        results = [process_single(m) for m in metrics]
        anomalies = [r for r in results if r.get("is_anomaly")]
        output = {
            "results": results,
            "anomaly_count": len(anomalies),
            "anomalies": anomalies,
        }
    else:
        output = process_single(data)

    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
