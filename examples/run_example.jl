# End-to-end build example. Loads the Excel data, calibrates, builds and
# initializes the model, writes the PATH square-system diagnostics to
# reports/path_square/, and only solves if the system is square.
# Run with:
#   julia --project=. examples/run_example.jl

include(joinpath(@__DIR__, "_example_preamble.jl"))
using EnvCGE
using JuMP

outdir = joinpath(ENV_CGE_PROJECT_ROOT, "reports", "path_square")
data, cal = calibrate_from_excel()

em = build_model(data, cal; initialize=true, audit_mapping=true, require_square=false)
iv = em.solution["initial_values"]
println("Initial values: applied=", get(iv, "applied", "?"), " unresolved=", get(iv, "unresolved", "?"),
        " from SAM calibration=", get(iv, "derived_from_excel_sam_calibration", "?"))
println("Variables:   ", JuMP.num_variables(em.jump))
println("Constraints: ", JuMP.num_constraints(em.jump; count_variable_in_set_constraints=false))

diag = write_path_square_report(em; outdir=outdir)
println("Free variables: ", diag["variable_count_free"], "  (", diag["variable_count_fixed"], " fixed)")
println("Square for PATH: ", diag["square_using_free_variables"],
        "  (gap = ", diag["square_gap_free_variables"], ")")
println("Diagnostic reports: ", outdir)

if diag["square_using_free_variables"]
    sol = solve!(em; require_square=true)
    println(sol)
else
    println("Model is not square. Inspect ", joinpath(outdir, "path_square_summary.md"),
            " before calling solve!.")
end
