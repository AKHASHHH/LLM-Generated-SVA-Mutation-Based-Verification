#!/bin/bash
# Final validation. Never writes to results/ or build/ (the first run), never touches $GEN_DIR.
#   A  time-0 experiment: Claude + GPT SVA on the reference, identical TB except the PCLK declaration
#        A0 logic PCLK = 1'b0  (first-run setting)      A1 bit PCLK = 1'b0  (+define+CLK2STATE)
#      both with +define+DIAG_T0, which reports any clock event in the first 1 ns and the sampled values there
#      (record only: phase A is refused if its results already exist)
#   B  complete clean rerun with +define+CLK_START_1NS, the start-up proven by the time-0 experiment
#      (ref check, compile, FP, activation, detection, then the audited matrix with the start-up enforced)
#      into results_clkstart1ns/ and build_clkstart1ns/; refused if results_clkstart1ns/ already exists
#   C  re-analysis of the FIRST-RUN logs with the validating matrix builder (read-only on results/)
#   E  first run vs corrected run comparison (needs B and C)
#   D  text traces of the interrupt path for the two Verdi captures (M10, M01), from the phase-B builds
# Usage: ./scripts/run_validation.sh [A|B|C|E|D]...      (no argument = B C E)
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/.." && pwd)
phases=${*:-B C E}
V=$root/results_validation; mkdir -p "$V"
RB=$root/results_clkstart1ns; BB=$root/build_clkstart1ns
for p in $phases; do case $p in
A)
  [ -e "$V/time0_experiment.txt" ] && { echo "phase A results exist (results_validation/time0_experiment.txt); kept, not rerun"; continue; }
  for cfg in "t0_logic:+define+DIAG_T0" "t0_bit:+define+DIAG_T0 +define+CLK2STATE"; do
    n=${cfg%%:*}; d=${cfg#*:}
    env RES_DIR="$V/$n" BUILD_DIR="$root/build_validation/$n" TB_DEFINES="$d" "$here/run_sva_compile.sh" > "$V/$n.compile.txt" 2>&1
    env RES_DIR="$V/$n" BUILD_DIR="$root/build_validation/$n" TB_DEFINES="$d" "$here/run_sva_fp.sh" > "$V/$n.fp.txt" 2>&1
  done
  {
    echo "TIME-0 EXPERIMENT (identical TB and vectors; only the PCLK declaration differs)"
    for n in t0_logic t0_bit; do
      echo; echo "== $n"
      for s in claude gpt; do
        f="$V/$n/fp/sva_$s.ref.log"
        echo "  sva_$s: SVA failure lines at time 0: $(grep 'u_sva' "$f" 2>/dev/null | grep -cE 'failed at 0 ?ps|at time 0 ?ps|failed at 0 ?ns|at time 0 ?ns')"
        echo "          all SVA failure lines:        $(grep 'u_sva' "$f" 2>/dev/null | grep -ciE 'failed|error')"
        grep -h "TBDIAG" "$f" 2>/dev/null | sed 's/^/          /'
      done
    done
  } | tee "$V/time0_experiment.txt" ;;
B)
  [ -e "$RB" ] && { echo "results_clkstart1ns/ already exists; move it aside to rerun phase B"; exit 1; }
  env RES_DIR="$RB" BUILD_DIR="$BB" TB_DEFINES="+define+CLK_START_1NS" "$here/run_all.sh" > "$V/clkstart1ns_run_all.txt" 2>&1
  env RES_DIR="$RB" python3 "$here/make_matrix.py" --expect-startup CLK_START_1NS > "$V/clkstart1ns_matrix.txt" 2>&1
  echo "matrix exit status: $?"; sed -n '/## 6/,$p' "$RB/matrix.md" ;;
C)
  env RES_DIR="$root/results" python3 "$here/make_matrix.py" --out "$V/first_run_revalidated_v2" > "$V/first_run_revalidated_v2.txt" 2>&1
  sed -n '/## 4/,/## 5/p' "$V/first_run_revalidated_v2/matrix.md" ;;
E)
  python3 "$here/compare_runs.py" "$V/first_run_revalidated_v2" "$RB" "$V/first_vs_corrected.md" | tail -4 ;;
D)
  mkdir -p "$V/traces"
  ( export RES_DIR="$RB" BUILD_DIR="$BB"; source "$here/common.sh"
    for s in gpt claude; do
      run "det_${s}_M10_IRQ_REGISTERED"       "$V/traces/M10_${s}.log" +TRACE_FROM=170 +TRACE_TO=215
      run "det_${s}_M01_PEND_CLEAR_BEATS_SET" "$V/traces/M01_${s}.log" +TRACE_FROM=825 +TRACE_TO=870
    done )
  for f in "$V"/traces/M10_gpt.log "$V"/traces/M01_gpt.log; do
    echo "== $(basename "$f")"
    grep "TBTRACE" "$f"
    echo "-- first scoreboard divergence:"; grep -m1 "TBMSG REF_DIVERGE" "$f"
    echo "-- first SVA failure lines:"; grep "u_sva" "$f" | grep -iE "failed|error" | grep -vE "at 0 ?ps|time 0 ?ps" | head -3
  done ;;
*) echo "unknown phase $p (use A B C E D)";;
esac; done
