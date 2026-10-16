#!/bin/bash
# STEP 4: mutant activation - each mutant as DUT, NO SVA, differential against the reference.
# A mutant is ACTIVATED if any cycle shows DUT != reference on outputs or architectural state.
source "$(dirname "$0")/common.sh"
mkdir -p "$RES/activation"
for m in "$ROOT"/mutants/M*.sv; do
  id=$(basename "$m" .sv)
  if build "act_$id" "" "$TB" "$REF" "$m"; then
    run "act_$id" "$RES/activation/$id.log"; echo "$id: $(summary "$RES/activation/$id.log")"
  else echo "$id: COMPILE_FAIL (build/act_$id/compile.log)"; fi
done
