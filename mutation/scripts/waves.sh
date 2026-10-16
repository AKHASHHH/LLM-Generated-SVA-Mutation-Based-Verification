#!/bin/bash
# Re-run an existing build with waveform dumping, for Verdi.
#   ./scripts/waves.sh <build-name> [vcd|fsdb]
#   build names: chk_ref, sva_gpt_ref, sva_claude_ref, act_M03_..., det_gpt_M03_..., det_claude_M03_...
# vcd  (default): writes results/waves/<build-name>.vcd. Then: vcd2fsdb <file>.vcd -o <file>.fsdb
# fsdb: REBUILDS <build-name>_fsdb with +define+FSDB and $FSDB_OPTS (Verdi PLI), then runs with +FSDB.
source "$(dirname "$0")/common.sh"
name=${1:?usage: waves.sh <build-name> [vcd|fsdb]}; kind=${2:-vcd}
[ -x "$BUILD/$name/simv" ] || die "no build/$name/simv - run the corresponding step first"
mkdir -p "$RES/waves"
if [ "$kind" = "vcd" ]; then
  run "$name" "$RES/waves/$name.log" +VCD +VCDFILE="$RES/waves/$name.vcd"
  echo "VCD: $RES/waves/$name.vcd"
  echo "Verdi: vcd2fsdb $RES/waves/$name.vcd -o $RES/waves/$name.fsdb ; verdi -ssf $RES/waves/$name.fsdb &"
else
  FSDB_OPTS=${FSDB_OPTS:-"-P ${VERDI_HOME:?set VERDI_HOME}/share/PLI/VCS/LINUX64/novas.tab ${VERDI_HOME}/share/PLI/VCS/LINUX64/pli.a"}
  # reuse the exact source list and defines recorded by VCS for the original build
  args=$(sed -n 's/^.*Command: *vcs //p' "$BUILD/$name/compile.log" | head -1)
  [ -n "$args" ] || die "cannot recover the build command from build/$name/compile.log; rebuild manually with +define+FSDB"
  d="$BUILD/${name}_fsdb"; rm -rf "$d"; mkdir -p "$d"
  ( cd "$d" && eval vcs $args +define+FSDB $FSDB_OPTS ) > "$d/vcs_stdout.log" 2>&1 || die "FSDB build failed: $d/vcs_stdout.log"
  ( cd "$d" && ./simv +VEC="$VEC" +FSDB -l "$RES/waves/${name}_fsdb.log" ) > /dev/null 2>&1
  echo "FSDB: $d/waves.fsdb   Verdi: cd $d ; verdi -dbdir simv.daidir -ssf waves.fsdb &"
fi
