# Usage:
#   julia examples/04_build_model.jl
#
# Prepare data and build the JuMP/PATH model without solving.
# Prints the variable/constraint counts (they must be equal for a square MCP).

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using JuMP
include(joinpath(@__DIR__, "..", "src", "LinkageModel.jl"))
using .LinkageModel

data = prepare_data!()
m = model(data)

println("Model built with PATH.")
println("JuMP variables:   ", num_variables(m))
println("JuMP constraints: ", num_constraints(m; count_variable_in_set_constraints=false))
print_model_diagnostics(m)
