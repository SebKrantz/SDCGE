# Usage:
#   julia examples/05_solve_and_export.jl
#
# Prepare -> build -> solve with PATH -> write CSV results -> plot.
# Always check the termination status: PATH may stop at its iteration limit
# without finding an equilibrium (see README, "Current status").

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using JuMP
include(joinpath(@__DIR__, "..", "src", "LinkageModel.jl"))
using .LinkageModel

data = prepare_data!()
m = model(data)

status = solve_model!(m)
println("PATH status:        ", status)
println("termination_status: ", termination_status(m))
println("primal_status:      ", primal_status(m))

results_dir = joinpath(@__DIR__, "..", "results")
export_results!(m, data; outdir=results_dir)
println("Results written to: ", results_dir)

try
    plot_files = plot_results(results_dir; outdir=joinpath(results_dir, "plots"))
    println("Plot files written:")
    foreach(println, plot_files)
catch err
    @warn "Plots were not created. Install Plots.jl to enable plotting." exception=(err, catch_backtrace())
end
