Time-0 experiment patch (apply on top of apbtmr_v2_validation_patch, inside mutation/)

Replaces : tb/tb_top.sv
  base   : 961353242f8d4a69d77260078c6ead79d971939cc4c7d16206508e34ad499941  (validation-patch version)
  new    : 3b8887a9fabe8e87daa6a39b66ea72489d9c539920d3d16838cd48955fbddb3d
Adds     : scripts/run_time0_experiment.sh, docs/TIME0_EXPERIMENT.md, TIME0_PATCH_README.txt
Untouched: generated originals, results/, results_validation/ (phase A), every other script.
Default TB behavior (no new defines) is identical to the validation-patch TB.
