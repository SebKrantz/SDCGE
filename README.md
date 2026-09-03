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
- **No equilibrium has been computed, and none can be yet.** Two blockers:
  1. Every equation is written with JuMP's legacy `@NLconstraint`.
     PATHSolver only accepts complementarity constraints
     (`@constraint(m, [F, x] in MOI.Complements(2))` / `F ⟂ x`), so the
     `solve!` path has never been reachable. All ≈200 equation sites need
     rewriting in that form, each with its complementary variable (the
     pairing in `src/path_mapping.jl` / `src/mcp.jl` is the starting point).
  2. The system is not square: 27,128 free variables vs 26,793 non-bound
     equations (gap 335). It was 45,900 vs 26,282 on the original upstream
     code; the reduction on 2026-09-03 came from closure switches
     (`invClosure`, `capClosure` — see below), declaring variables only over
     the index sets their equations use, deleting dead declarations, fixing
     372 exogenous variables in a default closure
     (`closure.jl::apply_default_closures!`), and adding documented
     equations (P-48, P-9…P-17 for default activities, F-39, D-36, D-12/D-23
     link, M-33). The remaining gap is mostly the value-added nest of the
     default activities (`VA2`/`PVA2`/`ND2`; ENVISAGE Table 3.2 uses land,
     not `VA2`, there) and the electricity make-matrix block (`PP`/`X` for
     `ely`, where the document gives no price equation).
- Once square and in complementarity form, calibration still has to be made
  consistent with initialisation: 36 % of equations have a non-zero residual
  at the start values because the share/elasticity parameters in
  `ParameterTables.jl` are defaults while start values are derived from the
  SAM flows. See "Known gaps" below.
- Closure options (`data.par`): `invClosure ∈ {"gtap" (default, M-18),
  "flexSf" (M-19), "usage" (M-21)}` and `capClosure ∈ {"vintage" (default,
  F-15…F-24), "static" (F-12/F-13)}`. Previously all alternatives were active
  at once.
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

Known gaps relative to the documentation (ranked):

1. Equations must be converted from `@NLconstraint` to complementarity form
   before PATH can be called (see status).
2. Square gap of 335 free variables: default-activity value-added nest
   (`VA2`/`PVA2`/`ND2`, Table 3.2) and the electricity make block
   (`PP`/`X` for `ely`, §3.3.2; with an empty `etd` sheet the generic
   S-1…S-5 block should be used instead of S-6…S-14).
3. Benchmark replication: share parameters must be derived from the
   SAM/make/use/final-demand/factor-demand flows at benchmark prices,
   consistently with `initialization.jl`. `calibration.jl::_calibrate_alpha`
   computes shares that nothing reads; `ParameterTables.jl` is what the
   equations use.
4. Labels: the port's "M-27/M-28" slots hold EV (implemented as the
   document's M-33) and `CV == 0` (the document has no CV equation); the
   document's M-27/M-28 are the PFACT/PWGDP price indices, not ported.
   M-34–M-39 are not ported. `PXGHG` is fixed at benchmark (no emission-tax
   schedule is implemented).
5. Land is treated as agriculture-only (non-agricultural land cells fixed
   at zero), which conflicts with the default nest in Table 3.2.
6. Dynamics: the Armington-twist updates G-10–G-12 are implemented but not
   wired into `dynamics_update!`; the climate damage module follows the
   documentation's own "[tbd]" marker.
