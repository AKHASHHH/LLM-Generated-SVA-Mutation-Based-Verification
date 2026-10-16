#!/bin/bash
# Runs steps 1-6 in order. Expect roughly 25 VCS compiles. Stops if the reference check fails.
here=$(dirname "$0")
"$here/run_ref_check.sh" || exit 1
grep -q "^ref: PASS" "${RES_DIR:-$here/../results}/ref_check/summary.txt" || { echo "Reference check FAILED - stop and adjudicate before continuing."; exit 1; }
"$here/run_sva_compile.sh" && "$here/run_sva_fp.sh" && "$here/run_activation.sh" && "$here/run_detection.sh" && python3 "$here/make_matrix.py"
