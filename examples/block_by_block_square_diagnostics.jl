# Run with:
#   julia --project=. examples/block_by_block_square_diagnostics.jl
# Optional:
#   julia --project=. examples/block_by_block_square_diagnostics.jl data/example_envcge_data.xlsx reports/path_square_blocks

include(joinpath(@__DIR__, "_example_preamble.jl"))
using EnvCGE

xlsx = length(ARGS) >= 1 ? example_path(ARGS[1]) : default_excel_path()
outdir = length(ARGS) >= 2 ? example_path(ARGS[2]) : joinpath(ENV_CGE_PROJECT_ROOT, "reports", "path_square_blocks")

println("Loading data: ", xlsx)
data = load_excel_data(xlsx)
cal = calibrate(data)

println("Building model block by block and checking PATH square counts...")
diag = path_square_block_diagnostics(data, cal; initialize=true, apply_closures=true, outdir=outdir, stop_on_error=false)

println("Final variables: ", diag["variable_count_total"])
println("Final non-bound equations: ", diag["constraint_count_excluding_bounds"])
println("Final gap variables - equations: ", diag["square_gap_total_variables"])
println("Square for PATH: ", diag["square_using_total_variables"])
println("Reports written to: ", outdir)
println("Open: ", joinpath(outdir, "block_square_summary.md"))
