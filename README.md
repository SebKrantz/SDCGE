# EnvCGE V9 — ENVISAGE-style climate CGE in Julia

EnvCGE is a Julia port of the [ENVISAGE v10.01](docs/ENVISAGE10.01_Documentation.pdf)
model: a dynamic, multi-regional computable general equilibrium (CGE) model for
environmental and climate-economy analysis, with emissions accounting, a
three-box carbon cycle, damage functions, and recursive dynamics. It is
formulated as a mixed complementarity problem (MCP) in [JuMP](https://jump.dev)
for the PATH solver, and reads its benchmark data from an Excel workbook.

> **Sibling branch.** The `main` branch of this repository holds an unrelated
> model (LCGE-V4, a LINKAGE-style CGE). The two share no code or history; do
> not merge them.

---

## Current status (2026-09-03)

Please read this before using the model.

- Data loading, SAM construction and balancing, calibration, model build,
  initialisation, the equation/MCP registries and the square-system
  diagnostics all work with the shipped example workbook
  (3 regions × 21 activities × 20 commodities).
- **The equation system is not square yet**: the build declares 29,547
  variables against 26,274 non-bound equations (gap 3,273). It was 45,900 vs
  26,282 (gap 19,618) before 2026-09-03; the reduction came from no longer
  declaring the agent-sourcing/MRIO trade families (`XWa`, `PDMa`, `XD`,
  `XM`, `PMa`, `PM`, `PD`) when `ArmFlag = 0`, declaring the electricity
  power/bundle variables over `ely` only, and removing duplicate or
  tautological closure equations (M-9, the `r = rres` branch of M-14, M-25,
  D-36). `solve!` refuses to call PATH (`require_square=true` by default),
  so no equilibrium has been computed yet.
- Known remaining issues: `Re[r]` (expected rate of return) is defined by
  three simultaneous alternative closure equations M-18, M-19 and M-21 —
  ENVISAGE selects one via a closure switch that this port lacks; this must
  be resolved before any solve. About 660 variable instances are still
  referenced by no equation (`Emi`, `VA2/PVA2/PVA1`, `ND2`, `kxRat`, `QFD`
  are declared over larger index sets than the equations that use them;
  `ZC`, `UEMin`, `YC` and the water-bundle family are dead declarations), and
  ≈2,600 further variables are used but under-determined.
  `examples/block_by_block_square_diagnostics.jl` and
  `reports/path_square/path_square_summary.md` show the gap per block.
- The standalone climate module (`climate_state` → `climate_step!` /
  `run_climate_path!`) works and responds sensibly to an emissions path.
- Solving a model of this size also needs a PATH licence: set
  `PATH_LICENSE_STRING` (the free courtesy licence from the
  [PATH website](https://pages.cs.wisc.edu/~ferris/path.html) suffices).

---

## Requirements

- Julia ≥ 1.10 (tested on 1.12.4)
- Packages, installed by `Pkg.instantiate()`:

| Package | Purpose |
|---|---|
| `JuMP`, `PATHSolver` | MCP formulation and solver interface |
| `DataFrames`, `CSV` | Tables, CSV reports |
| `XLSX` | Reading the benchmark workbook |
| `OrderedCollections` | Ordered equation/MCP registries |

---

## Installation

```bash
git clone -b envcge-v9 https://github.com/SebKrantz/SDCGE
cd SDCGE
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

`Project.toml` names the package `EnvCGE`, so with `--project=.` you can
`using EnvCGE` directly. Loading from source also works:

```julia
include("src/EnvCGE.jl"); using .EnvCGE
```

---

## Quick start

```julia
using EnvCGE            # julia --project=.

data, cal = calibrate_from_excel()             # data/example_envcge_data.xlsx
diag = path_square_diagnostics(data, cal)      # does not throw
diag["variable_count_total"], diag["constraint_count_excluding_bounds"]

em = build_model(data, cal; initialize=true, audit_mapping=true, require_square=false)
write_path_square_report(em; outdir="reports/path_square")   # CSV + Markdown reports

# Only once the system is square:
sol = solve!(em; require_square=true)
```

`preflight_path_square(data, cal)` is the throwing variant: it raises a
descriptive error if the system is not square, for scripts that must fail
early. Timings: calibrate ≈3 s, diagnostics ≈7 s, build ≈7 s.

---

## Examples and tests

Run from the project root; each script activates the environment itself.

| Script | What it does |
|---|---|
| `examples/read_excel_data.jl` | Load the workbook, print sets and SAM balance |
| `examples/run_example.jl` | Calibrate, build, write square diagnostics, solve if square |
| `examples/block_by_block_square_diagnostics.jl` | Add one equation block at a time and report the variable/equation gap per block |
| `examples/mcp_report.jl` | List the MCP complementarity pairs and the generated formulation |
| `examples/audit_set_coverage.jl` | Dump the loaded sets and the variable→equation mapping report |
| `examples/climate_and_dynamics_usage.jl` | Exercise the climate module from the model's start values |

```bash
julia --project=. examples/run_example.jl
julia --project=. test/runtests.jl      # smoke test (~30 s, no PATH call)
```

---

## Data

`data/example_envcge_data.xlsx` has 19 sheets. The ones the code actually
reads are `sets`, `sam` (150 accounts, balanced), `make`, `use`,
`final_demand`, `factor_demand` and `closures` (which variables are fixed
exogenously). The sheets `io`, `trade`, `elasticities`, `taxes`, `emissions`,
`climate`, `dynamics`, `nests`, `parameters` and `benchmark` are empty
placeholders in the example file — all elasticities, tax rates, emission
coefficients and dynamic parameters currently come from defaults hard-coded in
`src/ParameterTables.jl` and `src/calibration.jl`. `activity_product_map` and
`closure_variables` are not read.

---

## Project structure

```
SDCGE/  (branch envcge-v9)
├── src/
│   ├── EnvCGE.jl                   module entry point, include order, exports
│   ├── types.jl                    EnvSets, EnvData, EnvCalibration, EnvModel
│   ├── io.jl                       Excel loading (load_excel_data, load_default_data)
│   ├── sam.jl                      construct_sam, check_sam_balance, balance_sam
│   ├── calibration.jl              calibrate, calibrate_from_excel
│   ├── ParameterTables.jl          parameters(data, cal): every parameter used by the equations
│   ├── initialization.jl           start values (apply_initial_values!)
│   ├── production.jl … emissions.jl   equation blocks P, S, Y, D, T, E, F, M, EM (ENVISAGE numbering)
│   ├── climate.jl                  standalone carbon-cycle / temperature / damage module
│   ├── dynamics.jl                 recursive state updates (G, C equations), run_recursive_dynamic!
│   ├── equations_registry.jl       ENVISAGE equation registry and coverage report
│   ├── path_mapping.jl, mcp.jl     variable ↔ equation mapping, MCP pair registry
│   ├── path_square_diagnostics.jl  square-system checks and reports
│   └── model.jl                    build_model, solve!
├── data/example_envcge_data.xlsx
├── docs/ENVISAGE10.01_Documentation.pdf
├── examples/
├── test/runtests.jl
└── reports/                        generated diagnostics (git-ignored)
```

---

## Model specification

Equation labels in the source (`# P-1`, `# T-12`, `# EM-3`, …) refer to the
numbered equations in the ENVISAGE v10.01 technical documentation by
Dominique van der Mensbrugghe (GTAP Center, Purdue University, 2019), a copy of
which is in `docs/`. The PDF is third-party material included for reference;
it carries no explicit redistribution licence.

Known gaps relative to the documentation:

- The system is not square (see status above).
- Closure block: M-32–M-39 are not ported; M-18/M-19/M-21 are alternative
  closures that are all active at once; M-27/M-28 (EV/CV) are placeholders.
- Dynamics: the Armington-twist updates G-10–G-12 are implemented but not
  wired into `dynamics_update!`.
- The climate damage module follows the documentation's own "[tbd]" marker.
- `calibration.jl` computes CES share parameters that are never used; the
  parameters that enter the equations are recomputed in `ParameterTables.jl`.
