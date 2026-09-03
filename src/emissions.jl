# ENVISAGE v10.01 §3.10 Emissions, equations E-1:E-8.
#
# This file implements only the emissions equations printed in the ENVISAGE
# documentation.  Equation labels are written one-by-one immediately above the
# corresponding JuMP equation.

function _emission_source_set(s::EnvSets)
    # The document defines `is` as the master source set: SAM labels plus `tot`.
    return unique(vcat(s.i, s.fp, ["tot"]))
end

function _emission_aa_set(s::EnvSets)
    # Consumption emissions use aa; factor and process emissions use activities,
    # which are a subset of aa in the document.  Keep the union so the single
    # document variable family Emi[r,em,is,aa] can store all source types.
    return unique(vcat(s.aa, s.a))
end

"""
    _emi_slice_active(s, src, ag)

Sparsity pattern of the ENVISAGE emissions variable `Emi[r,em,is,aa]`:
`(i, aa) ∪ (f, a) ∪ ("tot", a)` — commodity-based emissions (E-1) exist for
every Armington agent, while factor-based (E-2) and process-based (E-3)
emissions exist only for activities.
"""
function _emi_slice_active(s::EnvSets, src::AbstractString, ag::AbstractString)
    if src in s.i
        return ag in s.aa
    elseif src in s.fp || src == "tot"
        return ag in s.a
    end
    return false
end

function _emission_coalitions(data::EnvData)
    # ENVISAGE uses index rq for emission coalitions.  If the aggregation has
    # not provided rq, the standard one-region-per-coalition case is used.
    rq = get(data.par, "rq", data.sets.r)
    return Vector{String}(rq)
end

function _mapr_emission(data::EnvData, q::String, r::String)
    # ENVISAGE uses mapr(rq,r) for the membership of regions in coalitions.
    # Accepted input forms are a Dict keyed by (rq,r) or "rq|r", or a DataFrame
    # with columns rq/r (or coalition/region) and an optional Boolean/value flag.
    mp = get(data.par, "mapr", nothing)
    mp === nothing && return q == r
    if mp isa AbstractDict
        return get(mp, (q, r), get(mp, "$(q)|$(r)", q == r)) == true || get(mp, (q, r), get(mp, "$(q)|$(r)", 0)) == 1
    elseif mp isa DataFrame
        qcol = (:rq in propertynames(mp)) ? :rq : ((:coalition in propertynames(mp)) ? :coalition : nothing)
        rcol = (:r in propertynames(mp)) ? :r : ((:region in propertynames(mp)) ? :region : nothing)
        qcol === nothing && return q == r
        rcol === nothing && return q == r
        flagcol = (:value in propertynames(mp)) ? :value : ((:active in propertynames(mp)) ? :active : nothing)
        for row in eachrow(mp)
            if strip(String(row[qcol])) == q && strip(String(row[rcol])) == r
                flagcol === nothing && return true
                v = row[flagcol]
                return !(ismissing(v) || v == 0 || lowercase(strip(String(v))) in ["false", "no", "0"])
            end
        end
        return false
    else
        return q == r
    end
end

