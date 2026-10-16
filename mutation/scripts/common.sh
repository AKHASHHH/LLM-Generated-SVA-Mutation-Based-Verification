#!/bin/bash
# Shared settings and helpers. Sourced by the run_*.sh scripts; not run directly.
# Environment overrides (tcsh: setenv NAME value):
#   GEN_DIR        directory holding the six ORIGINAL generated files (default: <pkg>/../gen). Read-only use.
#   VEC            vector file (default: <pkg>/vectors/all.vec)
#   VCS_OPTS       base VCS options
#   SVA_OPTS       extra options for builds that include an SVA module
#   USE_CORRECTED  1 = use sva_corrected/<name>_corrected.sv when it exists (never the default)
#   RES_DIR, BUILD_DIR  output directories (default results/, build/)
#   TB_DEFINES     extra +define+ options added to every build
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
GEN_DIR=${GEN_DIR:-$ROOT/../gen}
VEC=${VEC:-$ROOT/vectors/all.vec}
VCS_OPTS=${VCS_OPTS:-"-full64 -sverilog -timescale=1ns/1ps -debug_access+all -kdb"}
SVA_OPTS=${SVA_OPTS:-"-assert svaext"}
USE_CORRECTED=${USE_CORRECTED:-0}
TB=$ROOT/tb/tb_top.sv
REF=$ROOT/ref/apb_timer_ref.sv
REFDUT=$ROOT/ref/apb_timer_refdut.sv
RES=${RES_DIR:-$ROOT/results}          # validation runs use a separate RES_DIR, never results/
BUILD=${BUILD_DIR:-$ROOT/build}
TB_DEFINES=${TB_DEFINES:-}              # extra testbench defines, e.g. +define+CLK2STATE
mkdir -p "$RES"

die() { echo "ERROR: $*" >&2; exit 1; }

verify_gen() {
  # The six generated artifacts are only ever read. Verify they are byte-identical to the frozen copies.
  [ -d "$GEN_DIR" ] || die "GEN_DIR not found: $GEN_DIR (setenv GEN_DIR /path/to/gen)"
  ( cd "$GEN_DIR" && sha256sum -c "$ROOT/docs/gen_sha256.txt" ) > "$RES/gen_hash_check.log" 2>&1 \
    || { cat "$RES/gen_hash_check.log"; die "generated artifacts do not match their recorded SHA-256"; }
  echo "Original generated artifacts verified (results/gen_hash_check.log)."
}

sva_variant() {   # $1 = gpt|claude -> "corrected" only if USE_CORRECTED=1 and the corrected copy exists
  if [ "$USE_CORRECTED" = "1" ] && [ -f "$ROOT/sva_corrected/sva_${1}_1_corrected.sv" ]; then echo corrected; else echo original; fi
}
sva_file() {      # $1 = gpt|claude -> path of the SVA source to compile
  if [ "$(sva_variant "$1")" = "corrected" ]; then echo "$ROOT/sva_corrected/sva_${1}_1_corrected.sv"
  else echo "$GEN_DIR/sva_${1}_1.sv"; fi
}

# build NAME "DEFINES" FILE...   -> build/NAME/simv ; returns VCS exit status
build() {
  local name=$1 defs=$2; shift 2
  local d="$BUILD/$name"; rm -rf "$d"; mkdir -p "$d"
  ( cd "$d" && vcs $VCS_OPTS $TB_DEFINES $defs -top tb_top -o simv -l compile.log "$@" ) < /dev/null > "$d/vcs_stdout.log" 2>&1
  local rc=$?
  [ $rc -eq 0 ] && [ -x "$d/simv" ] && return 0
  [ $rc -eq 0 ] && rc=99
  return $rc
}

# run NAME LOGFILE [extra simv args...]
run() {
  local name=$1 log=$2; shift 2
  mkdir -p "$(dirname "$log")"
  ( cd "$BUILD/$name" && ./simv +VEC="$VEC" +DIVFILE="${log%.log}.div" "$@" -l "$log" ) < /dev/null > /dev/null 2>&1
  grep -q "TBSUMMARY" "$log" || echo "WARNING: no TBSUMMARY in $log (simulation did not finish)"
}

summary() { grep -h "TBSUMMARY" "$1" 2>/dev/null | sed 's/^.*TBSUMMARY //'; }
