# Usage:
#   julia examples/08_policy_experiments.jl
#
# Policy-experiment driver.
#
# 1. If data/policy_experiments.xlsx doesn't exist, generate a starter template
#    with 10 pre-populated scenarios and 10 periods.
# 2. Read the workbook and run every scenario whose `active` cell is "yes".
# 3. Each scenario writes a consolidated XLSX + plots to its own folder
#    under results/scenarios/<scenario_name>/, plus a cross-scenario
#    all_scenarios_results.xlsx.
#
# To design experiments, open policy_experiments.xlsx in Excel and overwrite
# any of: AT_by_activity, g_labor_by_skill, g_land, g_nres values for each
# simulation, then re-run this script.
#
# Runtime: each scenario-period is one static solve (~1–2 minutes), so the
# full 10×10 template takes several hours. Set fewer scenarios to "yes" or use
# write_policy_template(path; periods=3, n_scenarios=2) for a quick check.

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

include(joinpath(@__DIR__, "..", "src", "LinkageModel.jl"))
using .LinkageModel

template_path = joinpath(@__DIR__, "..", "data", "policy_experiments.xlsx")

if !isfile(template_path)
    println("Generating policy template at: ", template_path)
    mkpath(dirname(template_path))
    write_policy_template(template_path; periods=10, n_scenarios=10)
    println("Template created. Edit it in Excel to design experiments, then re-run.")
else
    println("Using existing policy template: ", template_path)
end

println("\n================================================================")
println("  Running policy experiments from: ", basename(template_path))
println("================================================================")

results = run_policy_experiments!(template_path;
            outdir="results/scenarios",
            make_plots=true,
            show_solver_output=false)

println("\n================================================================")
println("  All scenarios complete (", length(results), " scenarios)")
println("================================================================")
for name in sort(collect(keys(results)))
    _, history, _ = results[name]
    last_period = history[end]
    println("  ", name,
            ":   final GDP=", round(last_period.GDP_R1, digits=1),
            "   YH=", round(last_period.YH_HH, digits=1),
            "   K=", round(last_period.KS, digits=1))
end
println("\nConsolidated results: results/scenarios/all_scenarios_results.xlsx")
println("Comparison plots:     results/scenarios/plots/")
