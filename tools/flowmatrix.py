#!/usr/bin/env python3
"""Flow matrix tooling.

The flow matrix (docs/flow-matrix.yaml) is both the reviewed network document and the input
of the Terraform firewall module. This tool keeps the two consistent:

    python tools/flowmatrix.py validate            # schema, CIDRs, aliases, unique ids, ports
    python tools/flowmatrix.py render              # (re)generate docs/flow-matrix.md
    python tools/flowmatrix.py check               # fail if docs/flow-matrix.md is out of date

Only PyYAML is required.
"""

from __future__ import annotations

import argparse
import ipaddress
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_YAML = ROOT / "docs" / "flow-matrix.yaml"
DEFAULT_MD = ROOT / "docs" / "flow-matrix.md"

ID_RE = re.compile(r"^FW-\d{3}$")
NAME_RE = re.compile(r"^[a-z][a-z0-9-]{1,30}$")
PORT_RE = re.compile(r"^(\d{1,5})(?:-(\d{1,5}))?$")
PROTOCOLS = {"tcp", "udp", "icmp", "esp", "ah", "sctp", "ipip", "all"}
DIRECTIONS = {"INGRESS", "EGRESS"}
ACTIONS = {"allow", "deny"}
REQUIRED = {"id", "name", "description", "direction", "source", "destination", "rules", "justification"}


class MatrixError(Exception):
    pass


def load(path: Path) -> dict:
    with path.open(encoding="utf-8") as fh:
        data = yaml.safe_load(fh)
    if not isinstance(data, dict) or "flows" not in data:
        raise MatrixError(f"{path}: expected a mapping with a 'flows' list")
    return data


def _check_endpoint(value: str, aliases: set[str], where: str) -> None:
    if value in aliases:
        return
    try:
        ipaddress.ip_network(value, strict=True)
    except ValueError as exc:
        raise MatrixError(f"{where}: '{value}' is neither a declared alias nor a valid CIDR") from exc


def _check_port(port: str, where: str) -> None:
    match = PORT_RE.match(str(port))
    if not match:
        raise MatrixError(f"{where}: invalid port spec '{port}'")
    low = int(match.group(1))
    high = int(match.group(2) or low)
    if not (1 <= low <= 65535 and low <= high <= 65535):
        raise MatrixError(f"{where}: port range '{port}' out of bounds")


def validate(data: dict) -> list[str]:
    """Return a list of human-readable facts; raise MatrixError on the first violation."""
    aliases = set((data.get("aliases") or {}).keys())
    flows = data["flows"]
    if not isinstance(flows, list) or not flows:
        raise MatrixError("'flows' must be a non-empty list")

    seen: set[str] = set()
    for idx, flow in enumerate(flows):
        where = f"flows[{idx}]"
        if not isinstance(flow, dict):
            raise MatrixError(f"{where}: must be a mapping")
        missing = REQUIRED - flow.keys()
        if missing:
            raise MatrixError(f"{where}: missing keys {sorted(missing)}")
        fid = flow["id"]
        where = fid
        if not ID_RE.match(fid):
            raise MatrixError(f"{where}: id must look like FW-001")
        if fid in seen:
            raise MatrixError(f"{where}: duplicate id")
        seen.add(fid)
        if not NAME_RE.match(flow["name"]):
            raise MatrixError(f"{where}: name must be a short lowercase slug")
        if flow["direction"] not in DIRECTIONS:
            raise MatrixError(f"{where}: direction must be INGRESS or EGRESS")
        if flow.get("action", "allow") not in ACTIONS:
            raise MatrixError(f"{where}: action must be allow or deny")
        priority = flow.get("priority", 1000)
        if not isinstance(priority, int) or not 0 <= priority <= 65535:
            raise MatrixError(f"{where}: priority must be an integer between 0 and 65535")
        for key in ("source", "destination"):
            values = flow[key]
            if not isinstance(values, list) or not values:
                raise MatrixError(f"{where}: {key} must be a non-empty list")
            for value in values:
                _check_endpoint(str(value), aliases, f"{where}.{key}")
        rules = flow["rules"]
        if not isinstance(rules, list) or not rules:
            raise MatrixError(f"{where}: rules must be a non-empty list")
        for rule in rules:
            proto = str(rule.get("protocol", "")).lower()
            if proto not in PROTOCOLS:
                raise MatrixError(f"{where}: unknown protocol '{proto}'")
            ports = rule.get("ports")
            if ports is not None:
                if proto not in {"tcp", "udp", "sctp"}:
                    raise MatrixError(f"{where}: ports are only valid with tcp/udp/sctp (got {proto})")
                for port in ports:
                    _check_port(str(port), where)

    facts = [
        f"{len(flows)} flows",
        f"{sum(1 for f in flows if f['direction'] == 'INGRESS')} ingress",
        f"{sum(1 for f in flows if f['direction'] == 'EGRESS')} egress",
        f"{sum(1 for f in flows if f.get('action', 'allow') == 'deny')} deny",
        f"{sum(1 for f in flows if f.get('logging'))} logged",
    ]
    return facts


