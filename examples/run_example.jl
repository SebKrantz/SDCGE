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
println("Initial value report: ", em.solution["initial_values"])
println("Variables:   ", JuMP.num_variables(em.jump))
println("Constraints: ", JuMP.num_constraints(em.jump; count_variable_in_set_constraints=false))

diag = write_path_square_report(em; outdir=outdir)
println("Square for PATH: ", diag["square_using_total_variables"],
        "  (gap = ", diag["square_gap_total_variables"], ")")
println("Diagnostic reports: ", outdir)

if diag["square_using_total_variables"]
    sol = solve!(em; require_square=true)
    println(sol)
else
    println("Model is not square. Inspect ", joinpath(outdir, "path_square_summary.md"),
            " before calling solve!.")
end
