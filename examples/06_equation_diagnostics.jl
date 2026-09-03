# Usage:
#   julia examples/06_equation_diagnostics.jl
#
# Build the MCP model without solving and write equation/variable matching
# diagnostics to results/diagnostics/ (variables without a complementary
# equation, variables matched by several equations, likely redundant equations).

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

include(joinpath(@__DIR__, "..", "src", "LinkageModel.jl"))
using .LinkageModel

m, data = run_linkage!(solve=false, show_solver_output=false)

diag = diagnose_model(m; outdir=joinpath(@__DIR__, "..", "results", "diagnostics"),
                      write_csv=true, verbose=true)

println("Summary table:")
show(diag[:summary]; allrows=true, allcols=true)
println()
