Phase B (CLK_START_1NS) audited-campaign patch. Apply inside mutation/ on top of the time-0 patch.
Replaced files (base = version from apbtmr_v2_time0_patch / validation patch, new = this patch):
  tb/tb_top.sv  base 3b8887a9fabe8e87daa6a39b66ea72489d9c539920d3d16838cd48955fbddb3d  new a4b464c86f9326891bb05b8f28315ec4b601674bf2aa93fec85d8694dbea97c8
  scripts/make_matrix.py  base 285b4a80405e4c0fd8f416d60e150f64f6bb79b0322eef79f72c7953e4dd1a64  new af1f0d9d6b717a48ffb072fb39b7fefb562e41522b7255e0f215dd8dfaf63735
  scripts/run_validation.sh  base 04fc0f48b9f0b704c1e5fd90205a898b6782ba78ed98423327375ae2e45f5797  new 4633cd84d63d48655606da4ee21ed9acb51f8d0b64b8758f5f5c607e6ed20eed
  scripts/run_time0_experiment.sh  base 74347bdf9df817698353c5a1fdbeb52945eb475410d4a17fa3731d9ca7f8878a  new 529989366fe11f510eb146ebe1873ba5bd3da679c51f7ecc79159f61683f8689
Added: scripts/compare_runs.py, docs/PHASE_B_CLKSTART1NS.md, E3_PATCH_README.txt
Not changed: RTL, reference, mutants, SVA, vectors, common.sh, run_all.sh and the step scripts.
