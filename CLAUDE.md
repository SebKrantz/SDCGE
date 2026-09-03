# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

EnvCGE V9: a Julia port of the ENVISAGE v10.01 climate CGE model (multi-region, emissions, carbon cycle, recursive dynamics) as a mixed complementarity problem in JuMP for PATH. Module `EnvCGE` in `src/EnvCGE.jl`; `Project.toml` names the package, so with `--project=.` use `using EnvCGE` (not `using .EnvCGE`, which only works after `include("src/EnvCGE.jl")`).

The `main` branch of this repo is an unrelated model (LCGE-V4) with its own CLAUDE.md. Never merge the branches.

## Commands

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'     # once
julia --project=. test/runtests.jl                       # smoke test, ~30 s, no PATH call
julia --project=. examples/run_example.jl                # calibrate → build → reports/path_square/ → solve if square
julia --project=. examples/block_by_block_square_diagnostics.jl   # per-block variable/equation gap → reports/path_square_blocks/
```

Timings: `calibrate_from_excel()` ≈3 s, `path_square_diagnostics` ≈7 s, `build_model` ≈7 s.

## Pipeline and architecture

`load_default_data` → `calibrate` (or `calibrate_from_excel()` for both) → `build_model(data, cal; initialize=true, audit_mapping=true, require_square=false)` → `path_square_diagnostics` / `write_path_square_report` → `solve!`.

- `types.jl`: `EnvSets` (r, a, i, factors, households, …), `EnvData` (sets, raw sheets in `data.par`), `EnvCalibration` (benchmark flows, `cal.benchmark`), `EnvModel` (`em.jump` is the JuMP model, `em.solution` holds reports).
- `io.jl` reads `data/example_envcge_data.xlsx`. Only `sets`, `sam`, `make`, `use`, `final_demand`, `factor_demand`, `closures` carry data; the other sheets are empty and every elasticity/tax/emission/dynamic parameter comes from defaults in `ParameterTables.jl`.
- **`ParameterTables.jl::parameters(data, cal)` is the single source of parameters used by the equation blocks.** `calibration.jl::_calibrate_alpha` fills `cal.alpha` but nothing reads it — change share parameters in `ParameterTables.jl`, not there.
- Equation blocks (`production.jl` P, `supply.jl` S, `income.jl` Y, `demand.jl` D, `trade.jl` T, `markets.jl` E, `factors.jl` F, `closure.jl` M, `emissions.jl` EM) each add JuMP variables (guarded `if !haskey` declarations, so a block may pre-declare families used later) and `@constraint` equations named after the ENVISAGE label. `model.jl::build_model` calls them in that order, then `apply_initial_values!` and `apply_excel_closures!` (fixes the variables listed in the `closures` sheet).
- Registries: `equations_registry.jl` (ENVISAGE labels ↔ source file, `equation_coverage_report`), `path_mapping.jl` (`equation_variable_map`, `path_mapping_report`), `mcp.jl` (`mcp_pair_registry`, 247 pairs). Keep these in sync when adding or removing an equation — `audit_mapping=true` checks them at build time.
- `path_square_diagnostics.jl`: `path_square_diagnostics(data, cal)` returns counts without throwing; `preflight_path_square` / `assert_path_square_preflight!` throw when not square; `path_square_block_diagnostics` rebuilds block by block.
- `climate.jl` is a standalone 3-box carbon-cycle/temperature/damage model driven by the model's global emissions (`climate_state(cal)`, `climate_step!(em, st; dt)`, `run_climate_path!`). `dynamics.jl` propagates capital/labour/productivity state between periods (`dynamics_update!`, `run_recursive_dynamic!`, which calls `solve!` each period).

## Known state of the model (verified 2026-09-03)

- **PATH cannot be called yet: all equations are `@NLconstraint`.** PATHSolver.Optimizer only accepts `MOI.Complements` constraints (`@constraint(m, [F, x] in MOI.Complements(2))`, i.e. `F ⟂ x`) and rejects `@NLconstraint` models ("The solver does not support nonlinear problems"). Converting the ≈200 equation sites requires the complementary variable for each — use the pairing in `path_mapping.jl::equation_variable_map` / `mcp.jl::mcp_pair_registry`. Do this together with closing the remaining gap; a half-converted model does not load.
- Squareness is measured on **free** variables (`nfree == ncon`; JuMP-fixed variables are pinned by bounds): 27,128 free vs 26,793 equations, gap 335 (from 45,900/26,282 on the upstream code). Judge any change by `path_square_diagnostics(data, cal)`, `path_mapping_report` (must stay empty of missing/extra/undeclared) and the block script. Remaining gap: `VA2`/`PVA2`/`ND2` over default activities (ENVISAGE Table 3.2: default nest is `VA1 = CES(XF_lnd, KEF)`, not `VA2` — fix `def_va1` components in `ParameterTables.jl`, add a default branch to P-14, restrict `VA2/PVA2/ND2` to `acr ∪ alv`), and `PP`/`X` for electricity (with empty `etd` and no `pbmap`, fold `ely` into the generic S-1…S-5 block and skip S-6…S-14), plus ≈60 in small families (`EmiCap`, `TH2Om`, `TR`, `gy`, `XFD`/`YFD`).
- Closure switches in `data.par`: `invClosure` ("gtap" M-18 default | "flexSf" M-19 | "usage" M-21) and `capClosure` ("vintage" F-15…F-24 default | "static" F-12/F-13; in static mode `Klo/Khi/K0/RR/kxRat` are still declared and undetermined). `closure.jl::apply_default_closures!` (called by `build_model` after `apply_excel_closures!`, workbook rules win) fixes 372 exogenous instances at start values: `K0`, `Ks`, `LSz` (all but first zone), `YFD[r,gov]`, `μc`, `EmiOth*`/`EmiQ`/`τEmiQ`, `Rd`, `PXGHG`, non-agricultural land cells of `XF`/`PF`.
- Agent-sourcing trade families (`XWa`, `PDMa`, `XD`, `XM`, `PMa`, `PM`, `PD`; T-6…T-18) are declared only when `ArmFlag != 0` (the workbook has none); `path_mapping.jl` maps those equations to the national-sourcing variables when inactive. `PAa`, `XANRG`/`PANRG`, `YC`, `UEMin`, `XNRFs`, `gY` were deleted; `ZC` exists only under CDE demand; water bundles (`H2OBnd*`) only for matched labels, else a single-bundle fallback (F-43/F-48/F-50) is generated.
- Benchmark replication is not attempted yet: 36 % of equations have non-zero start residuals (max Inf on M-33 EV from `exp` overflow at the default `u`), because `ParameterTables.jl` shares/elasticities are defaults while `initialization.jl` start values come from the SAM. The fix is deriving every `alpha_*` from the benchmark flows at prices 1 (where `calibration.jl::_calibrate_alpha` should live).
- Label caveats: the port's "M-27/M-28" slots hold EV (= document M-33) and `CV == 0` (no CV equation in ENVISAGE v10.01); the document's M-27/M-28 are PFACT/PWGDP. M-34–M-39 not ported; G-10–G-12 twist functions not called. Land is treated as agriculture-only — conflicts with Table 3.2 and should be revisited with the `VA2` fix.
- Solving needs a PATH licence for this size: set `PATH_LICENSE_STRING` (free courtesy licence).
- `legacy_standard_cge/` (a separate Ipopt toy model) was removed; do not reintroduce it.

## Conventions

- `reports/` is git-ignored output from the diagnostics; never commit it.
- Examples `include("_example_preamble.jl")` (activates the project) then `using EnvCGE`.
- Equation comments cite ENVISAGE labels (`# P-1`, `# M-9`); keep them accurate when editing equations, and update `equations_registry.jl`/`mcp.jl` accordingly.
