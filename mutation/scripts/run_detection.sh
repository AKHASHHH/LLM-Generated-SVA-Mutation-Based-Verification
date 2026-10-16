#!/bin/bash
# STEP 5: detection - each compiled SVA set x each mutant, same vectors as the false-positive run.
source "$(dirname "$0")/common.sh"
verify_gen
[ -f "$RES/compile/status.tsv" ] || die "run scripts/run_sva_compile.sh first"
while IFS=$'\t' read -r s variant st rc f; do
  [ "$st" = "COMPILE_OK" ] || { echo "sva_$s: skipped ($st)"; continue; }
  mkdir -p "$RES/detection/sva_$s"
  for m in "$ROOT"/mutants/M*.sv; do
    id=$(basename "$m" .sv)
    if build "det_${s}_$id" "+define+WITH_SVA $SVA_OPTS" "$TB" "$REF" "$m" "$f"; then
      run "det_${s}_$id" "$RES/detection/sva_$s/$id.log"; echo "sva_$s x $id: done"
    else echo "sva_$s x $id: COMPILE_FAIL"; fi
  done
done < "$RES/compile/status.tsv"
