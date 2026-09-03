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
    println("square check: ", diag["variable_count_free"], " free variables (",
            diag["variable_count_total"], " total, ", diag["variable_count_fixed"],
            " fixed) vs ", diag["constraint_count_excluding_bounds"],
            " equations; gap = ", diag["square_gap_free_variables"])

    # Regression guards on the squaring work.  The gap is the number of free
    # variables still lacking a determining equation; it must not grow.
    @test diag["square_gap_free_variables"] <= 335
    @test diag["variable_count_fixed"] >= 397

    # The equation/variable registries must stay consistent with the blocks.
    rep = diag["path_mapping_report"]
    @test isempty(rep["missing_mapping"])
    @test isempty(rep["extra_mapping"])
    @test isempty(rep["undeclared_mapped_variable_families"])

    em = build_model(data, cal; initialize=true, audit_mapping=true, require_square=false)
    @test JuMP.num_variables(em.jump) == diag["variable_count_total"]

    # Exactly one of the three alternative capital-account closures M-18/M-19/
    # M-21 may determine Re; the default is the GTAP form M-18.
    @test get(data.par, "invClosure", "gtap") == "gtap"

    # Removed / conditionally declared families must really be gone.
    for dead in [:PAa, :XANRG, :PANRG, :YC, :ZC, :UEMin, :XNRFs, :gY]
        @test !haskey(JuMP.object_dictionary(em.jump), dead)
    end

    # Optional PATH solve, gated because PATHSolver needs a licence for a model
    # of this size and the system is not square yet.
    if get(ENV, "ENVCGE_TEST_SOLVE", "false") == "true"
        sol = solve!(em; require_square=true)
        @test haskey(sol, "status")
    end

    # Climate module runs standalone from JuMP start values.
    st = climate_state(cal)
    climate_step!(em, st; dt=1.0)
    @test st.MAT > 0
    @test 0 < climate_damage_factor(st) <= 1
end
