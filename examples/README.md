# LCGE-V4 examples

Run any script from the project root:

```bash
julia examples/01_prepare_data.jl
```

Each script activates the project environment and loads the model with
`include("src/LinkageModel.jl"); using .LinkageModel`.

| Script | What it does | Runtime |
|--------|--------------|---------|
| `01_prepare_data.jl` | Build the default synthetic SAM, RAS-balance it, calibrate | ~15 s |
| `02_read_csv_sam.jl` | Same, but reading `data/csv/sam.csv` | ~15 s |
| `03_read_excel_sam.jl` | Same, but reading `data/linkage_100sector_data.xlsx` | ~15 s |
| `04_build_model.jl` | Build the JuMP/PATH model and print variable/constraint counts | ~30 s |
| `05_solve_and_export.jl` | Build, solve with PATH (benchmark, ~4 s), write `results/*.csv`, plot | ~1 min |
| `06_equation_diagnostics.jl` | Equation ↔ variable matching and start residuals in `results/diagnostics/` | ~1 min |
| `07_recursive_dynamics.jl` | 10-period recursive-dynamic run → `results/dynamic/` (see README: periods with labour growth currently fail to converge) | ~9 min |
| `08_policy_experiments.jl` | Excel-driven scenario batch → `results/scenarios/` (2 scenarios × 3 periods ≈ 2 min; the 10×10 template ≈ 1–2 h) | hours |
| `09_full_pipeline.jl` | Static + dynamic + all scenarios in one go | hours |

Before relying on any solved result, check `termination_status(m)` — see
"Current status" and "Known limitations" in the top-level README.
