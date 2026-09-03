# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

LCGE-V4: a LINKAGE-style CGE model (100 sectors × 4 regions × 2 labour skills × 2 capital vintages) written as a square mixed complementarity problem in JuMP and solved with PATH. Module `LinkageModel` in `src/LinkageModel.jl`. There is no package name/UUID in `Project.toml`, so the module is always loaded from source:

```julia
include("src/LinkageModel.jl"); using .LinkageModel   # never `using LinkageModel`
```

The `envcge-v9` branch of this repo is an unrelated model (EnvCGE) with its own CLAUDE.md. Never merge the branches.

## Commands

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'        # once; 5–15 min (JuMP, Plots precompile)
julia --project=. test/runtests.jl                          # smoke test, ~1 min, no PATH call
LCGE_TEST_SOLVE=true julia --project=. test/runtests.jl     # + solve (currently FAILS, see below)
julia examples/04_build_model.jl                            # build only, prints counts
julia examples/05_solve_and_export.jl                       # build + solve + results/ + plots (~2 min)
```

Timings: `include` ≈7 s, `prepare_data!` ≈6 s, `model()` ≈14 s, `solve_model!` ≈75 s. Do not run `Pkg.resolve()`/`Pkg.update()` casually — the committed `Manifest.toml` (resolved on Julia 1.11, runs on 1.12) is the known-good environment.

## Pipeline and architecture

`prepare_data!` → `model` → `solve_model!` → `export_results!` (`run_linkage!` does all four; note its defaults `write_results=false, make_plots=false`).

- `Types.jl` — `LinkageData` (sets, SAM, calibrated tables, `metadata`). `default_sets!` defines the sets: 100 products `P001`–`P100` (also used as activities), regions `R1`–`R4`, vintages `Old`/`New`, labour `UnSkLab`/`SkLab`, one household `HH`, final-demand agents `Gov`/`Inv`. Energy = P071–P075, fertiliser = P076–P078, crops P001–P010, livestock P011–P020.
- `SAM.jl` — 216-account SAM (not 406, whatever old text says), synthetic default (`build_default_large_sam!`), CSV/Excel readers, RAS balancing. The SAM has **no regional dimension**; regional/bilateral structure is synthesised in `ParameterTables.jl` and `Initialization.jl`.
- `ParameterTables.jl::precompute_parameters` builds `PAR::Dict{Symbol,Any}` (stored as `data.metadata[:PAR]`, accessed via `parameters(data)`). Tables are `Dict` keyed by product or tuples such as `(r, rp, product)` for `:tau_m`, `(product, vintage)` for `:KSupply`. Policy shocks are applied by editing `PAR` between `prepare_data!` and `model`.
- `Variables.jl` declares every JuMP container; `Initialization.jl` sets start values/bounds; the equation files `Production/Income/Demand/Trade/Equilibrium/Closure/Factors/Other.jl` each add one paper-numbered block (`P-`, `Y-`, `D-`, `T-`, `E-`, `C-`, `F-`) as `@constraint(m, F ⟂ x)` pairs. Constraint names follow `<Block>_<n>[indices]`, e.g. `T_5[R1,P075]`.
- `ModelBuilder.jl` — `build_linkage_model!` calls the blocks in order; `solve_model!` runs `check_initialization!` first and errors on bad start values.
- `Results.jl` — `results_dataframe(m)` (one arg) and `export_results!`; per-variable CSVs are written only for containers that exist (legacy names in `common_variables` such as `GOVREV` silently produce nothing — the real variable is `YG`).
- `RecursiveDynamic.jl` re-solves the static model period by period, updating K/L/A between periods; `PolicyScenarios.jl` drives many trajectories from an Excel workbook (`write_policy_template` → edit → `run_policy_experiments!`). `Dynamics.jl` (paper G-equations) was removed; recursive dynamics live only in these two files.
- `Diagnostics.jl` — `diagnose_model` pairs each complementarity constraint with its variable via MOI `Complements` sets.

## Known state of the model (verified 2026-09-03)

- Build is square: 48,099 variables = 48,099 constraints.
- **The benchmark does not replicate.** PATH's residual at the start point is ≈6.1e3 (was 6.6e3), it diverges at `T_14[P075]` in the first major iteration and stops with `ITERATION_LIMIT` / `UNKNOWN_RESULT_STATUS`. Already fixed: bilateral-trade start values (built top-down from `XMT`/`ES` with `beta_1/2/w/z`; prices left at 1.0), `XDs`/`ES` split via `beta_xd`/`beta_es`, `TLnd` start, `beta_z = 1/(|r|·|rp|)`, and `M_GOVDEM`/`M_INVDEM` (now `= XAf[i,Gov]`/`XAf[i,Inv]`).
- Remaining start-residual sources, ranked (use `diagnostic_equation_matches(m)` → `residual_at_start`, aggregate by constraint family): (1) `Demand.jl` D-5/D-10…D-13 — `GammaC`, `alpha_dc/mc/df/mf` (`ParameterTables.jl` ~191–203) are uniform defaults, must be calibrated jointly with `theta`/`mu_c` from `XAc0`/`XAf0`; (2) `Production.jl` P_* — `Initialization.jl` per-vintage nest quantities use hard-coded fractions (`0.08*xp_per_v` …) instead of the calibrated `alpha_l/hkte/hktef/fert/e/h/kt` (`Calibration.jl` ~203–235); (3) `Closure.jl` C-3 — `tau_l/t/k/Ac/Af`, `kappa_h`, `pi` default 0 vs `YG` = total SAM taxes; (4) `Trade.jl` T-16 — CET primal aggregator only reproduces `X = ΣX_k` if `Σβ^(1+ρ) = 1`, incompatible with value-share `beta_xd/beta_es`; (5) `Factors.jl` F_Td_nonag/F_Ts_nonag force `Td = Ts = 0` outside `S[:ag]` while `chi_T`/`TSupply` starts sum over all `i` (the `TLnd` fix chose all-`i`; the ag-only convention is probably the consistent one — revisit together).
- Judge any calibration/initialisation change by whether the max start residual falls and PATH converges with variables unchanged; "no error" from `solve_model!` is not success — always check `termination_status(m)`. Dynamic runs and policy experiments complete mechanically but inherit the unconverged solves.
- Complementarity constraints are stored by JuMP as a positional `Vector` of scalar expressions (`func[1]` = F, `func[2]` = x), not MOI vector functions — `Diagnostics.jl` walks them that way.
- PATH licence is set in `LinkageModel.jl` from `PATH_LICENSE_STRING` if present, else a built-in courtesy licence.

## Conventions

- `results/` is git-ignored generated output; never commit it.
- Example scripts activate the project themselves (`Pkg.activate(joinpath(@__DIR__, ".."))`) so they run with plain `julia examples/xx.jl` from the repo root.
- Equation comments cite the LINKAGE paper numbering; keep the labels when editing an equation.
