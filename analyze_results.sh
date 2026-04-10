#!/bin/bash
# Group fixture results by command category and compare to RTK's claims

/tmp/ztk/bench_rtk.sh 2>&1 | awk '
/^\| / && !/command/ && !/^\| ---/ {
  gsub(/[ \t]*\|[ \t]*/, "|")
  gsub(/^\|/, "")
  gsub(/\|$/, "")
  split($0, f, "|")
  if (f[4] != "" && f[3] != "") {
    cmd = f[2]
    raw = f[3] + 0
    filt = f[4] + 0
    totals[cmd] += raw
    filtered[cmd] += filt
  }
}
END {
  printf "%-20s %10s %10s %8s  RTK claim\n", "Category", "Raw", "Filtered", "Savings"
  printf "%-20s %10s %10s %8s  ---------\n", "--------", "---", "--------", "-------"
  for (c in totals) {
    savings = (totals[c] - filtered[c]) * 100 / totals[c]
    printf "%-20s %10d %10d %7.1f%%\n", c, totals[c], filtered[c], savings
  }
  print "---"
  for (c in totals) {
    grand_raw += totals[c]
    grand_filt += filtered[c]
  }
  printf "%-20s %10d %10d %7.1f%%\n", "TOTAL", grand_raw, grand_filt, (grand_raw - grand_filt) * 100 / grand_raw
}'
