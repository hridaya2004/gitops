#!/usr/bin/env bash
set -euo pipefail

# Auto-format staged YAML files to KYAML format
# Uses sigs.k8s.io/yaml/yamlfmt with -o kyaml -w (in-place)

for f in "$@"; do
  [ -f "$f" ] || continue
  yamlfmt -o kyaml -w "$f"
  git add "$f"
done
