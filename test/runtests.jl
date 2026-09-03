# Smoke test: SAM preparation (default and CSV), model build, squareness and
# results export. Does not call PATH unless LCGE_TEST_SOLVE=true is set.
# Run with:  julia --project=. test/runtests.jl   (or Pkg.test())

using Test
include(joinpath(@__DIR__, "..", "src", "LinkageModel.jl"))
using .LinkageModel
using JuMP
using DataFrames

@testset "LCGE-V4 smoke test" begin
    data = prepare_data!()
    @test length(data.sam_accounts[:all]) == 216
    @test sam_balance_summary(data)[:max_abs_gap] < 1e-6

    # Bring-your-own SAM path (CSV).
    d2 = init_data()
    default_sets!(d2)
    setup_sam_accounts!(d2)
    read_sam_csv!(d2, joinpath(@__DIR__, "..", "data", "csv", "sam.csv"))
    @test size(d2.sam) == (216, 216)

    m = model(data; show_solver_output=false)
    nv = num_variables(m)
    nc = num_constraints(m; count_variable_in_set_constraints=false)
    println("variables = $nv, constraints = $nc")
    @test nv == nc

    df = results_dataframe(m)
    @test nrow(df) == nv
    @test !any(occursin("CartesianIndex", string(x)) for x in df.index)

    if get(ENV, "LCGE_TEST_SOLVE", "false") == "true"
        solve_model!(m; output="no", show_diagnostics=false)
        println("termination_status = ", termination_status(m))
        @test termination_status(m) in (MOI.LOCALLY_SOLVED, MOI.OPTIMAL)
    end
end
