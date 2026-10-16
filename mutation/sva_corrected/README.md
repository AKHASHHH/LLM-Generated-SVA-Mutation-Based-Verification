# sva_corrected/ (empty by design)

The original generated SVA files are never edited. They are read from `$GEN_DIR` and hash-checked before every run.

Create a file here **only if** an original SVA file fails its first-pass VCS compile, and only for a problem in the original source. Do not create one for a harness problem; fix the harness instead.

1. Keep the first-pass log. `results/compile/sva_<x>_1.original.first_pass.log` is written once and never overwritten.
2. `cp $GEN_DIR/sva_<x>_1.sv sva_corrected/sva_<x>_1_corrected.sv`, then make the **minimum** change needed to compile.
3. Record every change in `CHANGES.md`: the line, the original text, the new text, and the VCS error that required it.
4. Rerun with the corrected copy: `env USE_CORRECTED=1 ./scripts/run_sva_compile.sh`, and likewise for `run_sva_fp.sh` and `run_detection.sh`.
5. Report both results. The original's result is COMPILE_FAIL. The corrected copy's results are labeled "corrected" in `results/compile/status.tsv` and in the matrix.
