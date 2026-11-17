#!/bin/bash
# Turn the lines of a lab job's output into a picture.
# Usage: ./show_map.sh lab_omp_12345.out
f=${1:?usage: ./show_map.sh <job output file>}
grep -q '^MAP ' "$f" || { echo "No MAP lines in $f. Did the job finish? Check the file."; exit 1; }

grep '^MAP ' "$f" |
awk '{
  for (i = 2; i <= NF; i++) { split($i, kv, "="); v[kv[1]] = kv[2] }
  print v["host"], (v["rank"] == "-" ? -1 : v["rank"]), (v["thread"] == "-" ? -1 : v["thread"]), v["cpu"]
}' |
sort -k1,1 -k2,2n -k3,3n |
awk '
{
  h = $1; r = $2; t = $3; c = $4
  if (h != ph) {
    if (line != "") print line
    line = ""; pr = "x"; ph = h; nodes++
    print ""; print "  NODE " h
  }
  if (r != pr) {
    if (line != "") print line
    label = (r < 0) ? "1 process" : "rank " r
    line = sprintf("    %-10s", label); pr = r
    if (r >= 0) ranks[r] = 1
  }
  if (t >= 0) { line = line sprintf(" [t%d @cpu%d]", t, c); hasT = 1 }
  else        { line = line sprintf(" [@cpu%d]", c) }
  if (r >= 0) hasR = 1
  n++
}
END {
  if (line != "") print line
  for (k in ranks) nr++
  print ""
  if (hasR && hasT)      kind = "hybrid (MPI ranks, each with OpenMP threads)"
  else if (hasR)         kind = "MPI (separate ranks)"
  else                   kind = "OpenMP (threads in one process)"
  printf "  Workers: %d   Nodes: %d", n, nodes
  if (hasR) printf "   Ranks: %d", nr
  if (hasR && hasT) printf "   Threads per rank: %d", n / nr
  printf "\n  This looks like: %s\n\n", kind
}'
