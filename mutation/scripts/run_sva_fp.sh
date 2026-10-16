#!/bin/bash
# STEP 3: false-positive check - run each compiled SVA set on the REFERENCE with the full vector set.
# Any SVA failure here is a false positive (or a reference/spec disagreement to adjudicate).
# Optional:  ./scripts/run_sva_fp.sh all   also runs each SVA on the four original generated RTLs.
source "$(dirname "$0")/common.sh"
verify_gen
mkdir -p "$RES/fp"
[ -f "$RES/compile/status.tsv" ] || die "run scripts/run_sva_compile.sh first"
while IFS=$'\t' read -r s variant st rc f; do
  [ "$st" = "COMPILE_OK" ] || { echo "sva_$s: skipped ($st)"; continue; }
  run "sva_${s}_ref" "$RES/fp/sva_${s}.ref.log"
  echo "sva_$s on reference: $(summary "$RES/fp/sva_${s}.ref.log")"
  if [ "${1:-}" = "all" ]; then
    for t in rtl_gpt_1 rtl_gpt_2 rtl_claude_1 rtl_claude_2; do
      defs="+define+WITH_SVA $SVA_OPTS"; case $t in rtl_claude_*) defs="$defs +define+STATE_Q";; esac
      if build "sva_${s}_$t" "$defs" "$TB" "$REF" "$GEN_DIR/$t.sv" "$f"; then
        run "sva_${s}_$t" "$RES/fp/sva_${s}.$t.log"; echo "sva_$s on $t: $(summary "$RES/fp/sva_${s}.$t.log")"
      else echo "sva_$s on $t: COMPILE_FAIL"; fi
    done
  fi
done < "$RES/compile/status.tsv"
python3 "$ROOT/scripts/make_matrix.py" --fp-only
