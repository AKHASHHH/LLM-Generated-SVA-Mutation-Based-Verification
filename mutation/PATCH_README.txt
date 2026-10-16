Project 4 v2 validation patch. Extract inside Project_4/v2/mutation/ AFTER backing up the first-run files.
It replaces only testbench/script files (listed in FIRST_RUN_FILES.sha256) and adds scripts/run_validation.sh
and docs/VALIDATION.md. It never touches results/, build/, or the six generated originals.
With no new defines/plusargs, behaviour is identical to the first run.
