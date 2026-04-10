#!/usr/bin/env bash
# Run ztk filters against RTK extracted fixtures and compute size savings.
#
# For each fixture in MANIFEST.json:
#   - Read the raw input file size.
#   - Pipe its contents through `ztk filter <command>`.
#   - Capture filtered byte count and ztk exit code.
#   - When ztk does not match a filter (exit 1), report passthrough: filtered = raw.
#
# Output: a markdown table on stdout plus a totals/top/bottom summary.

set -u

ZTK="${ZTK:-/tmp/ztk/zig-out/bin/ztk}"
MANIFEST="${MANIFEST:-/tmp/rtk-extracted/MANIFEST.json}"

if [[ ! -x "$ZTK" ]]; then
  echo "ERROR: ztk binary not found at $ZTK" >&2
  exit 2
fi
if [[ ! -f "$MANIFEST" ]]; then
  echo "ERROR: manifest not found at $MANIFEST" >&2
  exit 2
fi

# Stream rows: name|command|input_path|raw_bytes
rows=$(jq -r '.fixtures[] | [.name, .command, .input_path, .raw_bytes] | @tsv' "$MANIFEST")

printf '| fixture | command | raw | filtered | savings%% | matched |\n'
printf '| --- | --- | ---: | ---: | ---: | :---: |\n'

total_raw=0
total_filtered=0
crashed=0
suspicious=()
declare -a all_rows

while IFS=$'\t' read -r name command input_path raw_bytes; do
  raw=$(wc -c < "$input_path" | tr -d ' ')
  tmp_out=$(mktemp)
  tmp_err=$(mktemp)
  "$ZTK" filter "$command" < "$input_path" > "$tmp_out" 2> "$tmp_err"
  rc=$?

  if [[ $rc -eq 0 ]]; then
    filtered=$(wc -c < "$tmp_out" | tr -d ' ')
    matched="yes"
  elif [[ $rc -eq 1 ]]; then
    # No filter matched: ztk would passthrough, count raw bytes.
    filtered=$raw
    matched="no"
  else
    crashed=$((crashed + 1))
    filtered=$raw
    matched="CRASH(rc=$rc)"
  fi

  # Suspicious: filter matched, raw was non-empty, output is empty.
  if [[ "$matched" == "yes" && "$raw" -gt 0 && "$filtered" -eq 0 ]]; then
    suspicious+=("$name (raw=$raw -> 0)")
  fi

  if [[ $raw -gt 0 ]]; then
    savings=$(awk -v r="$raw" -v f="$filtered" 'BEGIN{ printf "%.1f", (r-f)*100.0/r }')
  else
    savings="0.0"
  fi

  printf '| %s | %s | %d | %d | %s | %s |\n' "$name" "$command" "$raw" "$filtered" "$savings" "$matched"

  all_rows+=("$savings|$name|$command|$raw|$filtered|$matched")
  total_raw=$((total_raw + raw))
  total_filtered=$((total_filtered + filtered))

  rm -f "$tmp_out" "$tmp_err"
done <<< "$rows"

echo
echo "## Totals"
echo
if [[ $total_raw -gt 0 ]]; then
  overall=$(awk -v r="$total_raw" -v f="$total_filtered" 'BEGIN{ printf "%.1f", (r-f)*100.0/r }')
else
  overall="0.0"
fi
printf 'total_raw_bytes      : %d\n' "$total_raw"
printf 'total_filtered_bytes : %d\n' "$total_filtered"
printf 'overall_savings_pct  : %s%%\n' "$overall"
printf 'crashed_fixtures     : %d\n' "$crashed"

echo
echo "## Top 5 by savings"
echo
printf '%s\n' "${all_rows[@]}" | sort -t'|' -k1,1 -gr | head -5 | \
  awk -F'|' '{ printf "  %-30s  %-15s  %s%% (%d -> %d) [%s]\n", $2, $3, $1, $4, $5, $6 }'

echo
echo "## Bottom 5 by savings"
echo
printf '%s\n' "${all_rows[@]}" | sort -t'|' -k1,1 -g | head -5 | \
  awk -F'|' '{ printf "  %-30s  %-15s  %s%% (%d -> %d) [%s]\n", $2, $3, $1, $4, $5, $6 }'

echo
echo "## Suspicious outputs (matched filter but emitted nothing)"
echo
if [[ ${#suspicious[@]} -eq 0 ]]; then
  echo "  none"
else
  for s in "${suspicious[@]}"; do
    echo "  - $s"
  done
fi
