# Usage:
#   julia examples/09_full_pipeline.jl
#
# End-to-end pipeline run (long: several hours with the default template):
#   1. Static solve (build + single-period PATH solve)
#   2. Single dynamic trajectory (10 periods)
#   3. All active policy experiments from data/policy_experiments.xlsx

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

include(joinpath(@__DIR__, "..", "src", "LinkageModel.jl"))
using .LinkageModel
using JuMP  # value() / status accessors

const PIPE_T0 = time()
_dt() = round(time() - PIPE_T0; digits=1)

println("================================================================")
println("  LINKAGE — End-to-end pipeline")
println("================================================================")

# ─────────────────────────────────────────────────────────────────────────────
# 1. STATIC: build + single PATH solve
# ─────────────────────────────────────────────────────────────────────────────
println("\n[1/3] STATIC MODEL  (t=$(_dt())s)")
println("-----------------------------------------------------------")
m_static, data_static = run_linkage!(solve=true, show_solver_output=false)
i = data_static.sets[:i]
gdp_static = value(m_static[:GDP]["R1"])
sumPPXP    = sum(value(m_static[:PP][ii]) * value(m_static[:XP][ii]) for ii in i)
println("  STATIC status: ", termination_status(m_static), " / ", primal_status(m_static))
println("  GDP[R1] = ", round(gdp_static, digits=1),
        "  Σ PP·XP = ", round(sumPPXP, digits=1),
        "  (t=$(_dt())s)")

# ─────────────────────────────────────────────────────────────────────────────
# 2. DYNAMIC: 10-period recursive solve (single trajectory)
# ─────────────────────────────────────────────────────────────────────────────
println("\n[2/3] SINGLE 10-PERIOD DYNAMIC RUN  (t=$(_dt())s)")
println("-----------------------------------------------------------")
data_dyn, hist_dyn, _ = run_recursive_dynamic!(
    periods            = 10,
    delta              = 0.05,
    g_labor            = 0.02,
    g_tfp              = 0.015,
    outdir             = "results/dynamic",
    show_solver_output = false,
)
println("  DYNAMIC complete.  Final GDP=", round(hist_dyn[end].GDP_R1, digits=1),
        "  K=", round(hist_dyn[end].KS, digits=1),
        "  (t=$(_dt())s)")
println("  Output:  results/dynamic/dynamic_results.xlsx")
println("           results/dynamic/plots/")

# ─────────────────────────────────────────────────────────────────────────────
# 3. POLICY EXPERIMENTS: all active scenarios from data/policy_experiments.xlsx
# ─────────────────────────────────────────────────────────────────────────────
println("\n[3/3] POLICY EXPERIMENTS  (t=$(_dt())s)")
println("-----------------------------------------------------------")
template = joinpath(@__DIR__, "..", "data", "policy_experiments.xlsx")
if !isfile(template)
    println("  Generating template: ", template)
    mkpath(dirname(template))
    write_policy_template(template; periods=10, n_scenarios=10)
end

scenarios = read_policy_scenarios(template)
println("  Template:   ", template)
println("  Scenarios:  ", length(scenarios), " active")
for s in scenarios
    println("    [", s.sim_id, "] ", s.name, " — periods=", s.periods)
end

results = run_policy_experiments!(template;
    outdir="results/scenarios",
    make_plots=true,
    show_solver_output=false)

# ─────────────────────────────────────────────────────────────────────────────
#  Final summary
# ─────────────────────────────────────────────────────────────────────────────
println("\n================================================================")
println("  PIPELINE COMPLETE  (total t=$(_dt())s)")
println("================================================================")
println("\nScenario final outcomes (period $(scenarios[1].periods)):")
println("  ", rpad("scenario", 22), "  ", lpad("GDP[R1]", 12),
        "  ", lpad("YH", 12), "  ", lpad("K", 12))
for scen in scenarios
    haskey(results, scen.name) || continue
    h = results[scen.name][2]
    isempty(h) && continue
    last = h[end]
    println("  ", rpad(scen.name, 22),
            "  ", lpad(round(last.GDP_R1, digits=1), 12),
            "  ", lpad(round(last.YH_HH,  digits=1), 12),
            "  ", lpad(round(last.KS,     digits=1), 12))
end
println("\nKey outputs:")
println("  Static:     results/balanced_sam.csv")
println("  Dynamic:    results/dynamic/dynamic_results.xlsx + plots/")
println("  Scenarios:  results/scenarios/all_scenarios_results.xlsx + plots/")
