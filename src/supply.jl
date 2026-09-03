# ENVISAGE v10.01 §3.3: Commodity supply equations S-1:S-14.
# This file deliberately uses the document's variable names only for the supply block:
#   X, P, PP, XP, PX, XS, PS, XPOW, PPOW, XPB, PPOWN, PPB, PPBN.
# There is no separate MAKE variable: the make matrix is represented by X[r,a,i],
# exactly as in equations S-1 through S-5.

function supply_block!(m::JuMP.Model, data::EnvData, cal::EnvCalibration)
    PAR = parameters(data, cal)
    # Local parameter aliases generated from ParameterTables.jl.
    alpha_elya_val = PAR[:alpha_elya_val]
    alpha_etd_val = PAR[:alpha_etd_val]
    alpha_pb_val = PAR[:alpha_pb_val]
    alpha_pow_val = PAR[:alpha_pow_val]
    alpha_s_val = PAR[:alpha_s_val]
    gamma_p_val = PAR[:gamma_p_val]
    lambda_pb_val = PAR[:lambda_pb_val]
    lambda_pow_val = PAR[:lambda_pow_val]
    lambda_s_val = PAR[:lambda_s_val]
    omega_s = PAR[:omega_s]
    sigma_el = PAR[:sigma_el]
    sigma_pb = PAR[:sigma_pb]
    sigma_pow = PAR[:sigma_pow]
    sigma_s = PAR[:sigma_s]
    tau_p = PAR[:tau_p]
    s = data.sets

    # Document-consistent index subsets used for conditional equations.
    # `ely` and `etd` are read from the Excel sets sheet into EnvSets.
    # `ely` is the electric commodity subset of i. `etd` is the optional
    # transmission/distribution activity subset of a. If the workbook has no
    # T&D activity, `s.etd` is empty and the S-6 T&D component is omitted.
    ely = [i for i in s.ely if i in s.i]
    etd = [a for a in s.etd if a in s.a]
    nonely = [i for i in s.i if !(i in ely)]

    # Power bundle mappings for S-12:S-14. If the workbook does not provide them,
    # use all elya in all pb as a permissive default, still without changing names.
    pbmap_raw = get(data.par, "pbmap", Dict{String,Vector{String}}())
    pbmap = Dict{String,Vector{String}}()
    for pb in s.pb
        vals = haskey(pbmap_raw, pb) ? pbmap_raw[pb] : s.elya
        pbmap[pb] = [a for a in vals if a in s.elya]
    end

    @variables(m, begin
        # Non-electric make/supply variables from S-1:S-5.
        X[s.r,s.a,s.i] >= 0          # X_{r,a,i}: supply of commodity i by activity a
        P[s.r,s.a,s.i] >= 0          # P_{r,a,i}: basic supply price
        PP[s.r,s.a,s.i] >= 0         # PP_{r,a,i}: tax-inclusive supply price
        XS[s.r,s.i] >= 0             # XS_{r,i}: aggregate supplied commodity
        PS[s.r,s.i] >= 0             # PS_{r,i}: aggregate supplied price

        # Electricity variables from S-6:S-14.  Declared over s.ely (the
        # electricity-commodity subset of s.i), matching the domain already
        # documented for these families in mcp.jl (`_mcp_domain_for_variable`:
        # "r × ely" / "r × pb × ely").  S-7:S-14 are only ever generated for
        # `e in ely`, so declaring these over the full s.i commodity domain
        # left the non-electricity slices permanently undetermined.
        XPOW[s.r,ely] >= 0           # XPOW_{r,ely}: aggregate power bundle demand
        PPOW[s.r,ely] >= 0           # PPOW_{r,ely}: average power-bundle price
        XPB[s.r,s.pb,ely] >= 0       # XPB_{r,pb,ely}: power bundle demand
        PPOWN[s.r,ely] >= 0          # PPOWN_{r,ely}: adjusted-CES power price index
        PPB[s.r,s.pb,ely] >= 0       # PPB_{r,pb,ely}: average price of power bundle pb
        PPBN[s.r,s.pb,ely] >= 0      # PPBN_{r,pb,ely}: adjusted-CES price index for pb
    end)

    XP = m[:XP]
    PX = m[:PX]

    # Coefficients. These names mirror the ENVISAGE notation in comments:
    # gamma_p = γ^p, lambda_s = λ^s, alpha_s = α^s, alpha_pow = α^pow,
    # alpha_pb = α^pb, lambda_pow = λ^pow, lambda_pb = λ^pb.
    # Pre-compute all scalar coefficients before entering JuMP nonlinear macros.
    # JuMP treats calls such as lambda_s(i) inside @NLconstraint as nonlinear
    # function calls unless they are expanded to numeric constants.  The
    # ENVISAGE notation remains λ^s, λ^pow, λ^pb; these are calibration
    # parameters, not Julia functions.
    gamma_p_val  = gamma_p_val
    lambda_s_val = lambda_s_val
    alpha_s_val  = alpha_s_val
    alpha_etd_val = alpha_etd_val
    alpha_pow_val = alpha_pow_val
    alpha_pb_val  = alpha_pb_val
    lambda_pow_val = lambda_pow_val
    alpha_elya_val = alpha_elya_val
    lambda_pb_val  = lambda_pb_val

    omega_s = omega_s      # ω^s transformation elasticity
    sigma_s = sigma_s      # σ^s aggregation elasticity
    sigma_el = sigma_el    # σ^el electricity top nest
    sigma_pow = sigma_pow  # σ^pow power bundle nest
    sigma_pb = sigma_pb    # σ^pb generation nest
    tau_p = tau_p            # τ^p output tax

    # S-1: activity output allocation across commodities, with the perfect-transform case.
    for r in s.r, a in s.a, i in nonely
        if isfinite(omega_s)
            @NLconstraint(m, X[r,a,i] == gamma_p_val[(a,i)] * (1 / lambda_s_val[i])^(1 + omega_s) * (P[r,a,i] / PX[r,a])^omega_s * XP[r,a])
        else
            @NLconstraint(m, P[r,a,i] == lambda_s_val[i] * PX[r,a])
        end
    end

    # S-2: activity revenue identity.
    @NLconstraint(m, [r=s.r,a=s.a], PX[r,a] * XP[r,a] == sum(P[r,a,i] * X[r,a,i] for i in nonely))

    # S-3: output tax wedge.
    @NLconstraint(m, [r=s.r,a=s.a,i=nonely], PP[r,a,i] == (1 + tau_p) * P[r,a,i])

    # S-4: commodity aggregation across activities, with law-of-one-price case.
    for r in s.r, a in s.a, i in nonely
        if isfinite(sigma_s)
            @NLconstraint(m, X[r,a,i] == alpha_s_val[(a,i)] * (PS[r,i] / PP[r,a,i])^sigma_s * XS[r,i])
        else
            @NLconstraint(m, PP[r,a,i] == PS[r,i])
        end
    end

    # S-5: supplied commodity zero-profit/price identity.
    @NLconstraint(m, [r=s.r,i=nonely], PS[r,i] * XS[r,i] == sum(PP[r,a,i] * X[r,a,i] for a in s.a))

    # S-6:S-14 are generated for electric commodities `ely`; S-6 is skipped when `etd` is empty.
    for r in s.r, e in ely
        for a in etd
            # S-6: demand for transmission/distribution service activities.
            @NLconstraint(m, X[r,a,e] == alpha_etd_val[(a,e)] * (PS[r,e] / PP[r,a,e])^sigma_el * XS[r,e])
        end
        # S-7: demand for aggregate power bundle.
        @NLconstraint(m, XPOW[r,e] == alpha_pow_val[e] * (PS[r,e] / PPOW[r,e])^sigma_el * XS[r,e])
        # S-8: aggregate electricity supply price.
        @NLconstraint(m, PS[r,e] == (sum(alpha_etd_val[(a,e)] * PP[r,a,e]^(1 - sigma_el) for a in etd) + alpha_pow_val[e] * PPOW[r,e]^(1 - sigma_el))^(1 / (1 - sigma_el)))
        # S-9: demand for power bundles.
        for pb in s.pb
            @NLconstraint(m, XPB[r,pb,e] == alpha_pb_val[(e,pb)] * lambda_pow_val[pb]^(-sigma_pow) * (PPOWN[r,e] / PPB[r,pb,e])^sigma_pow * XPOW[r,e])
        end
        # S-10: adjusted-CES price index for aggregate power.
        @NLconstraint(m, PPOWN[r,e] == (sum(alpha_pb_val[(e,pb)] * (lambda_pow_val[pb] * PPB[r,pb,e])^(-sigma_pow) for pb in s.pb))^(-1 / sigma_pow))
        # S-11: average power price identity.
        @NLconstraint(m, PPOW[r,e] * XPOW[r,e] == sum(PPB[r,pb,e] * XPB[r,pb,e] for pb in s.pb))
        for pb in s.pb
            if get(alpha_pb_val, (e,pb), 0.0) > 0.0
                active_elya = [a for a in pbmap[pb] if haskey(alpha_elya_val, (pb,e,a))]
                for a in active_elya
                    # S-12: demand for power generated by activity elya mapped to pb.
                    @NLconstraint(m, X[r,a,e] == alpha_elya_val[(pb,e,a)] * (PPBN[r,pb,e] / (lambda_pb_val[a] * PP[r,a,e]))^sigma_pb * XPB[r,pb,e])
                end
                # S-13: adjusted-CES power-bundle price index.
                @NLconstraint(m, PPBN[r,pb,e] == (sum(alpha_elya_val[(pb,e,a)] * (lambda_pb_val[a] * PP[r,a,e])^(-sigma_pb) for a in active_elya))^(-1 / sigma_pb))
                # S-14: average power-bundle price identity.
                @NLconstraint(m, PPB[r,pb,e] * XPB[r,pb,e] == sum(PP[r,a,e] * X[r,a,e] for a in active_elya))
            end
        end
    end

    return m
end

function supply_residuals!(res::Dict{String,Function})
    for k in 1:14
        res["S-$k"] = x -> error("Residual S-$k is implemented as a JuMP equation in supply_block!.")
    end
    return res
end
