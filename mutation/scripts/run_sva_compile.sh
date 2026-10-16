#!/bin/bash
# STEP 2: first-pass compilation of each ORIGINAL SVA set, bound to the reference DUT.
# The first compile log of each SVA is preserved as results/compile/<sva>.first_pass.log and never overwritten.
source "$(dirname "$0")/common.sh"
verify_gen
mkdir -p "$RES/compile"
: > "$RES/compile/status.tsv.new"
for s in gpt claude; do
  f=$(sva_file $s); variant=$(sva_variant $s)
  if build "sva_${s}_ref" "+define+WITH_SVA $SVA_OPTS" "$TB" "$REF" "$REFDUT" "$f"; then rc=0; st=COMPILE_OK; else rc=$?; st=COMPILE_FAIL; fi
  first="$RES/compile/sva_${s}_1.${variant}.first_pass.log"
  if [ ! -f "$first" ]; then cp "$BUILD/sva_${s}_ref/compile.log" "$first" 2>/dev/null
  else cp "$BUILD/sva_${s}_ref/compile.log" "$RES/compile/sva_${s}_1.${variant}.rerun_$(date +%Y%m%d_%H%M%S).log" 2>/dev/null; fi
  printf "%s\t%s\t%s\t%s\t%s\n" "$s" "$variant" "$st" "$rc" "$f" >> "$RES/compile/status.tsv.new"
  echo "sva_$s ($variant): $st  (log: build/sva_${s}_ref/compile.log)"
done
mv "$RES/compile/status.tsv.new" "$RES/compile/status.tsv"