def _fmt_rules(rules: list[dict]) -> str:
    parts = []
    for rule in rules:
        proto = str(rule["protocol"]).lower()
        ports = rule.get("ports")
        parts.append(f"{proto} {', '.join(str(p) for p in ports)}" if ports else proto)
    return "<br>".join(parts)


def render(data: dict) -> str:
    meta = data.get("metadata") or {}
    aliases = data.get("aliases") or {}
    flows = data["flows"]
    lines = [
        "# Flow matrix (matrice de flux)",
        "",
        "> Generated from `docs/flow-matrix.yaml` by `python tools/flowmatrix.py render`. Do not edit by hand.",
        "",
        f"- Platform: **{meta.get('platform', 'n/a')}**",
        f"- Owner: {meta.get('owner', 'n/a')}",
        f"- Last review: {meta.get('reviewed', 'n/a')}",
        "",
        "## Zones",
        "",
        "| Alias | Meaning |",
        "|-------|---------|",
    ]
    lines += [f"| `{alias}` | {desc} |" for alias, desc in aliases.items()]
    lines += [
        "",
        "## Flows",
        "",
        "Each line is implemented as one VPC firewall rule named `<prefix>-<id>-<name>`.",
        "",
        "| ID | Name | Dir | Action | Prio | Source | Destination | Protocol / ports | Log "
        "| Description | Justification |",
        "|----|------|-----|--------|------|--------|-------------|------------------|-----"
        "|-------------|---------------|",
    ]
    row = "| {id} | `{name}` | {dir} | {action} | {prio} | {src} | {dst} | {rules} | {log} | {desc} | {just} |"
    for f in flows:
        lines.append(
            row.format(
                id=f["id"],
                name=f["name"],
                dir=f["direction"],
                action=f.get("action", "allow"),
                prio=f.get("priority", 1000),
                src=", ".join(f"`{s}`" for s in f["source"]),
                dst=", ".join(f"`{d}`" for d in f["destination"]),
                rules=_fmt_rules(f["rules"]),
                log="yes" if f.get("logging") else "",
                desc=f["description"],
                just=f["justification"],
            )
        )
    lines += [
        "",
        "## Change procedure",
        "",
        "1. Open a merge request editing `docs/flow-matrix.yaml` (new flow id, justification, owner).",
        "2. CI validates the matrix and regenerates this document; `terraform plan` shows the resulting rule.",
        "3. Network/security review on the merge request, then `terraform apply` from the pipeline.",
        "",
    ]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["validate", "render", "check"])
    parser.add_argument("--yaml", type=Path, default=DEFAULT_YAML)
    parser.add_argument("--md", type=Path, default=DEFAULT_MD)
    args = parser.parse_args(argv)

    try:
        data = load(args.yaml)
        facts = validate(data)
    except (MatrixError, yaml.YAMLError) as exc:
        print(f"flow matrix invalid: {exc}", file=sys.stderr)
        return 1

    print(f"flow matrix valid: {', '.join(facts)}")
    if args.command == "validate":
        return 0

    rendered = render(data)
    if args.command == "render":
        args.md.write_text(rendered, encoding="utf-8", newline="\n")
        print(f"wrote {args.md}")
        return 0

    current = args.md.read_text(encoding="utf-8") if args.md.exists() else ""
    if current.replace("\r\n", "\n") != rendered:
        print(f"{args.md} is out of date: run 'python tools/flowmatrix.py render'", file=sys.stderr)
        return 1
    print(f"{args.md} is up to date")
    return 0


if __name__ == "__main__":
    sys.exit(main())
