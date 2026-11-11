#!/usr/bin/env python3
"""Apply performance acceptance thresholds to a JMeter CSV results file (.jtl).

    python tools/jmeter_gate.py reports/staging/jmeter.jtl --max-error-rate 1 --max-p95-ms 500

Prints a per-label summary table (Markdown) and exits 1 when any label breaches a threshold.
Works with the default CSV output of `jmeter -n -l results.jtl`.
"""

from __future__ import annotations

import argparse
import csv
import statistics
import sys
from collections import defaultdict
from pathlib import Path


def percentile(values: list[int], pct: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    k = (len(ordered) - 1) * pct / 100
    lower = int(k)
    upper = min(lower + 1, len(ordered) - 1)
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (k - lower)


def load(path: Path) -> dict[str, dict]:
    per_label: dict[str, dict] = defaultdict(lambda: {"elapsed": [], "errors": 0, "count": 0})
    with path.open(newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        required = {"label", "elapsed", "success"}
        if reader.fieldnames is None or not required.issubset(reader.fieldnames):
            raise SystemExit(f"{path}: not a JMeter CSV results file (needs columns {sorted(required)})")
        for row in reader:
            entry = per_label[row["label"]]
            entry["count"] += 1
            entry["elapsed"].append(int(row["elapsed"]))
            if row["success"].strip().lower() != "true":
                entry["errors"] += 1
    return per_label


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("jtl", type=Path)
    parser.add_argument("--max-error-rate", type=float, default=1.0, help="max error percentage per label")
    parser.add_argument("--max-p95-ms", type=float, default=500.0, help="max p95 latency per label (ms)")
    parser.add_argument("--min-samples", type=int, default=10, help="minimum samples per label")
    args = parser.parse_args(argv)

    per_label = load(args.jtl)
    if not per_label:
        print("no samples found", file=sys.stderr)
        return 1

    print(f"Thresholds: error rate <= {args.max_error_rate}% and p95 <= {args.max_p95_ms:.0f} ms per endpoint\n")
    print("| Endpoint | Samples | Errors | Error % | Avg ms | p95 ms | p99 ms | Max ms | Verdict |")
    print("|----------|---------|--------|---------|--------|--------|--------|--------|---------|")
    breached = False
    for label, entry in sorted(per_label.items()):
        elapsed = entry["elapsed"]
        error_rate = 100.0 * entry["errors"] / entry["count"]
        p95 = percentile(elapsed, 95)
        p99 = percentile(elapsed, 99)
        problems = []
        if error_rate > args.max_error_rate:
            problems.append("errors")
        if p95 > args.max_p95_ms:
            problems.append("p95")
        if entry["count"] < args.min_samples:
            problems.append("samples")
        verdict = "PASS" if not problems else "FAIL (" + ", ".join(problems) + ")"
        breached |= bool(problems)
        print(
            f"| {label} | {entry['count']} | {entry['errors']} | {error_rate:.2f} | "
            f"{statistics.fmean(elapsed):.0f} | {p95:.0f} | {p99:.0f} | {max(elapsed)} | {verdict} |"
        )

    total = sum(e["count"] for e in per_label.values())
    errors = sum(e["errors"] for e in per_label.values())
    print(f"\nTotal: {total} samples, {errors} errors ({100.0 * errors / total:.2f}%)")
    print("RESULT: " + ("REJECTED" if breached else "ACCEPTED"))
    return 1 if breached else 0


if __name__ == "__main__":
    sys.exit(main())
