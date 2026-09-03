# Usage:
#   julia examples/07_recursive_dynamics.jl
#
# Recursive-dynamic LINKAGE solve over 10 periods.
#
# Each period is a static MCP solve.  Between periods, capital, labor and
# productivity are updated using the previous-period solution:
#
#     K[t+1] = (1 − δ) · K[t]   + investment_t
#     L[t+1] = (1 + g_l)        · L[t]
#     A[t+1] = (1 + g_tfp)      · A[t]
#
# Outputs (under results/dynamic/):
#     dynamic_results.xlsx   consolidated workbook, one sheet per variable
#     time_series.csv        10 rows × macro indicators
#     plots/                 trajectories (requires Plots.jl)
#
# Each period takes roughly as long as one static solve (~1–2 minutes).

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

include(joinpath(@__DIR__, "..", "src", "LinkageModel.jl"))
using .LinkageModel

println("================================================================")
println("  LINKAGE Recursive-Dynamic Run (10 periods)")
println("================================================================")
println("  δ (capital depreciation): 0.05")
println("  g_labor (labor growth):   0.02")
println("  g_tfp (productivity):     0.015")
println("  g_land / g_nres:          0.0 / 0.0")
println("  Output directory:         results/dynamic/")
println("================================================================")

outdir = "results/dynamic"

data, history, snapshots = run_recursive_dynamic!(
    periods            = 10,
    delta              = 0.05,
    g_labor            = 0.02,
    g_tfp              = 0.015,
    g_land             = 0.0,
    g_nres             = 0.0,
    outdir             = outdir,
    show_solver_output = false,
)

println("\n================================================================")
println("  Dynamic run complete — time-series summary:")
println("================================================================")
for row in history
    gdp  = row.GDP_R1 isa Real ? round(row.GDP_R1,  digits=1) : missing
    rgdp = row.RGDP_R1 isa Real ? round(row.RGDP_R1, digits=1) : missing
    pgdp = row.PGDP_R1 isa Real ? round(row.PGDP_R1, digits=4) : missing
    yh   = row.YH_HH isa Real ? round(row.YH_HH,    digits=1) : missing
    inv  = row.INVEST isa Real ? round(row.INVEST,  digits=1) : missing
    ks   = row.KS isa Real ? round(row.KS,          digits=1) : missing
    println("  t=", row.period,
            "  GDP=", gdp,
            "  RGDP=", rgdp,
            "  PGDP=", pgdp,
            "  YH=", yh,
            "  INV=", inv,
            "  K=", ks)
end

println("\nGenerating plots ...")
try
    files = plot_dynamic_results(joinpath(outdir, "dynamic_results.xlsx");
                                 outdir=joinpath(outdir, "plots"))
    println("  ", length(files), " plot files written to ", joinpath(outdir, "plots"))
catch err
    @warn "Plotting failed — likely missing Plots.jl. Run `import Pkg; Pkg.add(\"Plots\")` to enable." exception=(err, catch_backtrace())
end

println("\nConsolidated Excel: ", joinpath(outdir, "dynamic_results.xlsx"))
println("Time series CSV:    ", joinpath(outdir, "time_series.csv"))
println("Plots:              ", joinpath(outdir, "plots"))
