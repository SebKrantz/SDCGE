# ENVISAGE v10.01 §3.8 Factor markets.
# Strict document version: this block uses only variable families appearing in
# the ENVISAGE factor-market section and adjacent production/macro equations.

function _first_or(v::Vector{String}, default::String)
    return isempty(v) ? default : first(v)
end

function _old_vintage(s::EnvSets)
    for v in s.v
        if lowercase(v) in ["old", "v_old", "installed"]
            return v
        end
    end
    return _first_or(s.v, "Old")
end

function _first_matching(v::Vector{String}, pred)
    for x in v
        pred(x) && return x
    end
    return nothing
end

function _activities_in_zone(s::EnvSets, z::String)
    zl = lowercase(z)
    if length(s.z) == 1 || zl in ["nsg", "all", "nat", "national"]
        return s.a
    elseif startswith(zl, "rur")
        return union(s.acr, s.alv)
    elseif startswith(zl, "urb")
        ag = Set(union(s.acr, s.alv))
        return [a for a in s.a if !(a in ag)]
    else
        return s.a
    end
end

function _land_activities_for_bundle(s::EnvSets, lb::String, lb1::String)
    # ENVISAGE uses a user mapping from land bundles to activities.  The
    # workbook does not supply one, so bundles are matched to the documented
    # land-using activity groups by label (crop bundles to `acr`, pasture /
    # grazing / livestock bundles to `alv`); an unrecognised label falls back to
    # the whole agricultural land domain in the first bundle.  Previously every
    # bundle other than the first was mapped to no activity at all, which left
    # its price index PLBN and its average price PLB undetermined.
    u = uppercase(lb)
    if occursin("CROP", u) || occursin("CRP", u) || occursin("ARABLE", u)
        return s.acr
    elseif occursin("PAST", u) || occursin("GRAZ", u) || occursin("LVS", u) || occursin("LIVE", u)
        return s.alv
    end
    return lb == lb1 ? union(s.acr, s.alv) : String[]
end

function _wbx(s::EnvSets)
    return [wb for wb in s.wbnd if uppercase(wb) in ["ENV", "GRD"]]
end
function _wb1(s::EnvSets)
    return [wb for wb in s.wbnd if uppercase(wb) in ["AGR", "NAG"]]
end
function _wb2(s::EnvSets)
    return [wb for wb in s.wbnd if uppercase(wb) in ["CRP", "LVS", "IND", "MUN"]]
end
function _wba(s::EnvSets)
    return [wb for wb in s.wbnd if uppercase(wb) in ["CRP"]]
end
function _wbi(s::EnvSets)
    return [wb for wb in s.wbnd if uppercase(wb) in ["LVS", "IND", "MUN"]]
end
function _parent_wb1(wb2::String)
    u = uppercase(wb2)
    return u in ["CRP", "LVS"] ? "AGR" : "NAG"
end
function _activities_for_water_bundle(s::EnvSets, wb::String)
    u = uppercase(wb)
    if u == "CRP"
        return s.acr
    elseif u == "LVS"
        return s.alv
    elseif u in ["IND", "MUN"]
        return s.ax
    else
        return String[]
    end
end

