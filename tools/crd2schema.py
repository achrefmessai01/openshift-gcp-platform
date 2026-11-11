#!/usr/bin/env python3
"""Convert CustomResourceDefinitions into JSON schemas usable by kubeconform.

    python tools/crd2schema.py <crd.yaml | URL> [<crd.yaml | URL> ...] --out deploy/schemas

One file per served version is written as <out>/<group>/<kind>_<version>.json, the layout
expected by kubeconform's -schema-location
'deploy/schemas/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'.

The transformation mirrors kubeconform's openapi2jsonschema: the OpenAPI v3 schema of each
version is taken as-is, `x-kubernetes-int-or-string` becomes `oneOf [string, integer]`,
and a draft-04 `$schema` is added. Only PyYAML is required.
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.request
from pathlib import Path
from typing import Any

import yaml


def load(source: str) -> list[dict]:
    if source.startswith(("http://", "https://")):
        with urllib.request.urlopen(source, timeout=60) as resp:
            text = resp.read().decode("utf-8")
    else:
        text = Path(source).read_text(encoding="utf-8")
    return [d for d in yaml.safe_load_all(text) if d]


def transform(node: Any) -> Any:
    if isinstance(node, dict):
        # Generated CRDs may carry keywords set to null (e.g. `anyOf: null` on Route targetPort);
        # Kubernetes ignores them but JSON schema validators do not, so they are dropped.
        node = {k: v for k, v in node.items() if v is not None}
        if node.get("x-kubernetes-int-or-string"):
            out = {k: transform(v) for k, v in node.items() if k not in ("x-kubernetes-int-or-string", "type")}
            out["oneOf"] = [{"type": "string"}, {"type": "integer"}]
            return out
        return {k: transform(v) for k, v in node.items()}
    if isinstance(node, list):
        return [transform(v) for v in node]
    return node


def convert(crd: dict, out_dir: Path) -> list[Path]:
    if crd.get("kind") != "CustomResourceDefinition":
        return []
    group = crd["spec"]["group"]
    kind = crd["spec"]["names"]["kind"].lower()
    written: list[Path] = []
    for version in crd["spec"]["versions"]:
        if not version.get("served", True):
            continue
        schema = version.get("schema", {}).get("openAPIV3Schema")
        if not schema:
            continue
        schema = transform(schema)
        schema["$schema"] = "http://json-schema.org/draft-04/schema#"
        target = out_dir / group / f"{kind}_{version['name']}.json"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(schema, indent=2) + "\n", encoding="utf-8", newline="\n")
        written.append(target)
    return written


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("sources", nargs="+", help="CRD manifests (files or URLs), multi-document YAML allowed")
    parser.add_argument("--out", type=Path, default=Path("deploy/schemas"))
    args = parser.parse_args(argv)

    total = 0
    for source in args.sources:
        for doc in load(source):
            for path in convert(doc, args.out):
                print(f"wrote {path}")
                total += 1
    if total == 0:
        print("no CustomResourceDefinition found", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