function emissions_block!(m::JuMP.Model, data::EnvData, cal::EnvCalibration)
    PAR = parameters(data, cal)
    # Local parameter aliases generated from ParameterTables.jl.
    chi_Cap = PAR[:chi_Cap]
    chi_Emi = PAR[:chi_Emi]
    rho_Emi = PAR[:rho_Emi]
    rho_Emi_d = PAR[:rho_Emi_d]
    rho_Emi_m = PAR[:rho_Emi_m]
    s = data.sets
    is = _emission_source_set(s)
    aa = _emission_aa_set(s)
    rq = _emission_coalitions(data)

    od = JuMP.object_dictionary(m)

    # Declare only ENVISAGE emissions variable families used in E-1:E-8.
    # ENVISAGE E-1:E-3 populate three disjoint slices of Emi_{r,em,is,aa}
    # (documentation pp. 66-67 and footnote 81): the commodity slice (is = i)
    # spans all Armington agents aa, while the factor slice (is = f) and the
    # process slice (is = "tot") exist only over activities.  Declaring the full
    # rectangular cross product left the (f, fd) and ("tot", fd) cells with no
    # determining equation, so the declaration follows the document's sparsity.
    if !haskey(od, :Emi)
        @variable(m, Emi[r=s.r, em=s.em, src=is, ag=aa; _emi_slice_active(s, src, ag)] >= 0)
    end
    if !haskey(od, :EmiTot)
        @variable(m, EmiTot[s.r, s.em] >= 0)
    end
    if !haskey(od, :EmiOth)
        @variable(m, EmiOth[s.r, s.em] >= 0)
    end
    if !haskey(od, :EmiGbl)
        @variable(m, EmiGbl[s.em] >= 0)
    end
    if !haskey(od, :EmiOthGbl)
        @variable(m, EmiOthGbl[s.em] >= 0)
    end
    if !haskey(od, :τEmi)
        @variable(m, τEmi[s.r, s.em])
    end
    if !haskey(od, :τEmiQ)
        @variable(m, τEmiQ[rq, s.em])
    end
    if !haskey(od, :EmiCap)
        @variable(m, EmiCap[rq, s.em] >= 0)
    end
    if !haskey(od, :EmiQ)
        @variable(m, EmiQ[s.r, s.em] >= 0)
    end
    if !haskey(od, :EmiQY)
        @variable(m, EmiQY[s.r, s.em])
    end

    XA = m[:XA]
    XF = m[:XF]
    XP = m[:XP]
    Emi = m[:Emi]
    EmiTot = m[:EmiTot]
    EmiOth = m[:EmiOth]
    EmiGbl = m[:EmiGbl]
    EmiOthGbl = m[:EmiOthGbl]
    τEmi = m[:τEmi]
    τEmiQ = m[:τEmiQ]
    EmiCap = m[:EmiCap]
    EmiQ = m[:EmiQ]
    EmiQY = m[:EmiQY]

    # Document parameters.  These are calibrated/exogenous values, not JuMP
    # functions.  They are kept scalar in this compact implementation and can be
    # replaced by indexed calibration dictionaries later without changing the
    # equation names.
    χEmi   = chi_Emi
    χCap   = chi_Cap
    ρEmi   = rho_Emi
    ρEmid  = rho_Emi_d
    ρEmim  = rho_Emi_m
    ArmFlag = Int(get(data.par, "ArmFlag", 0))

    # (E-1) Consumption-based emissions.
    if ArmFlag == 0
        @NLconstraint(m, [r=s.r, em=s.em, i=s.i, aa0=s.aa],
            Emi[r, em, i, aa0] == χEmi * ρEmi * XA[r, i, aa0]
        )
    else
        haskey(JuMP.object_dictionary(m), :XD) || error("E-1 with ArmFlag != 0 requires document variable XD from the trade block.")
        haskey(JuMP.object_dictionary(m), :XM) || error("E-1 with ArmFlag != 0 requires document variable XM from the trade block.")
        XD = m[:XD]
        XM = m[:XM]
        @NLconstraint(m, [r=s.r, em=s.em, i=s.i, aa0=s.aa],
            Emi[r, em, i, aa0] == χEmi * ρEmid * XD[r, i, aa0] + χEmi * ρEmim * XM[r, i, aa0]
        )
    end

    # (E-2) Factor-based emissions.
    @NLconstraint(m, [r=s.r, em=s.em, f=s.fp, a=s.a],
        Emi[r, em, f, a] == χEmi * ρEmi * XF[r, f, a]
    )

    # (E-3) Output/process-based emissions.
    @NLconstraint(m, [r=s.r, em=s.em, a=s.a],
        Emi[r, em, "tot", a] == χEmi * ρEmi * XP[r, a]
    )

    # (E-4) Aggregate regional emissions.
    @NLconstraint(m, [r=s.r, em=s.em],
        EmiTot[r, em] ==
            sum(Emi[r, em, i, aa0] for i in s.i, aa0 in s.aa) +
            sum(Emi[r, em, f, a] for f in s.fp, a in s.a) +
            sum(Emi[r, em, "tot", a] for a in s.a) +
            EmiOth[r, em]
    )

    # (E-5) Global emissions.
    @NLconstraint(m, [em=s.em],
        EmiGbl[em] == sum(EmiTot[r, em] for r in s.r) + EmiOthGbl[em]
    )

    # (E-6) Emissions cap by coalition rq.
    @NLconstraint(m, [q=rq, em=s.em],
        sum(EmiTot[r, em] for r in s.r if _mapr_emission(data, q, r)) == χCap * EmiCap[q, em]
    )

    # (E-7) Region emission tax mapped from coalition emission tax.
    @NLconstraint(m, [q=rq, r=s.r, em=s.em; _mapr_emission(data, q, r)],
        τEmi[r, em] == τEmiQ[q, em]
    )

    # (E-8) Value of emission quota trade.
    @NLconstraint(m, [r=s.r, em=s.em],
        EmiQY[r, em] == τEmi[r, em] * (EmiQ[r, em] - EmiTot[r, em])
    )

    return m
end

function emissions_residuals!(res::Dict{String,Function})
    for k in 1:8
        res["EM-$k"] = x -> error("Residual EM-$k is implemented as ENVISAGE printed E-$k in emissions_block!.")
    end
    return res
end
