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

- With the shipped workbook the system is **not square**: 29,547 variables vs 26,274 non-bound equations (gap 3,273; was 45,900 vs 26,282 before the 2026-09-03 cleanup). `solve!` refuses until this is fixed; judge any change by re-running `path_square_diagnostics(data, cal)` and the block script. The workbook has no `ArmFlag`/`ifMRIO`, so the agent-sourcing trade families (`XWa`, `PDMa`, `XD`, `XM`, `PMa`, `PM`, `PD`; T-6…T-18) are now declared only when `ArmFlag != 0`, and `path_mapping.jl` maps those equations to the national-sourcing variables (`XDTd`, `XMT`, `PDT`, `PMT`, `XWd`, `PDM`) when inactive.
- **Over-determination to resolve first:** `closure.jl` defines `Re[r]` three times — M-18 (GTAP `Re = Rc·(TKe/TKs)^(-eps)`), M-19 (`Re = Rg + Rd`), M-21 (USAGE form). ENVISAGE chooses one by closure switch; this port has none, so 9 equations determine 3 variables. Pick one (and add the switch) before any solve.
- Remaining unused declarations (≈660 instances): `Emi` slices, `VA2`/`PVA2`/`PVA1`/`ND2` (P-9…P-17 only apply to `acr ∪ alv`), `kxRat` (old vintage only), `QFD`, `PLBN`; pure dead: `ZC` (CDE only), `UEMin`, `YC`, `PH2OBnd*`/`H2OBndd`/`PTH2On` (water bundles never match `s.wbnd`). Beyond those, ≈2,600 variables are referenced but lack a determining equation — needs equation-level analysis against the ENVISAGE document.
- Still-placeholder equations: M-27/M-28 (EV/CV are `YFD - YFD`); M-32–M-39 not ported. `dynamics.jl` G-10–G-12 twist functions are defined but not called. Removed as duplicates/tautologies: M-9, the `r == rres` branch of M-14, M-25 (= M-10), D-36 (= D-37 on `h ⊆ fd`).
- Solving needs a PATH licence for this size: set `PATH_LICENSE_STRING` (free courtesy licence).
- `legacy_standard_cge/` (a separate Ipopt toy model) was removed; do not reintroduce it.

## Conventions

- `reports/` is git-ignored output from the diagnostics; never commit it.
- Examples `include("_example_preamble.jl")` (activates the project) then `using EnvCGE`.
- Equation comments cite ENVISAGE labels (`# P-1`, `# M-9`); keep them accurate when editing equations, and update `equations_registry.jl`/`mcp.jl` accordingly.
