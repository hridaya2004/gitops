#!/usr/bin/env bash
set -euo pipefail

# walk up from each staged file to find the nearest kustomization.yaml
declare -A kustomize_cache
for f in "$@"; do
  [ "$(basename "$f")" = "kustomization.yaml" ] && continue

  file_dir=$(dirname "$f")
  dir="$file_dir"
  while [ "$dir" != "." ] && [ "$dir" != "/" ]; do
    if [ -f "$dir/kustomization.yaml" ]; then
      # cache kustomize output per kustomization dir so we don't rebuild
      if [[ -z "${kustomize_cache[$dir]:-}" ]]; then
        kustomize_cache[$dir]=$(kubectl kustomize "$dir")
      fi
      build_output=${kustomize_cache[$dir]}

      # identify the resource so we can find it in the build output
      identity=$(yq eval-all '.apiVersion + "|" + .kind + "|" + (.metadata.name // "")' "$f" 2>/dev/null)
      [ -z "$identity" ] && break

      # extract the matching rendered document from the build output
      rendered=$(echo "$build_output" | yq eval-all "
        select(.apiVersion + \"|\" + .kind + \"|\" + (.metadata.name // \"\") == \"$identity\")
      " - 2>/dev/null)

      if [ -n "$rendered" ]; then
        tmp=$(mktemp)
        echo "$rendered" > "$tmp"
        if ! diff -q "$f" "$tmp" > /dev/null 2>&1; then
          cp "$tmp" "$f"
          git add "$f"
        fi
        rm -f "$tmp"

        if git diff --cached --quiet -- "$f" 2>/dev/null; then
          git reset HEAD -- "$f" 2>/dev/null || true
        fi
      fi
      break
    fi
    dir=$(dirname "$dir")
  done
done

# nothing staged — prevent an empty commit
if git diff --cached --quiet -- . 2>/dev/null; then
  echo "kustomize: no meaningful changes, aborting commit"
  exit 1
fi
