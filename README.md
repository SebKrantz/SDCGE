# LCGE-V4 — LINKAGE-style economy-wide policy simulation model

LCGE-V4 is a Julia implementation of a LINKAGE-style computable general
equilibrium (CGE) model: 100 sectors, 4 regions, two labour skills with
rural–urban migration, old/new capital vintages, nested Armington/CET trade
with tariff-rate quotas, and a recursive-dynamic extension. It simulates how a
policy change (a tariff, a productivity shock, labour growth, …) ripples
through prices, production, employment, trade and household income.

The model is written as a square **mixed complementarity problem (MCP)** in
[JuMP](https://jump.dev) and solved with the **PATH** solver.

> **Sibling branch.** The `envcge-v9` branch of this repository holds an
> unrelated model (EnvCGE V9, an ENVISAGE-style climate CGE). The two share no
> code or history; do not merge them.

---

## Current status (2026-09-03)

Please read this before trusting any number the model produces.

- The default synthetic economy prepares, balances and builds correctly:
  216-account SAM, 48,099 variables = 48,099 complementarity constraints.
- **The benchmark solve does not currently converge.** A correctly
  calibrated benchmark is an equilibrium by construction (all equation
  residuals ≈ 0 at the start values). Here PATH starts from a residual of
  ≈6.1e3, stops at its iteration limit and reports
  `termination_status = ITERATION_LIMIT`, `primal_status = UNKNOWN_RESULT_STATUS`.
  Until this is fixed, shocks, dynamic runs and policy experiments run
  mechanically but their results are not meaningful.
- What has been fixed (2026-09-03): bilateral-trade start values are now
  derived from the aggregate imports/exports and the share parameters
  (`T-5…T-27` residuals ≈ 0), domestic-supply/export split uses the calibrated
  shares (`T-14`), land supply (`F-13`), the `beta_z` normalisation (`T-19`)
  and a double-applied share in `M_GOVDEM`/`M_INVDEM`.
- What remains (largest start residuals first, see `diagnose_model`):
  household Armington/bundle shares `GammaC`, `alpha_dc/mc/df/mf` are uniform
  defaults, not calibrated from the SAM (`D-5`, `D-10…D-13`); per-vintage
  production-nest start values use hard-coded fractions instead of the
  calibrated `alpha_*` (`P_*`, e.g. `P_67`); government revenue `C-3` cannot
  match because `tau_l/t/k/Ac/Af`, `kappa_h`, `pi` default to 0 while `YG` is
  calibrated as total SAM tax revenue; and the CET aggregator `T-16` is
  inconsistent with the value-share calibration of `beta_xd/beta_es`
  (needs a different CET parameterisation). These need modelling decisions,
  not just code fixes.
- Always check `termination_status(m)` after `solve_model!` — a run that
  "completes" is not the same as one that converged. `diagnose_model(m)`
  now reports each equation's residual at the start point
  (`residual_at_start`), which is the right metric to watch while fixing the
  calibration.

---

## Requirements

| Requirement | Notes |
|---|---|
| Julia ≥ 1.10 | `Manifest.toml` was resolved with 1.11; tested on 1.12.4 |
| PATH licence | A public courtesy licence is built in (valid to 31 Dec 2035). Set `PATH_LICENSE_STRING` to override it. |

Julia packages (installed automatically by `Pkg.instantiate()`):

| Package | Purpose |
|---|---|
| `JuMP`, `PATHSolver`, `Complementarity` | MCP formulation and PATH solver interface |
| `DataFrames` | Results tables |
| `XLSX` | Excel SAM input, dynamic/scenario workbooks |
| `Plots` | Optional charts of results and trajectories |

---

## Installation

```bash
git clone https://github.com/SebKrantz/SDCGE
cd SDCGE
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

The first `instantiate` precompiles JuMP and Plots and can take 5–15 minutes.

---

## Quick start

```julia
include("src/LinkageModel.jl")
using .LinkageModel
using JuMP

data = init_data()        # empty data container
prepare_data!(data)       # built-in synthetic 100-sector SAM → balance → calibrate
m = model(data)           # build the JuMP/PATH model (~15 s)
solve_model!(m)           # solve with PATH (~75 s)
termination_status(m)     # check this! see "Current status"
export_results!(m, data)  # write results/*.csv
```

One-call equivalent (results are only written if you ask for them):

```julia
m, data = run_linkage!(write_results=true)
```

Rough timings on a laptop: `include` 7 s, `prepare_data!` 6 s, `model` 14 s,
`solve_model!` ≈ 75 s.

---

## Output

`export_results!(m, data)` writes to `results/` (git-ignored):

| File | Contents |
|---|---|
| `results_all_variables.csv` | Every variable element: value, start value, change, % change |
| `results_summary.csv` | Named macro indicators (GDP, CPI, household income, government revenue `YG`, investment, savings, …) |
| `results_scalars.csv` | Scalar variables |
| `results_<VAR>.csv` | One file per major variable container, e.g. `results_XP.csv`, `results_GDP.csv`, `results_YH.csv`, `results_YG.csv` |
| `results_metadata.csv` | Solver termination/primal status and timestamp |
| `balanced_sam.csv`, `sam_balance_table.csv`, `sam_balance_summary.csv` | The RAS-balanced SAM and its row/column gaps |

In Julia, `results_dataframe(m)` returns the same table as
`results_all_variables.csv`. `pct_change_from_start` is the change relative
to the calibrated start value.

---

## Using your own SAM

The economy is defined by a square Social Accounting Matrix with **216
accounts** in the standard order (100 activities, 100 commodities, factors,
taxes, institutions, margins); see `data/csv/sam_accounts.csv`. The SAM is
RAS-balanced automatically and the balance report is written next to the
results.

```julia
# CSV: first row / first column hold the account labels
data = prepare_data!(init_data(); source=:csv, sam_path="data/csv/sam.csv")

# Excel: sheet "SAM" of the workbook
data = prepare_data!(init_data(); source=:excel, sam_path="data/linkage_100sector_data.xlsx")

m = model(data)
```

`examples/02_read_csv_sam.jl` and `03_read_excel_sam.jl` show the explicit
step-by-step version (`read_sam_csv!` → `validate_sam!` → `balance_sam_ras!`
→ `calibrate_from_sam!`).

---

## Applying a policy shock

All calibrated parameters live in `parameters(data)` (a `Dict{Symbol,Any}`,
stored in `data.metadata[:PAR]`). Modify them after `prepare_data!` and before
`model`:

```julia
data = prepare_data!(init_data())
PAR = parameters(data)
PAR[:tau_m][("R1", "R2", "P001")] = 0.20   # import tariff, index (r, rp, product)
m = model(data)
solve_model!(m)
```

Commonly used entries:

| Key | Description | Index |
|---|---|---|
| `:tau_m`, `:tau_e` | Import tariff / export tax rate | `(r, rp, product)` |
| `:tau_p` | Output tax rate | `product` |
| `:AT` | Total factor productivity | `product` |
| `:LSupply` | Labour supply | `"UnSkLab"` or `"SkLab"` |
| `:KSupply` | Capital supply | `(product, vintage)` |

---

## Recursive dynamics and policy experiments

```julia
# 10 periods; each period is one static solve, then K, L and A are updated
data, history, snapshots = run_recursive_dynamic!(periods=10, delta=0.05,
                                                  g_labor=0.02, g_tfp=0.015,
                                                  outdir="results/dynamic")
plot_dynamic_results("results/dynamic/dynamic_results.xlsx")

# Excel-driven batch of scenarios (one sheet per exogenous block)
write_policy_template("data/policy_experiments.xlsx"; periods=10, n_scenarios=10)
results = run_policy_experiments!("data/policy_experiments.xlsx";
                                  outdir="results/scenarios", make_plots=true)
```

See `examples/07_recursive_dynamics.jl` and `08_policy_experiments.jl`.

---

## Examples and tests

`examples/` contains nine numbered scripts from data preparation to the full
dynamic/policy pipeline; see `examples/README.md` for the list and runtimes.

```bash
julia examples/04_build_model.jl          # build only, prints variable/constraint counts
julia --project=. test/runtests.jl        # smoke test: SAM, CSV import, build, results labels (~1 min)
LCGE_TEST_SOLVE=true julia --project=. test/runtests.jl   # additionally solve (currently fails, see status)
```

---

## Diagnostics

```julia
print_model_diagnostics(m)   # variable/constraint counts and solver
diagnose_model(m)            # equation ↔ variable matching report in results/diagnostics/
```

---

## Troubleshooting

**`termination_status(m)` is `ITERATION_LIMIT`, not `LOCALLY_SOLVED`** —
see "Current status". This is the state of the shipped benchmark; a
`pct_change_from_start` far from zero is a symptom of the failed solve, not an
economic result.

**PATH licence error** — set `PATH_LICENSE_STRING` before starting Julia
(see [PATHSolver.jl](https://github.com/chkwon/PATHSolver.jl)); by default the
built-in courtesy licence is used.

**`SAM is not balanced`** — RAS balancing is applied automatically; large
residual gaps in `results/sam_balance_table.csv` mean the input SAM is
inconsistent.

**`MethodError` when reading a SAM** — make sure the CSV/Excel file has
exactly the 216 accounts listed in `data/csv/sam_accounts.csv`, in that order.

---

## Project layout

```
SDCGE/  (branch main)
├── src/
│   ├── LinkageModel.jl     module entry point; include order and exports
│   ├── Types.jl            LinkageData container, default_sets!
│   ├── SAM.jl              SAM accounts, synthetic SAM, CSV/Excel readers, RAS balancing
│   ├── Calibration.jl      calibrate_from_sam!
│   ├── ParameterTables.jl  precompute_parameters → PAR dictionary
│   ├── Functions.jl        CES / CET / Armington helper functions
│   ├── Initialization.jl   start values and bounds for all variables
│   ├── Variables.jl        @variables declarations
│   ├── Production.jl, Income.jl, Demand.jl, Trade.jl, Equilibrium.jl,
│   │   Closure.jl, Factors.jl, Other.jl   paper-numbered equation blocks (P-, Y-, D-, T-, E-, C-, F-)
│   ├── ModelBuilder.jl     prepare_data!, model/build_model, solve_model!, run_linkage!
│   ├── Results.jl          results_dataframe, export_results!
│   ├── Plotting.jl         plot_results, plot_dynamic_results, plot_all_scenarios
│   ├── Diagnostics.jl      diagnose_model, print_equation_diagnostics
│   ├── RecursiveDynamic.jl run_recursive_dynamic!
│   └── PolicyScenarios.jl  write_policy_template, run_policy_experiments!
├── data/                   synthetic SAM (CSV + Excel), policy_experiments.xlsx template
├── examples/               numbered walkthrough scripts (start here)
├── test/runtests.jl        smoke test
└── results/                generated output (git-ignored)
```

---

## What the model covers

| Feature | Detail |
|---|---|
| Sectors | 100 (crops P001–P010, livestock P011–P020, energy P071–P075, fertiliser P076–P078, other industry and services) |
| Regions | 4 (`R1`–`R4`) with bilateral trade |
| Labour | Unskilled and skilled, rural/urban zones, migration |
| Capital | Old (installed) and new (investment) vintages |
| Trade | Nested Armington import demand, CET export supply, tariff-rate quotas |
| Government | Output, intermediate, trade, factor and income taxes; fiscal balance |
| Households | One representative household; ELES/AIDADS-style demand system |
| Dynamics | Recursive: capital accumulation, labour growth, productivity growth |
