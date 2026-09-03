# Smoke test: data loading, calibration, model build, square diagnostics and
# the standalone climate module. Does not call PATH.
# Run with:  julia --project=. -e 'using Pkg; Pkg.test()'   or   julia --project=. test/runtests.jl

using Test
using EnvCGE
using JuMP

@testset "EnvCGE smoke test" begin
    data, cal = calibrate_from_excel()
    @test length(data.sets.r) == 3
    @test length(data.sets.a) == 21
    @test length(data.sets.i) == 20

    # Non-throwing square check (preflight_path_square throws when not square).
    diag = path_square_diagnostics(data, cal)
    @test diag["variable_count_total"] > 0
    @test diag["constraint_count_excluding_bounds"] > 0
    println("square check: ", diag["variable_count_total"], " variables vs ",
            diag["constraint_count_excluding_bounds"], " equations; square = ",
            diag["square_using_total_variables"])

    em = build_model(data, cal; initialize=true, audit_mapping=true, require_square=false)
    @test JuMP.num_variables(em.jump) == diag["variable_count_total"]

    # Climate module runs standalone from JuMP start values.
    st = climate_state(cal)
    climate_step!(em, st; dt=1.0)
    @test st.MAT > 0
    @test 0 < climate_damage_factor(st) <= 1
end
