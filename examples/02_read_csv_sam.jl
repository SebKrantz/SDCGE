# Usage:
#   julia examples/02_read_csv_sam.jl
#
# Read the CSV SAM (data/csv/sam.csv), balance it with RAS, and calibrate.
# Equivalent one-liner: prepare_data!(init_data(); source=:csv, sam_path=...)

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

include(joinpath(@__DIR__, "..", "src", "LinkageModel.jl"))
using .LinkageModel

sam_path = joinpath(@__DIR__, "..", "data", "csv", "sam.csv")
isfile(sam_path) || error("CSV SAM file not found: $(sam_path)")

data = init_data()
default_sets!(data)
setup_sam_accounts!(data)
read_sam_csv!(data, sam_path)
validate_sam!(data; require_balanced=false)
balance_sam_ras!(data)
assert_balanced_sam!(data)
calibrate_from_sam!(data)

println("CSV SAM read, balanced, and calibrated.")
println("Accounts: ", length(data.sam_accounts[:all]))
println("Calibrated products: ", length(data.sets[:i]))
println("Maximum balanced SAM gap: ", sam_balance_summary(data)[:max_abs_gap])
