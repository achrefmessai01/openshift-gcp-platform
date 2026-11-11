#!/usr/bin/env python3
"""Run the Robot Framework acceptance suites and write the acceptance record
(procès-verbal de recette) as Markdown and JSON.

    python tools/acceptance.py --base-url https://subscriber-api-dev.apps.ocp.example.com \
        --env dev --api-key "$API_KEY" --include smoke --include functional

Outputs (default: reports/<env>/):
    acceptance-<env>-<timestamp>.md     human-readable record, one line per test id
    acceptance-<env>-<timestamp>.json   machine-readable record
    output.xml / log.html / report.html / xunit.xml   native Robot artefacts

Exit code: 0 when every executed test passed, 1 otherwise, 2 on usage errors.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import UTC, datetime
from pathlib import Path

from robot import run as robot_run
from robot.api import ExecutionResult

ROOT = Path(__file__).resolve().parent.parent
SUITES = ROOT / "tests" / "robot"
TEST_ID = re.compile(r"^(R[A-Z]-\d{3})\b")


def parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base-url", default="http://localhost:8080", help="application base URL")
    parser.add_argument("--env", default="local", help="environment label written into the record")
    parser.add_argument("--api-key", default="", help="X-API-Key for write operations")
    parser.add_argument("--expected-env", default="", help="APP_ENV the target must report (RT-003)")
    parser.add_argument("--route-host", default="", help="Route hostname for platform tests (RP-00x)")
    parser.add_argument("--api-url", default="", help="OpenShift API URL for platform tests (RP-01x)")
    parser.add_argument("--include", action="append", default=[], help="tag to include (repeatable)")
    parser.add_argument("--exclude", action="append", default=[], help="tag to exclude (repeatable)")
    parser.add_argument("--suite", action="append", default=[], help="suite path(s); default tests/robot")
    parser.add_argument("--out", default=None, help="output directory (default reports/<env>)")
    parser.add_argument("--no-verify-tls", action="store_true", help="skip TLS verification (self-signed)")
    return parser.parse_args(argv)


def run_robot(args: argparse.Namespace, outdir: Path) -> int:
    variables = [
        f"BASE_URL:{args.base_url}",
        f"API_KEY:{args.api_key}",
        f"EXPECTED_ENV:{args.expected_env}",
        f"ROUTE_HOST:{args.route_host}",
        f"API_URL:{args.api_url}",
        f"VERIFY_TLS:{'False' if args.no_verify_tls else 'True'}",
    ]
    suites = [str(Path(s)) for s in args.suite] or [str(SUITES)]
    return robot_run(
        *suites,
        outputdir=str(outdir),
        output="output.xml",
        log="log.html",
        report="report.html",
        xunit="xunit.xml",
        variable=variables,
        include=args.include or None,
        exclude=args.exclude or None,
        loglevel="INFO",
        consolecolors="off",
        name=f"Acceptance {args.env}",
    )


def collect(outdir: Path, env: str, base_url: str) -> dict:
    result = ExecutionResult(str(outdir / "output.xml"))
    tests = []

    def visit(suite) -> None:
        for test in suite.tests:
            match = TEST_ID.match(test.name)
            tests.append(
                {
                    "id": match.group(1) if match else "",
                    "name": test.name,
                    "suite": suite.name,
                    "tags": sorted(test.tags),
                    "status": test.status,
                    "elapsed_s": round(test.elapsed_time.total_seconds(), 2),
                    "message": test.message,
                }
            )
        for child in suite.suites:
            visit(child)

    visit(result.suite)
    stats = result.statistics.total
    return {
        "environment": env,
        "base_url": base_url,
        "executed_at": datetime.now(tz=UTC).isoformat(timespec="seconds"),
        "robot_version": result.generator,
        "summary": {
            "total": stats.total,
            "passed": stats.passed,
            "failed": stats.failed,
            "skipped": stats.skipped,
            "verdict": "ACCEPTED" if stats.failed == 0 and stats.passed > 0 else "REJECTED",
        },
        "tests": tests,
    }


def to_markdown(record: dict) -> str:
    s = record["summary"]
    lines = [
        f"# Acceptance record — {record['environment']}",
        "",
        f"- Target: `{record['base_url']}`",
        f"- Executed: {record['executed_at']}",
        f"- Generator: {record['robot_version']}",
        f"- Result: **{s['verdict']}** ({s['passed']} passed, {s['failed']} failed, "
        f"{s['skipped']} skipped, {s['total']} total)",
        "",
        "| ID | Test | Tags | Status | Time (s) | Message |",
        "|----|------|------|--------|----------|---------|",
    ]
    for t in record["tests"]:
        message = t["message"].replace("|", "\\|").replace("\n", " ")
        lines.append(
            f"| {t['id']} | {t['name']} | {', '.join(t['tags'])} | {t['status']} | {t['elapsed_s']} | {message} |"
        )
    lines += [
        "",
        "Sign-off (name / date / decision): ________________________________",
        "",
    ]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    outdir = Path(args.out) if args.out else ROOT / "reports" / args.env
    outdir.mkdir(parents=True, exist_ok=True)

    rc = run_robot(args, outdir)
    if not (outdir / "output.xml").exists():
        print("robot produced no output.xml (usage error?)", file=sys.stderr)
        return 2

    record = collect(outdir, args.env, args.base_url)
    stamp = datetime.now(tz=UTC).strftime("%Y%m%dT%H%M%SZ")
    md_path = outdir / f"acceptance-{args.env}-{stamp}.md"
    json_path = outdir / f"acceptance-{args.env}-{stamp}.json"
    md_path.write_text(to_markdown(record), encoding="utf-8", newline="\n")
    json_path.write_text(json.dumps(record, indent=2), encoding="utf-8", newline="\n")

    s = record["summary"]
    print(f"\n{s['verdict']}: {s['passed']} passed, {s['failed']} failed, {s['skipped']} skipped")
    print(f"record: {md_path}")
    return 0 if rc == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
