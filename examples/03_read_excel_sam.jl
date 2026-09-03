# Usage:
#   julia examples/03_read_excel_sam.jl
#
# Read the Excel SAM (sheet "SAM" of data/linkage_100sector_data.xlsx),
# balance it with RAS, and calibrate.
# Equivalent one-liner: prepare_data!(init_data(); source=:excel, sam_path=...)

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

include(joinpath(@__DIR__, "..", "src", "LinkageModel.jl"))
using .LinkageModel

sam_path = joinpath(@__DIR__, "..", "data", "linkage_100sector_data.xlsx")
isfile(sam_path) || error("Excel SAM file not found: $(sam_path)")

data = init_data()
default_sets!(data)
setup_sam_accounts!(data)
read_sam_excel!(data, sam_path)
validate_sam!(data; require_balanced=false)
balance_sam_ras!(data)
assert_balanced_sam!(data)
calibrate_from_sam!(data)

println("Excel SAM read, balanced, and calibrated.")
println("Accounts: ", length(data.sam_accounts[:all]))
println("Maximum balanced SAM gap: ", sam_balance_summary(data)[:max_abs_gap])
