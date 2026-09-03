# === Function usage ===
# Core data containers and coefficient accessors.
# Usage:
#   data = load_default_data()              # returns EnvData
#   cal  = calibrate(data)                  # returns EnvCalibration
#   sets = data.sets                        # EnvSets
#   PAR = parameters(data, cal)                  # precomputed parameter table
#   sigma_arm                           # scalar elasticity
#   tau_m                               # tax parameter
# ======================

const DictSS = Dict{String,String}
const DictSV = Dict{String,Vector{String}}
const ArrKey = NTuple{N,String} where N

struct EnvSets
    # Table 3.1 core accounts and activity/commodity sets
    aa::Vector{String}; a::Vector{String}; acr::Vector{String}; alv::Vector{String}; ax::Vector{String}; elya::Vector{String}; ely::Vector{String}; etd::Vector{String}; z::Vector{String}
    i::Vector{String}; inum::Vector{String}; k::Vector{String}; nrg::Vector{String}
    # Table 3.1 factor sets.  `f` is kept as a compatibility alias for `fp`.
    fp::Vector{String}; f::Vector{String}; l::Vector{String}; ul::Vector{String}; sl::Vector{String}; cap::Vector{String}; lnd::Vector{String}; nrs::Vector{String}; wat::Vector{String}
    # Table 3.1 final demand and government revenue subsets
    fd::Vector{String}; fdc::Vector{String}; h::Vector{String}; gov::Vector{String}; inv::Vector{String}
    gy::Vector{String}; itax::Vector{String}; ptax::Vector{String}; mtax::Vector{String}; etax::Vector{String}; vtax::Vector{String}; ctax::Vector{String}; dtax::Vector{String}
    # Regions and emission types from Table 3.1, plus model-extension sets used later in the documentation
    r::Vector{String}; rnum::Vector{String}; rres::Vector{String}; em::Vector{String}
    v::Vector{String}; pb::Vector{String}; lb::Vector{String}; wbnd::Vector{String}; t::Vector{String}
end

mutable struct EnvData
    sets::EnvSets
    tables::Dict{String,DataFrame}
    par::Dict{String,Any}
    sam::DataFrame
end

mutable struct EnvCalibration
    alpha::Dict{String,Any}
    sigma::Dict{String,Any}
    lambda::Dict{String,Any}
    taxes::Dict{String,Any}
    benchmark::Dict{String,Any}
    emissions::Dict{String,Any}
    climate::Dict{String,Any}
end

mutable struct EnvModel
    data::EnvData
    calib::EnvCalibration
    jump::Union{Nothing,JuMP.Model}
    equations::OrderedDict{String,String}
    residuals::Dict{String,Function}
    solution::Dict{String,Any}
end

safeget(d::AbstractDict, k, default=0.0) = haskey(d,k) ? d[k] : default
safeget(d, k, default=0.0) = default

# Membership helpers for Table 3.1 subsets.  They default to false
# if the aggregation does not define a subset.
is_crop(s::EnvSets, a::String) = a in s.acr
is_livestock(s::EnvSets, a::String) = a in s.alv
is_other_activity(s::EnvSets, a::String) = a in s.ax

"""
    default_activities(s::EnvSets)

The activity set for the "all other activities" branch of the ENVISAGE
production nests P-9:P-17.  The document splits `a` into crops (`acr`),
livestock (`alv`) and everything else; the workbook's `ax` set lists only the
non-agricultural, non-power activities, so using `ax` directly leaves the power
activities (`elya`) without any value-added nest.  This helper returns the
document's default branch, `a \\ (acr ∪ alv)`.
"""
default_activities(s::EnvSets) = [a for a in s.a if !(a in s.acr) && !(a in s.alv)]
is_power_activity(s::EnvSets, a::String) = a in s.elya
is_electric_commodity(s::EnvSets, i::String) = i in s.ely
is_transmission_distribution_activity(s::EnvSets, a::String) = a in s.etd
is_default_activity(s::EnvSets, a::String) = is_other_activity(s,a)
is_energy(s::EnvSets, x::String) = x in s.nrg
is_consumed_commodity(s::EnvSets, x::String) = x in s.k
is_land_factor(s::EnvSets, f::String) = f in s.lnd
is_capital_factor(s::EnvSets, f::String) = f in s.cap
is_resource_factor(s::EnvSets, f::String) = f in s.nrs
is_water_factor(s::EnvSets, f::String) = f in s.wat
is_labor_factor(s::EnvSets, f::String) = f in s.l
is_final_nonhousehold(s::EnvSets, fd::String) = fd in s.fdc
is_government_fd(s::EnvSets, fd::String) = fd in s.gov
is_investment_fd(s::EnvSets, fd::String) = fd in s.inv
