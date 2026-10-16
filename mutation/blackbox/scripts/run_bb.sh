#!/bin/bash
# Experiment 2 runner (black-box checkers). Writes only under blackbox/results/ and blackbox/build/.
# Reuses the white-box helpers (scripts/common.sh: build, run, verify_gen) and the UNCHANGED tb/tb_top.sv.
# Every build uses +define+CLK_START_1NS (the validated start-up). Checkers are compiled from blackbox/gen/
# exactly as generated; their hashes are verified before every phase.
#   iso   interface isolation: comment-stripped text scan + standalone VCS elaboration (checker as only top)
#   base  in-TB compile with the reference DUT + baseline run; writes the baseline gate
#   det   20 detection runs (only for checkers whose baseline gate passed); refused otherwise
#   matrix  audited Experiment 2 matrix (scripts/bb_matrix.py)
# Usage: ./blackbox/scripts/run_bb.sh [iso|base|det|matrix]...   (no argument = iso base det matrix,
#        stopping after base if the baseline gate fails)
here=$(cd "$(dirname "$0")" && pwd); BB=$(cd "$here/.." && pwd); ROOT=$(cd "$BB/.." && pwd)
export RES_DIR="$BB/results" BUILD_DIR="$BB/build" TB_DEFINES="+define+CLK_START_1NS"
source "$ROOT/scripts/common.sh"
GB=$BB/gen; R=$RES; CHECKERS="gpt claude"
# Hook: default = module bb_bind as a second top (-top bb_bind). setenv BB_BIND_MODE unit if your VCS rejects a
# second -top: the bind then sits at compilation-unit scope (tb/bb_bind_unit.sv) and tb_top stays the only top.
if [ "${BB_BIND_MODE:-module}" = unit ]; then HOOK="$BB/tb/bb_bind_unit.sv"; HOOKTOP=""; else HOOK="$BB/tb/bb_bind.sv"; HOOKTOP="-top bb_bind"; fi
phases=${*:-iso base det matrix}

verify_bb() {
  ( cd "$GB" && sha256sum -c "$BB/docs/BB_FROZEN_SHA256.txt" ) > "$R/bb_hash_check.log" 2>&1 \
    || { cat "$R/bb_hash_check.log"; die "black-box checker files differ from the reviewed originals (docs/BB_FROZEN_SHA256.txt)"; }
  if [ -f "$GB/bb_sha256.txt" ]; then
    ( cd "$GB" && sha256sum -c bb_sha256.txt ) >> "$R/bb_hash_check.log" 2>&1 \
      || ( cd "$BB" && sha256sum -c gen/bb_sha256.txt ) >> "$R/bb_hash_check.log" 2>&1 \
      || ( cd "$ROOT" && sha256sum -c blackbox/gen/bb_sha256.txt ) >> "$R/bb_hash_check.log" 2>&1 \
      || { cat "$R/bb_hash_check.log"; die "gen/bb_sha256.txt does not verify"; }
  fi
  echo "Black-box checkers verified unchanged (results/bb_hash_check.log)."
}
fresh() { [ -e "$1" ] && die "$(basename "$1")/ already exists in blackbox/results; move it aside to rerun this phase"; mkdir -p "$1"; }
iso_ok()  { grep -q "^$1	PASS" "$R/isolation/status.tsv" 2>/dev/null; }
gate_ok() { grep -q "^$1	PASS" "$R/baseline/gate.tsv" 2>/dev/null; }