function factors_block!(m::JuMP.Model, data::EnvData, cal::EnvCalibration)
    PAR = parameters(data, cal)
    # Local parameter aliases generated from ParameterTables.jl.
    TH2OMax = PAR[:TH2OMax]
    TLandMax = PAR[:TLandMax]
    alpha_capital_supply = PAR[:alpha_capital_supply]
    alpha_h2ob = PAR[:alpha_h2ob]
    alpha_land_activity = PAR[:alpha_land_activity]
    alpha_land_nlb = PAR[:alpha_land_nlb]
    alpha_land_top = PAR[:alpha_land_top]
    alpha_water_activity = PAR[:alpha_water_activity]
    alpha_water_second = PAR[:alpha_water_second]
    alpha_water_top = PAR[:alpha_water_top]
    chi_h2o = PAR[:chi_h2o]
    chi_nrs = PAR[:chi_nrs]
    chi_nrsp = PAR[:chi_nrsp]
    chi_rw = PAR[:chi_rw]
    chi_t = PAR[:chi_t]
    chi_w_nrs = PAR[:chi_w_nrs]
    controls = PAR[:controls]
    # Domain for kxRat: ENVISAGE F-20/F-21 define the capital-output ratio only
    # for the installed ("Old") vintage (documentation p. 48).
    vold_dom = [_old_vintage(data.sets)]
    # Water-bundle domains: only labels the ENVISAGE hierarchy recognises.
    wbnd_dom = unique(vcat(_wb1(data.sets), _wb2(data.sets), _wbx(data.sets)))
    # Land-using activities (P-14): crops and livestock only.
    aland = [a for a in data.sets.a if a in data.sets.acr || a in data.sets.alv]
    epsilon_h2ob = PAR[:epsilon_h2ob]
    eta_I = PAR[:eta_I]
    eta_h2ob = PAR[:eta_h2ob]
    eta_nrs = PAR[:eta_nrs]
    eta_nrs_hi = PAR[:eta_nrs_hi]
    eta_nrs_lo = PAR[:eta_nrs_lo]
    eta_t = PAR[:eta_t]
    eta_w = PAR[:eta_w]
    gamma_tl = PAR[:gamma_tl]
    gamma_tw = PAR[:gamma_tw]
    kappa_nrs = PAR[:kappa_nrs]
    lambda_h2ob = PAR[:lambda_h2ob]
    lambda_nrs = PAR[:lambda_nrs]
    omega_k = PAR[:omega_k]
    omega_lb = PAR[:omega_lb]
    omega_nlb = PAR[:omega_nlb]
    omega_rwg = PAR[:omega_rwg]
    omega_rwp = PAR[:omega_rwp]
    omega_rwue = PAR[:omega_rwue]
    omega_t = PAR[:omega_t]
    omega_w1 = PAR[:omega_w1]
    omega_w2 = PAR[:omega_w2]
    tau_v = PAR[:tau_v]
    s = data.sets

    @variables(m, begin
        # Labor market variables
        LDz[s.r,s.l,s.z] >= 0
        Wres[s.r,s.l,s.z] >= 0
        We[s.r,s.l,s.z] >= 0
        0 <= UEz[s.r,s.l,s.z] <= 0.999
        LSz[s.r,s.l,s.z] >= 0
        Wa[s.r,s.l,s.z] >= 0
        piUrb[s.r,s.l] >= 0
        Wt[s.r,s.l] >= 0
        piS[s.r,s.l]
        Ls[s.r,s.l] >= 0
        TLs[s.r] >= 0

        # Capital market variables
        Kv[s.r,s.a,s.v] >= 0
        TKs[s.r] >= 0
        TR[s.r] >= 0
        PK[s.r,s.a,s.v] >= 0
        Klo[s.r,s.a] >= 0
        Khi[s.r,s.a] >= 0
        K0[s.r,s.a] >= 0
        0 <= RR[s.r,s.a] <= 1
        # F-20/F-21 define the capital-output ratio only for the installed
        # ("old") vintage, so kxRat is declared over that vintage alone; the new
        # vintage slice previously had no equation.
        kxRat[s.r,s.a,vold_dom] >= 0

        # Land market variables
        TLand[s.r] >= 0
        PTLand[s.r] >= 0
        PTLandN[s.r] >= 0
        XLB[s.r,s.lb] >= 0
        XNLB[s.r] >= 0
        PLB[s.r,s.lb] >= 0
        PNLBN[s.r] >= 0
        PNLB[s.r] >= 0
        PLBN[s.r,s.lb] >= 0
        # Land is demanded only by crops and livestock (P-14/F-33/F-36).
        Lands[s.r,aland] >= 0

        # Natural resource market variables
        etaNRS[s.r,s.a] >= 0
        XNRSs[s.r,s.a] >= 0

        # Water market variables
        TH2O[s.r] >= 0
        PTH2O[s.r] >= 0
        TH2Om[s.r] >= 0
        # The water-bundle families exist only for the bundle labels the
        # ENVISAGE water hierarchy F-42:F-53 recognises (AGR/NAG, CRP/LVS/IND/
        # MUN, ENV/GRD).  With any other `wbnd` aggregation those equations are
        # never generated, so the families are declared over the matched labels
        # only instead of leaving every instance undetermined.  PTH2On (F-43) is
        # likewise pinned to PTH2O when that nest is absent (see F-43 below).
        PTH2On[s.r] >= 0
        H2OBnd[s.r,wbnd_dom] >= 0
        PH2OBnd[s.r,wbnd_dom] >= 0
        PH2OBndN[s.r,wbnd_dom] >= 0
        H2Os[s.r,s.a] >= 0
        H2OBndd[s.r,wbnd_dom] >= 0

        # Macro price used in F-25/F-38/F-40 if not declared elsewhere yet.
        PGDPMP[s.r] >= 0
        # `gy` (growth of real per-capita GDP) is the ENVISAGE M-5 variable; the
        # factor block previously declared a second, undetermined copy `gY`.
        gy[s.r]

        # Factor-market price paid to factor owners, used in F-5/F-8/F-24/F-54.
        PF[s.r,s.fp,s.a] >= 0
    end)

    XF = m[:XF]
    PFp = m[:PFp]
    XP = m[:XP]
    XPv = m[:XPv]
    K = m[:K]
    PKp = m[:PKp]
    PFD = m[:PFD]

    oldv = _old_vintage(s)
    href = _first_or(s.h, _first_or(s.fd, "HHD"))
    lb1 = _first_or(s.lb, "LB1")
    land_rest = [lb for lb in s.lb if lb != lb1]
    wb1s = _wb1(s); wb2s = _wb2(s); wbas = _wba(s); wbis = _wbi(s); wbxs = _wbx(s)

    omega_rw_g = omega_rwg
    omega_rw_ue = omega_rwue
    omega_rw_p = omega_rwp
    omega_k = omega_k
    eta_I = eta_I
    eta_t = eta_t
    eta_w = eta_w
    omega_t = omega_t
    omega_nlb = omega_nlb
    omega_lb = omega_lb
    omega_w1 = omega_w1
    omega_w2 = omega_w2
    eps_h2ob = epsilon_h2ob
    eta_h2ob = eta_h2ob
    kappa_nrs = kappa_nrs
    eta_nrs_lo = eta_nrs_lo
    eta_nrs_hi = eta_nrs_hi
    eta_nrs = eta_nrs
    chi_rw = chi_rw
    chi_t = chi_t
    gamma_tl = gamma_tl
    TLandMax = TLandMax
    chi_h2o = chi_h2o
    gamma_tw = gamma_tw
    TH2OMax = TH2OMax
    alpha_h2ob = alpha_h2ob
    lambda_h2ob = lambda_h2ob
    lambda_nrs = lambda_nrs
    chi_nrs = chi_nrs
    chi_w_nrs = chi_w_nrs
    chi_nrsp = chi_nrsp
    tau_v = tau_v

    # Precompute all CES/CET share coefficients used in F-equations.  Do not call
    # parameter tables are precomputed in ParameterTables.jl and read through PAR before @NLconstraint.
    alpha_capital_supply = alpha_capital_supply
    alpha_land_top = alpha_land_top
    alpha_land_nlb = alpha_land_nlb
    alpha_land_activity = alpha_land_activity
    alpha_water_top = alpha_water_top
    alpha_water_second = alpha_water_second
    alpha_water_activity = alpha_water_activity
    lnd0 = _first_or(s.lnd, "LND")
    wat0 = _first_or(s.wat, "WAT")
    nrs0 = _first_or(s.nrs, "NRS")

    controls = controls
    ifLandCET_raw = get(controls, "ifLandCET", true)
    ifLandCET = ifLandCET_raw isa Bool ? ifLandCET_raw : (ifLandCET_raw isa Number ? ifLandCET_raw != 0 : lowercase(strip(string(ifLandCET_raw))) in ["1", "true", "yes", "y"])
    tass = uppercase(strip(string(get(controls, "TASS", "KELAS"))))
    wass = uppercase(strip(string(get(controls, "WASS", "KELAS"))))

    for r in s.r, l in s.l, z in s.z
        az = _activities_in_zone(s, z)
        # (F-1) Labor demand within the relevant labor-market zone.
        @NLconstraint(m, LDz[r,l,z] == sum(XF[r,l,a] for a in az))
        # (F-2) Reservation wage.
        @NLconstraint(m, Wres[r,l,z] == chi_rw * (1 + gy[r])^omega_rw_g * ((1 - UEz[r,l,z]) / 1.0)^omega_rw_ue * (PFD[r,href] / 1.0)^omega_rw_p)
        # (F-3) Labor-market complementarity wage inequality.
        @NLconstraint(m, We[r,l,z] >= Wres[r,l,z])
        # (F-4) Unemployment definition.
        @NLconstraint(m, (1 - UEz[r,l,z]) * LSz[r,l,z] == LDz[r,l,z])
        for a in az
            # (F-5) Sectoral wage equals zone equilibrium wage adjusted by wage differential.
            @NLconstraint(m, PF[r,l,a] == We[r,l,z])
        end
        # (F-6) Average wage in each zone.
        @NLconstraint(m, Wa[r,l,z] * sum(XF[r,l,a] for a in az) == sum(PF[r,l,a] * XF[r,l,a] for a in az))
    end
    rur = _first_matching(s.z, z -> startswith(lowercase(z), "rur"))
    urb = _first_matching(s.z, z -> startswith(lowercase(z), "urb"))
    if rur !== nothing && urb !== nothing
        for r in s.r, l in s.l
            # (F-7) Urban premium.
            @NLconstraint(m, piUrb[r,l] == ((1 - UEz[r,l,urb]) * Wa[r,l,urb]) / ((1 - UEz[r,l,rur]) * Wa[r,l,rur]))
        end
    end
    for r in s.r, l in s.l
        # (F-8) Average economy-wide wage by skill type.
        @NLconstraint(m, Wt[r,l] * sum(XF[r,l,a] for a in s.a) == sum(PF[r,l,a] * XF[r,l,a] for a in s.a))
        lr = isempty(s.sl) ? s.l : s.sl
        # (F-9) Skill premium.
        @NLconstraint(m, piS[r,l] == (sum(Wt[r,ll] * Ls[r,ll] for ll in lr) / sum(Ls[r,ll] for ll in lr)) / Wt[r,l] - 1)
        # (F-10) Total labor supply by skill.
        @NLconstraint(m, Ls[r,l] == sum(LSz[r,l,z] for z in s.z))
    end
    for r in s.r
        # (F-11) Total labor supply.
        @NLconstraint(m, TLs[r] == sum(Ls[r,l] for l in s.l))
    end

    # ENVISAGE §3.8.2 splits the capital market into two ALTERNATIVE closures
    # (documentation pp. 46-48):
    #   * the comparative-static closure, F-12 (CET allocation of TKs across
    #     activities) + F-13 (aggregate rate of return) + F-14, and
    #   * the vintage-capital closure, F-15:F-24, in which F-18 (not F-13)
    #     "determines the economy-wide rate of return, TR" and PK follows from
    #     F-19.
    # This port previously generated both at once, so K and TR were each
    # determined twice (252 equations for 126 K instances, 6 for 3 TR).
    # `data.par["capClosure"]` selects one:
    #   "vintage" (default) -> F-14:F-24, "static" -> F-12:F-14 + F-22:F-24.
    cap_closure = lowercase(strip(String(get(data.par, "capClosure", "vintage"))))
    cap_closure in ["vintage", "static"] ||
        error("Unknown data.par[\"capClosure\"] = $(cap_closure). Use \"vintage\" or \"static\".")
    vintage_capital = cap_closure == "vintage"

    if !vintage_capital
        for r in s.r
            if isfinite(omega_k)
                for a in s.a, v in s.v
                    # (F-12) Comparative-static capital supply allocation.
                    @NLconstraint(m, K[r,a,v] == alpha_capital_supply[a] * (PK[r,a,v] / TR[r])^omega_k * TKs[r])
                end
            else
                for a in s.a, v in s.v
                    # (F-12) Comparative-static capital supply allocation, perfect mobility case.
                    @NLconstraint(m, PK[r,a,v] == TR[r])
                end
            end
            # (F-13) Aggregate rate of return to capital.
            @NLconstraint(m, TR[r] * TKs[r] == sum(PK[r,a,v] * K[r,a,v] for a in s.a, v in s.v))
        end
    end
    for r in s.r, a in s.a, v in s.v
        # (F-14) Capital supply equals capital demand.  Holds in both closures.
        @NLconstraint(m, Kv[r,a,v] == K[r,a,v])
    end

    for r in s.r, a in s.a
        if vintage_capital
            if isfinite(eta_I)
                # (F-15) Old capital supply complementarity condition
                # (Klo >= K0*RR^etaI, complementary to RR <= 1).
                @NLconstraint(m, Klo[r,a] >= K0[r,a] * RR[r,a]^eta_I)
            else
                # (F-15) Old capital supply, horizontal supply case.
                @NLconstraint(m, RR[r,a] == 1)
            end
            # (F-16) New capital complementarity return-ratio condition
            # (RR <= 1, complementary to Khi >= 0).
            @NLconstraint(m, RR[r,a] <= 1)
            # (F-17) Total capital supply meets total capital demand.
            @NLconstraint(m, Klo[r,a] + Khi[r,a] <= sum(K[r,a,v] for v in s.v))
            for v in s.v
                # (F-19) Sector- and vintage-specific rate of return.
                @NLconstraint(m, PK[r,a,v] == RR[r,a] * TR[r])
            end
            if oldv in s.v
                # (F-20) Old-vintage capital-output ratio.
                @NLconstraint(m, kxRat[r,a,oldv] == K[r,a,oldv] / XPv[r,a,oldv])
                # (F-21) Output with old capital.
                @NLconstraint(m, kxRat[r,a,oldv] * XPv[r,a,oldv] == Klo[r,a])
            end
        end
        # (F-22) Aggregate output across vintages.  In the vintage closure this
        # determines output with New capital (documentation p. 48).
        @NLconstraint(m, XP[r,a] == sum(XPv[r,a,v] for v in s.v))
        for f in s.cap
            # (F-23) Capital factor demand accounting identity.
            @NLconstraint(m, XF[r,f,a] == sum(K[r,a,v] for v in s.v))
            if oldv in s.v
                # (F-24) Capital factor price accounting identity.
                @NLconstraint(m, PF[r,f,a] == PK[r,a,oldv])
            end
        end
    end
    if vintage_capital
        for r in s.r
            # (F-18) Aggregate capital supply; determines the economy-wide rate
            # of return TR in the vintage closure.
            @NLconstraint(m, TKs[r] == sum(K[r,a,v] for a in s.a, v in s.v))
        end
    end

    for r in s.r
        if isempty(s.lnd)
            # (F-25) Aggregate land supply, no land-account case.
            @NLconstraint(m, TLand[r] == 0)
        elseif tass == "KELAS" && isfinite(eta_t)
            # (F-25) Aggregate land supply, iso-elastic case.
            @NLconstraint(m, TLand[r] == chi_t * (PTLand[r] / PGDPMP[r])^eta_t)
        elseif tass == "LOGIST"
            # (F-25) Aggregate land supply, logistic case.
            @NLconstraint(m, TLand[r] == TLandMax / (1 + chi_t * exp(-gamma_tl * (PTLand[r] / PGDPMP[r]))))
        elseif tass == "HYPERB"
            # (F-25) Aggregate land supply, hyperbola case.
            @NLconstraint(m, TLand[r] == TLandMax - chi_t * (PTLand[r] / PGDPMP[r])^(-gamma_tl))
        else
            # (F-25) Aggregate land supply, horizontal case.
            @NLconstraint(m, PTLand[r] == PGDPMP[r])
        end
    end

    if !isempty(s.lb) && !isempty(s.lnd)
        for r in s.r
            if isfinite(omega_t)
                # (F-26) Top land bundle allocation.
                @NLconstraint(m, XLB[r,lb1] == alpha_land_top[lb1] * (PLB[r,lb1] / PTLandN[r])^omega_t * TLand[r])
                if !isempty(land_rest)
                    # (F-27) Intermediate land bundle allocation.
                    @NLconstraint(m, XNLB[r] == alpha_land_top["XNLB"] * (PNLB[r] / PTLandN[r])^omega_t * TLand[r])
                else
                    # (F-27) Intermediate land bundle allocation, empty residual-bundle case.
                    @NLconstraint(m, XNLB[r] == 0)
                end
                if ifLandCET
                    # (F-28) Aggregate land price index, standard CET case.
                    @NLconstraint(m, PTLandN[r] == (alpha_land_top[lb1] * PLB[r,lb1]^(1 + omega_t) + alpha_land_top["XNLB"] * PNLB[r]^(1 + omega_t))^(1/(1 + omega_t)))
                else
                    # (F-28) Aggregate land price index, adjusted CET case.
                    @NLconstraint(m, PTLandN[r] == (alpha_land_top[lb1] * PLB[r,lb1]^omega_t + alpha_land_top["XNLB"] * PNLB[r]^omega_t)^(1/omega_t))
                end
            else
                # (F-26) Top land bundle allocation, perfect-transformation case.
                @NLconstraint(m, PLB[r,lb1] == PTLand[r])
                # (F-27) Intermediate land bundle allocation, perfect-transformation case.
                @NLconstraint(m, PNLB[r] == PTLand[r])
            end
            # (F-29) Average price of aggregate land.
            @NLconstraint(m, PTLand[r] * TLand[r] == PLB[r,lb1] * XLB[r,lb1] + PNLB[r] * XNLB[r])

            if !isempty(land_rest)
                for lb in land_rest
                    if isfinite(omega_nlb)
                        # (F-30) Second-level land bundle allocation.
                        @NLconstraint(m, XLB[r,lb] == alpha_land_nlb[lb] * (PLB[r,lb] / PNLBN[r])^omega_nlb * XNLB[r])
                    else
                        # (F-30) Second-level land bundle allocation, perfect-transformation case.
                        @NLconstraint(m, PLB[r,lb] == PNLB[r])
                    end
                end
                if isfinite(omega_nlb)
                    if ifLandCET
                        # (F-31) Intermediate land bundle price index, standard CET case.
                        @NLconstraint(m, PNLBN[r] == (sum(alpha_land_nlb[lb] * PLB[r,lb]^(1 + omega_nlb) for lb in land_rest))^(1/(1 + omega_nlb)))
                    else
                        # (F-31) Intermediate land bundle price index, adjusted CET case.
                        @NLconstraint(m, PNLBN[r] == (sum(alpha_land_nlb[lb] * PLB[r,lb]^omega_nlb for lb in land_rest))^(1/omega_nlb))
                    end
                end
                # (F-32) Average price of the intermediate land bundle.
                @NLconstraint(m, PNLB[r] * XNLB[r] == sum(PLB[r,lb] * XLB[r,lb] for lb in land_rest))
            end

            for lb in s.lb
                acts = _land_activities_for_bundle(s, lb, lb1)
                for a in acts
                    if isfinite(omega_lb)
                        # (F-33) Land supply to activity mapped to land bundle.
                        @NLconstraint(m, Lands[r,a] == alpha_land_activity[a] * (PF[r,lnd0,a] / PLBN[r,lb])^omega_lb * XLB[r,lb])
                    else
                        # (F-33) Land supply to activity, perfect-transformation case.
                        @NLconstraint(m, PF[r,lnd0,a] == PLB[r,lb])
                    end
                end
                if !isempty(acts) && isfinite(omega_lb)
                    if ifLandCET
                        # (F-34) Land bundle price index, standard CET case.
                        @NLconstraint(m, PLBN[r,lb] == (sum(alpha_land_activity[a] * PF[r,lnd0,a]^(1 + omega_lb) for a in acts))^(1/(1 + omega_lb)))
                    else
                        # (F-34) Land bundle price index, adjusted CET case.
                        @NLconstraint(m, PLBN[r,lb] == (sum(alpha_land_activity[a] * PF[r,lnd0,a]^omega_lb for a in acts))^(1/omega_lb))
                    end
                    # (F-35) Average price of land bundle.
                    @NLconstraint(m, PLB[r,lb] * XLB[r,lb] == sum(PF[r,lnd0,a] * Lands[r,a] for a in acts))
                end
            end
        end
    end
    for r in s.r, a in aland, f in s.lnd
        # (F-36) Land supply equals land demand by activity; this is the
        # land-market clearing condition that prices PF[r,lnd,a].
        @NLconstraint(m, Lands[r,a] == XF[r,f,a])
    end

    for r in s.r, a in s.a
        if !isempty(s.nrs)
            # (F-37) Market-condition natural resource supply elasticity.
            @NLconstraint(m, etaNRS[r,a] == eta_nrs_lo + (eta_nrs_hi - eta_nrs_lo) / (1 + exp(-kappa_nrs * (sum(XF[r,f,a] for f in s.nrs) / 1.0 - 1))))
            if isfinite(eta_nrs)
                # (F-38) Natural resource supply function.
                @NLconstraint(m, XNRSs[r,a] == chi_w_nrs * chi_nrs * lambda_nrs * (PF[r,nrs0,a] / PGDPMP[r])^etaNRS[r,a])
            else
                # (F-38) Natural resource supply, horizontal case.
                @NLconstraint(m, chi_nrsp * PF[r,nrs0,a] == PGDPMP[r])
            end
            # (F-39) Natural resource equilibrium: supply meets activity demand.
            # This is the market-clearing condition that prices the natural
            # resource, i.e. it is paired with PF[r,nrs,a].  The former version
            # only *defined* an auxiliary demand aggregate XNRFs and therefore
            # left PF[r,nrs,a] with no determining equation; XNRFs is dropped.
            @NLconstraint(m, XNRSs[r,a] == sum(XF[r,f,a] for f in s.nrs))
        else
            # (F-38) Natural resource supply, no natural-resource-account case.
            @NLconstraint(m, XNRSs[r,a] == 0)
        end
    end

    for r in s.r
        if isempty(s.wat)
            # (F-40) Aggregate water supply, no water-account case.
            @NLconstraint(m, TH2O[r] == 0)
        elseif wass == "KELAS" && isfinite(eta_w)
            # (F-40) Aggregate water supply, iso-elastic case.
            @NLconstraint(m, TH2O[r] == chi_h2o * (PTH2O[r] / PGDPMP[r])^eta_w)
        elseif wass == "LOGIST"
            # (F-40) Aggregate water supply, logistic case.
            @NLconstraint(m, TH2O[r] == TH2OMax / (1 + chi_h2o * exp(-gamma_tw * (PTH2O[r] / PGDPMP[r]))))
        elseif wass == "HYPERB"
            # (F-40) Aggregate water supply, hyperbola case.
            @NLconstraint(m, TH2O[r] == TH2OMax - chi_h2o * (PTH2O[r] / PGDPMP[r])^(-gamma_tw))
        else
            # (F-40) Aggregate water supply, horizontal case.
            @NLconstraint(m, PTH2O[r] == PGDPMP[r])
        end
        if !isempty(s.wat)
            # (F-41) Total water supply equals marketed plus exogenous demand.
            @NLconstraint(m, TH2O[r] == TH2Om[r] + sum(H2OBnd[r,wb] for wb in wbxs))

            if !isempty(wb1s)
            for wb in wb1s
                if isfinite(omega_w1)
                    # (F-42) First-level marketed water bundle allocation.
                    @NLconstraint(m, H2OBnd[r,wb] == alpha_water_top[wb] * (PH2OBnd[r,wb] / PTH2On[r])^omega_w1 * TH2Om[r])
                else
                    # (F-42) First-level marketed water bundle allocation, perfect-transformation case.
                    @NLconstraint(m, PH2OBnd[r,wb] == PTH2O[r])
                end
            end
            if isfinite(omega_w1)
                # (F-43) Marketed water aggregate price index.
                @NLconstraint(m, PTH2On[r] == (sum(alpha_water_top[wb] * PH2OBnd[r,wb]^omega_w1 for wb in wb1s))^(1/omega_w1))
            end
            # (F-44) Average marketed water supply price.
            @NLconstraint(m, PTH2O[r] * TH2Om[r] == sum(PH2OBnd[r,wb] * H2OBnd[r,wb] for wb in wb1s))
        end

        for wb in wb2s
            p = _parent_wb1(wb)
            if p in wb1s
                if isfinite(omega_w2)
                    # (F-45) Second-level water bundle allocation.
                    @NLconstraint(m, H2OBnd[r,wb] == alpha_water_second[wb] * (PH2OBnd[r,wb] / PH2OBndN[r,p])^omega_w2 * H2OBnd[r,p])
                else
                    # (F-45) Second-level water bundle allocation, perfect-transformation case.
                    @NLconstraint(m, PH2OBnd[r,wb] == PH2OBnd[r,p])
                end
            end
        end
        for wb in wb1s
            kids = [x for x in wb2s if _parent_wb1(x) == wb]
            if !isempty(kids)
                if isfinite(omega_w2)
                    # (F-46) Second-level water bundle price index.
                    @NLconstraint(m, PH2OBndN[r,wb] == (sum(alpha_water_second[k] * PH2OBnd[r,k]^omega_w2 for k in kids))^(1/omega_w2))
                end
                # (F-47) Average price of second-level water bundle.
                @NLconstraint(m, PH2OBnd[r,wb] * H2OBnd[r,wb] == sum(PH2OBnd[r,k] * H2OBnd[r,k] for k in kids))
            end
        end

        for wb in wbas
            acts = _activities_for_water_bundle(s, wb)
            for a in acts
                if isfinite(omega_w2)
                    # (F-48) Water supply to activity mapped to water bundle.
                    @NLconstraint(m, H2Os[r,a] == alpha_water_activity[a] * (PF[r,wat0,a] / PH2OBndN[r,wb])^omega_w2 * H2OBnd[r,wb])
                else
                    # (F-48) Water supply to activity, perfect-transformation case.
                    @NLconstraint(m, PF[r,wat0,a] == PH2OBnd[r,wb])
                end
            end
            if !isempty(acts) && isfinite(omega_w2)
                # (F-49) Activity-level water bundle price index.
                @NLconstraint(m, PH2OBndN[r,wb] == (sum(alpha_water_activity[a] * PF[r,wat0,a]^omega_w2 for a in acts))^(1/omega_w2))
                # (F-50) Average price of activity-level water bundle.
                @NLconstraint(m, PH2OBnd[r,wb] * H2OBnd[r,wb] == sum(PF[r,wat0,a] * H2Os[r,a] for a in acts))
            end
        end
        if isempty(wb1s)
            # (F-43) With no first-level water bundle the adjusted-CES index
            # collapses onto the marketed water price.
            @NLconstraint(m, PTH2On[r] == PTH2O[r])
        end
        if isempty(wbas)
            # (F-48)/(F-50) Degenerate single-bundle water market.  The
            # ENVISAGE water-bundle hierarchy (F-42:F-50) is keyed on the
            # document's bundle labels AGR/NAG/CRP/LVS/IND/MUN/ENV/GRD; when the
            # aggregation's `wbnd` set uses none of them (as in the shipped
            # workbook, which has IRR/NONIRR) none of those equations can be
            # instantiated and H2Os and PTH2O are left undetermined.  In that
            # case marketed water is a single bundle allocated directly to
            # activities by the same CET form, and its average price is the
            # value-share identity F-50 written for that single bundle.
            for a in s.a
                @NLconstraint(m, H2Os[r,a] == alpha_water_activity[a] * (PF[r,wat0,a] / PTH2O[r])^omega_w2 * TH2Om[r])
            end
            @NLconstraint(m, PTH2O[r] * TH2Om[r] == sum(PF[r,wat0,a] * H2Os[r,a] for a in s.a))
        end
        for a in s.a, f in s.wat
            # (F-51) Water supply equals activity water demand; this is the
            # water-market clearing condition that prices PF[r,wat,a].
            @NLconstraint(m, H2Os[r,a] == XF[r,f,a])
        end
            for wb in wbis
                acts = _activities_for_water_bundle(s, wb)
                # (F-52) Aggregate water-bundle demand.
                @NLconstraint(m, H2OBndd[r,wb] == (alpha_h2ob / lambda_h2ob) * (PH2OBnd[r,wb] / PGDPMP[r])^(-eps_h2ob) * (sum(XP[r,a] for a in acts) / 1.0)^eta_h2ob)
                # (F-53) Aggregate water-bundle market clearing.
                @NLconstraint(m, H2OBnd[r,wb] == H2OBndd[r,wb])
            end
        end
    end

    for r in s.r, f in s.fp, a in s.a
        # (F-54) Producer purchase price of factors.
        @NLconstraint(m, PFp[r,f,a] == (1 + tau_v) * PF[r,f,a])
    end
    for r in s.r, a in s.a, v in s.v
        # (F-55) Producer purchase price of vintage capital.
        @NLconstraint(m, PKp[r,a,v] == (1 + tau_v) * PK[r,a,v])
    end
    return m
end

function factors_residuals!(res::Dict{String,Function})
    for k in 1:55
        res["F-$k"] = x -> error("Residual F-$k is implemented as ENVISAGE F-$k in factors_block!.")
    end
    return res
end