verify_gen; verify_bb
for p in $phases; do case $p in
iso)
  fresh "$R/isolation"
  for s in $CHECKERS; do
    f="$GB/sva_bb_${s}_1.sv"
    # (1) text scan, comments removed: any dotted identifier (hierarchical reference), $root, TB/DUT names,
    #     bind, force/release, file I/O, DPI, `include
    sed -e 's://.*$::' "$f" | perl -0pe 's:/\*.*?\*/::gs' \
      | grep -nE '\$root|\btb_top\b|\bdut\b|\bref_i\b|\bu_sva\b|\bbind\b|\bforce\b|\brelease\b|\$fopen|\$readmem|\$fwrite|DPI|`include|[A-Za-z_][A-Za-z0-9_$]*\.[A-Za-z_]' \
      > "$R/isolation/sva_bb_${s}.scan.txt"
    nscan=$(grep -c . "$R/isolation/sva_bb_${s}.scan.txt")
    # (2) standalone elaboration with the checker as the ONLY top: a reference outside the module cannot resolve
    d="$BUILD/iso_$s"; rm -rf "$d"; mkdir -p "$d"
    ( cd "$d" && vcs $VCS_OPTS $SVA_OPTS -top apb_timer_bb_sva -o simv -l compile.log "$f" ) < /dev/null > "$d/vcs_stdout.log" 2>&1
    rc=$?; [ $rc -eq 0 ] && [ -x "$d/simv" ] || { [ $rc -eq 0 ] && rc=99; }
    cp "$d/compile.log" "$R/isolation/sva_bb_${s}.standalone_compile.log" 2>/dev/null
    if [ "$nscan" -eq 0 ] && [ $rc -eq 0 ]; then v=PASS; elif [ "$nscan" -ne 0 ]; then v=FAIL_SCAN; else v=STANDALONE_FAIL; fi
    printf "%s\t%s\t%s\t%s\n" "$s" "$v" "$nscan" "$rc" >> "$R/isolation/status.tsv"
    echo "isolation sva_bb_$s: $v (scan hits $nscan, standalone vcs rc $rc)"
  done ;;
base)
  [ -f "$R/isolation/status.tsv" ] || die "run the iso phase first"
  fresh "$R/baseline"; mkdir -p "$R/compile"
  for s in $CHECKERS; do
    f="$GB/sva_bb_${s}_1.sv"
    if grep -q "^$s	FAIL_SCAN" "$R/isolation/status.tsv"; then
      printf "%s\tISOLATION_FAIL\t-\t%s\n" "$s" "$f" >> "$R/compile/status.tsv"; echo "sva_bb_$s: ISOLATION_FAIL (text scan), not run"; continue; fi
    if build "bb_${s}_ref" "$SVA_OPTS $HOOKTOP" "$TB" "$REF" "$REFDUT" "$HOOK" "$f"; then
      if iso_ok "$s"; then st=COMPILE_OK
      else st=ISOLATION_FAIL; echo "sva_bb_$s: compiles only inside the TB, not standalone: hierarchical access suspected"; fi
    else st=COMPILE_FAIL; rc=$?; fi
    cp "$BUILD/bb_${s}_ref/compile.log" "$R/compile/sva_bb_${s}.first_pass.log" 2>/dev/null
    printf "%s\t%s\t-\t%s\n" "$s" "$st" "$f" >> "$R/compile/status.tsv"
    if [ "$st" = COMPILE_OK ]; then
      run "bb_${s}_ref" "$R/baseline/sva_bb_${s}.ref.log"
      echo "sva_bb_$s on reference: $(summary "$R/baseline/sva_bb_${s}.ref.log")"
    else echo "sva_bb_$s: $st (see results/compile/sva_bb_${s}.first_pass.log)"; fi
  done
  python3 "$here/bb_matrix.py" --gate-only; grc=$?
  [ $grc -eq 0 ] || { echo "BASELINE GATE FAILED: stopping before mutation runs (see results/baseline/gate.md)."; exit 1; } ;;
det)
  [ -f "$R/baseline/gate.tsv" ] || die "run the base phase first"
  python3 "$here/bb_matrix.py" --gate-only > /dev/null || die "baseline gate not passed; mutation runs refused (results/baseline/gate.md)"
  fresh "$R/detection"
  for s in $CHECKERS; do
    gate_ok "$s" || { echo "sva_bb_$s: skipped (baseline gate)"; continue; }
    mkdir -p "$R/detection/sva_bb_$s"
    for m in "$ROOT"/mutants/M*.sv; do
      id=$(basename "$m" .sv)
      if build "bb_${s}_$id" "$SVA_OPTS $HOOKTOP" "$TB" "$REF" "$m" "$HOOK" "$GB/sva_bb_${s}_1.sv"; then
        run "bb_${s}_$id" "$R/detection/sva_bb_$s/$id.log"; echo "sva_bb_$s x $id: done"
      else echo "COMPILE_FAIL" > "$R/detection/sva_bb_$s/$id.log"; echo "sva_bb_$s x $id: COMPILE_FAIL"; fi
    done
  done ;;
matrix)
  python3 "$here/bb_matrix.py"; echo "matrix exit status: $?" ;;
*) die "unknown phase $p (use iso base det matrix)";;
esac; done
