# ENVISAGE v10.01 §3.5 Final demand block, equations D-1:D-37.
# Document-strict implementation: variable families and equation labels follow the
# ENVISAGE documentation. Conditional equations are implemented with explicit
# Julia branches for the selected demand system and optional waste module.

_envisage_flag(data::EnvData, key::String, default) = get(data.par, key, default)

function _hasvar(m::JuMP.Model, nm::Symbol)
    return haskey(JuMP.object_dictionary(m), nm)
end

function demand_block!(m::JuMP.Model, data::EnvData, cal::EnvCalibration)
    PAR = parameters(data, cal)
    # Local parameter aliases generated from ParameterTables.jl.
    P_sav = PAR[:P_sav]
    alpha_ac = PAR[:alpha_ac]
    alpha_aw = PAR[:alpha_aw]
    alpha_c = PAR[:alpha_c]
    alpha_cnnrg = PAR[:alpha_cnnrg]
    alpha_cnrg = PAR[:alpha_cnrg]
    alpha_fd = PAR[:alpha_fd]
    alpha_i = PAR[:alpha_i]
    aps = PAR[:aps]
    beta_c = PAR[:beta_c]
    chi_s = PAR[:chi_s]
    gamma_c = PAR[:gamma_c]
    lambda_ac = PAR[:lambda_ac]
    lambda_aw = PAR[:lambda_aw]
    mu_s = PAR[:mu_s]
    nu_c = PAR[:nu_c]
    nu_carrier = PAR[:nu_carrier]
    nu_e = PAR[:nu_e]
    nu_nely = PAR[:nu_nely]
    nu_nnrg = PAR[:nu_nnrg]
    nu_olg = PAR[:nu_olg]
    sigma_ac = PAR[:sigma_ac]
    sigma_fd = PAR[:sigma_fd]
    tau_w = PAR[:tau_w]
    s = data.sets
    nk = max(length(s.k), 1)
    ni = max(length(s.i), 1)
    nt = max(length(s.t), 1)

    # ENVISAGE demand-system switches.  Valid values: "LES", "ELES", "AIDADS", "CDE".
    demand_system = uppercase(String(_envisage_flag(data, "demand_system", "LES")))
    waste_flag = Bool(_envisage_flag(data, "waste_module", true))

    # `YC` (nominal consumption) was declared but appears in no ENVISAGE
    # equation of this port, and `ZC` is the CDE auxiliary variable used only by
    # D-5:D-7.  Declaring them unconditionally left 3 + 60 permanently
    # undetermined instances; ZC is now declared only in the CDE branch and YC
    # is dropped.
    @variables(m, begin
        Ysup[s.r,s.h]
        XC[s.r,s.k,s.h] >= 0
        PC[s.r,s.k,s.h] >= 0
        μc[s.r,s.k,s.h] >= 0
        u[s.r,s.h]
        shr[s.r,s.k,s.h] >= 0
        XCnnrg[s.r,s.k,s.h] >= 0
        XCnrg[s.r,s.k,s.h] >= 0
        PCnnrg[s.r,s.k,s.h] >= 0
        PCnrg[s.r,s.k,s.h] >= 0
        XAh[s.r,s.i,s.h] >= 0
        PAh[s.r,s.i,s.h] >= 0
        XCely[s.r,s.k,s.h] >= 0
        XCnely[s.r,s.k,s.h] >= 0
        PCely[s.r,s.k,s.h] >= 0
        PCnely[s.r,s.k,s.h] >= 0
        XCcoa[s.r,s.k,s.h] >= 0
        XColg[s.r,s.k,s.h] >= 0
        PCcoa[s.r,s.k,s.h] >= 0
        PColg[s.r,s.k,s.h] >= 0
        XCoil[s.r,s.k,s.h] >= 0
        XCgas[s.r,s.k,s.h] >= 0
        PCoil[s.r,s.k,s.h] >= 0
        PCgas[s.r,s.k,s.h] >= 0
        XAc[s.r,s.i,s.h] >= 0
        PACC[s.r,s.i,s.h] >= 0
        PAc[s.r,s.i,s.h] >= 0
        PAw[s.r,s.i,s.h] >= 0
        XFD[s.r,s.fd] >= 0
        PFD[s.r,s.fd] >= 0
        # D-35 only builds the Fisher-index indicator for household agents, so
        # QFD is declared over s.h rather than the full final-demand set (the
        # government/investment slices had no equation).
        QFD[s.r,s.h,s.t,s.t] >= 0
    end)

    # Use the document's common final-demand/Armington variables declared elsewhere.
    YD = m[:YD]
    Sh = m[:Sh]
    YFD = m[:YFD]
    XA = m[:XA]
    PA = m[:PA]
    XAw = m[:XAw]
    Pop = _hasvar(m, :Pop) ? m[:Pop] : nothing

    nonnrg = setdiff(s.i, s.nrg)
    ely = isempty(s.ely) ? String[] : s.ely
    nely = setdiff(s.nrg, ely)

    γc = gamma_c
    βc = beta_c
    μs = mu_s
    Psav = P_sav
    χs = chi_s
    aps = aps
    τw = tau_w
    νc = nu_c
    νnnrg = nu_nnrg
    νe = nu_e
    νnely = nu_nely
    νolg = nu_olg
    νcar = nu_carrier
    σac = sigma_ac
    σfd = sigma_fd

    αc = alpha_c
    αcnnrg = alpha_cnnrg
    αcnrg = alpha_cnrg
    αi = alpha_i
    αfd = alpha_fd
    αac = alpha_ac
    αaw = alpha_aw
    λac = lambda_ac
    λaw = lambda_aw

    # D-1 through D-8: household demand system.  Only the equations belonging to
    # the selected document demand system are generated.
    if demand_system == "ELES"
        @NLconstraints(m, begin
            # (D-1) Supernumerary income, ELES case.
            [r=s.r,h=s.h], Ysup[r,h] == YD[r] - sum(PC[r,k,h] * γc for k in s.k)
            # (D-2) LES/ELES consumption demand.
            [r=s.r,k=s.k,h=s.h], XC[r,k,h] == γc + βc * μc[r,k,h] * Ysup[r,h] / PC[r,k,h]
            # (D-3) ELES utility.
            [r=s.r,h=s.h], u[r,h] == (Ysup[r,h] / Psav)^μs * prod((PC[r,k,h] / (μc[r,k,h] + 1e-9))^(-βc * μc[r,k,h]) for k in s.k)
        end)
    elseif demand_system == "AIDADS"
        @NLconstraints(m, begin
            # (D-1) Supernumerary income, LES/AIDADS case.
            [r=s.r,h=s.h], Ysup[r,h] == YD[r] - Sh[r] - sum(PC[r,k,h] * γc for k in s.k)
            # (D-4) AIDADS marginal budget share.
            [r=s.r,k=s.k,h=s.h], μc[r,k,h] == αc[k]
            # (D-2) AIDADS consumption demand.
            [r=s.r,k=s.k,h=s.h], XC[r,k,h] == γc + βc * μc[r,k,h] * Ysup[r,h] / PC[r,k,h]
            # (D-3) AIDADS utility expression.
            [r=s.r,h=s.h], u[r,h] == -1 - log(1 + sum(μc[r,k,h] * log((XC[r,k,h] - γc + 1e-9)) for k in s.k))
            # (D-8) Consumption from budget shares.
            [r=s.r,k=s.k,h=s.h], shr[r,k,h] == PC[r,k,h] * XC[r,k,h] / (YD[r] - Sh[r] + 1e-9)
        end)
    elseif demand_system == "CDE"
        # ZC is the CDE auxiliary variable (D-5:D-7); it exists only here.
        @variable(m, ZC[s.r,s.k,s.h] >= 0)
        @NLconstraints(m, begin
            # (D-5) CDE auxiliary variable.
            [r=s.r,k=s.k,h=s.h], ZC[r,k,h] == αc[k] * (u[r,h] + 1e-9) * (PC[r,k,h] / ((YD[r] - Sh[r]) + 1e-9))
            # (D-6) CDE budget shares.
            [r=s.r,k=s.k,h=s.h], shr[r,k,h] == ZC[r,k,h] / (sum(ZC[r,j,h] for j in s.k) + 1e-9)
            # (D-7) CDE utility normalization.
            [r=s.r,h=s.h], sum(ZC[r,k,h] for k in s.k) == 1
            # (D-8) CDE consumption from budget shares.
            [r=s.r,k=s.k,h=s.h], shr[r,k,h] == PC[r,k,h] * XC[r,k,h] / (YD[r] - Sh[r] + 1e-9)
        end)
    else
        @NLconstraints(m, begin
            # (D-1) Supernumerary income, LES/AIDADS case.
            [r=s.r,h=s.h], Ysup[r,h] == YD[r] - Sh[r] - sum(PC[r,k,h] * γc for k in s.k)
            # (D-2) LES consumption demand.
            [r=s.r,k=s.k,h=s.h], XC[r,k,h] == γc + βc * μc[r,k,h] * Ysup[r,h] / PC[r,k,h]
            # (D-3) LES utility expression.
            [r=s.r,h=s.h], u[r,h] == -1 - log(1 + sum(μc[r,k,h] * log((XC[r,k,h] - γc + 1e-9)) for k in s.k))
            # (D-8) LES budget shares.
            [r=s.r,k=s.k,h=s.h], shr[r,k,h] == PC[r,k,h] * XC[r,k,h] / (YD[r] - Sh[r] + 1e-9)
        end)
    end

    # D-9:D-24: conversion of consumer goods to producer goods.
    @NLconstraints(m, begin
        # (D-9) Non-energy bundle demand.
        [r=s.r,k=s.k,h=s.h], XCnnrg[r,k,h] == αcnnrg[k] * (PC[r,k,h] / PCnnrg[r,k,h])^νc * XC[r,k,h]
        # (D-10) Energy bundle demand.
        [r=s.r,k=s.k,h=s.h], XCnrg[r,k,h] == αcnrg[k] * (PC[r,k,h] / PCnrg[r,k,h])^νc * XC[r,k,h]
        # (D-11) Consumer commodity price.
        [r=s.r,k=s.k,h=s.h], PC[r,k,h] == (αcnnrg[k]*PCnnrg[r,k,h]^(1-νc) + αcnrg[k]*PCnrg[r,k,h]^(1-νc))^(1/(1-νc))
        # (D-12) Non-energy Armington demand by households.
        [r=s.r,i=nonnrg,h=s.h], XAh[r,i,h] == sum(αi[i] * (PCnnrg[r,k,h] / PAh[r,i,h])^νnnrg * XCnnrg[r,k,h] for k in s.k)
        # (D-13) Non-energy consumer bundle price.
        [r=s.r,k=s.k,h=s.h], PCnnrg[r,k,h] == (sum(αi[i] * PAh[r,i,h]^(1-νnnrg) for i in nonnrg))^(1/(1-νnnrg))
        # (D-14) Electricity bundle demand.
        [r=s.r,k=s.k,h=s.h], XCely[r,k,h] == αc[k] * (PCnrg[r,k,h] / PCely[r,k,h])^νe * XCnrg[r,k,h]
        # (D-15) Non-electric energy bundle demand.
        [r=s.r,k=s.k,h=s.h], XCnely[r,k,h] == αc[k] * (PCnrg[r,k,h] / PCnely[r,k,h])^νe * XCnrg[r,k,h]
        # (D-16) Energy bundle price.
        [r=s.r,k=s.k,h=s.h], PCnrg[r,k,h] == (αc[k]*PCely[r,k,h]^(1-νe) + αc[k]*PCnely[r,k,h]^(1-νe))^(1/(1-νe))
        # (D-17) Coal bundle demand.
        [r=s.r,k=s.k,h=s.h], XCcoa[r,k,h] == αc[k] * (PCnely[r,k,h] / PCcoa[r,k,h])^νnely * XCnely[r,k,h]
        # (D-18) Oil-and-gas bundle demand.
        [r=s.r,k=s.k,h=s.h], XColg[r,k,h] == αc[k] * (PCnely[r,k,h] / PColg[r,k,h])^νnely * XCnely[r,k,h]
        # (D-19) Non-electric energy price.
        [r=s.r,k=s.k,h=s.h], PCnely[r,k,h] == (αc[k]*PCcoa[r,k,h]^(1-νnely) + αc[k]*PColg[r,k,h]^(1-νnely))^(1/(1-νnely))
        # (D-20) Oil bundle demand.
        [r=s.r,k=s.k,h=s.h], XCoil[r,k,h] == αc[k] * (PColg[r,k,h] / PCoil[r,k,h])^νolg * XColg[r,k,h]
        # (D-21) Gas bundle demand.
        [r=s.r,k=s.k,h=s.h], XCgas[r,k,h] == αc[k] * (PColg[r,k,h] / PCgas[r,k,h])^νolg * XColg[r,k,h]
        # (D-22) Oil-and-gas price.
        [r=s.r,k=s.k,h=s.h], PColg[r,k,h] == (αc[k]*PCoil[r,k,h]^(1-νolg) + αc[k]*PCgas[r,k,h]^(1-νolg))^(1/(1-νolg))
        # (D-23) Energy Armington demand by households.
        [r=s.r,i=s.nrg,h=s.h], XAh[r,i,h] == sum(αi[i] * XCnrg[r,k,h] for k in s.k)
        # XAh is this port's name for the household Armington demand that
        # ENVISAGE writes directly as XA(r,i,h); D-27:D-32 use the latter, so
        # the two are tied together here rather than leaving XA[r,i,h] with no
        # determining equation.
        [r=s.r,i=s.i,h=s.h], XA[r,i,h] == XAh[r,i,h]
    end)

    # (D-24) Consumer prices of the household energy carriers.  The household
    # energy nest D-14:D-22 splits XCnrg into an electricity bundle and a
    # non-electric bundle (coal, then oil and gas); each carrier faces the
    # household Armington purchaser price PAh of the corresponding commodity.
    # The previous version of D-24 instead repeated `PAh == PA` for the energy
    # commodities, duplicating D-32 and leaving PCely/PCcoa/PCoil/PCgas — 240
    # instances — with no equation at all.
    ccarrier_p = Dict("ELY"=>PCely, "COA"=>PCcoa, "OIL"=>PCoil, "GAS"=>PCgas)
    for key in ["ELY", "COA", "OIL", "GAS"]
        Pk = ccarrier_p[key]
        match_i = findfirst(i -> _nrg_carrier_key(i) == key, s.i)
        if match_i === nothing
            # No commodity for this carrier in the aggregation: the node is
            # inactive and its price is held at the benchmark value 1.
            for r in s.r, k in s.k, h in s.h
                @NLconstraint(m, Pk[r,k,h] == 1.0)
            end
        else
            ii = s.i[match_i]
            for r in s.r, k in s.k, h in s.h
                @NLconstraint(m, Pk[r,k,h] == PAh[r,ii,h])
            end
        end
    end

    if demand_system == "ELES"
        @NLconstraints(m, begin
            # (D-26) ELES household saving.
            [r=s.r,h=s.h], Sh[r] == YD[r] - sum(PC[r,k,h] * XC[r,k,h] for k in s.k)
        end)
    else
        @NLconstraints(m, begin
            # (D-25) Household saving outside ELES.
            [r=s.r,h=s.h], Sh[r] == χs * aps * YD[r]
        end)
    end

    if waste_flag
        @NLconstraints(m, begin
            # (D-27) Actual consumption from Armington household demand.
            [r=s.r,i=s.i,h=s.h], XAc[r,i,h] == αac[i] * XA[r,i,h] * (PACC[r,i,h] / (λac * PAc[r,i,h]))^σac
            # (D-28) Waste from Armington household demand.
            [r=s.r,i=s.i,h=s.h], XAw[r,i,h] == αaw[i] * XA[r,i,h] * (PACC[r,i,h] / (λaw * PAw[r,i,h]))^σac
            # (D-29) ACES composite price for actual consumption/waste.
            [r=s.r,i=s.i,h=s.h], PACC[r,i,h] == (αac[i]*(λac*PAc[r,i,h])^(-σac) + αaw[i]*(λaw*PAw[r,i,h])^(-σac))^(-1/σac)
            # (D-30) Price of actual consumption.
            [r=s.r,i=s.i,h=s.h], PAc[r,i,h] == PA[r,i,h]
            # (D-31) Price of waste.
            [r=s.r,i=s.i,h=s.h], PAw[r,i,h] == PA[r,i,h] * (1 + τw)
            # (D-32) Waste-inclusive purchaser price.
            [r=s.r,i=s.i,h=s.h], PAh[r,i,h] * XA[r,i,h] == PAc[r,i,h]*XAc[r,i,h] + PAw[r,i,h]*XAw[r,i,h]
        end)
    else
        @NLconstraints(m, begin
            # (D-30) Price of actual consumption when waste module is inactive.
            [r=s.r,i=s.i,h=s.h], PAc[r,i,h] == PA[r,i,h]
            # (D-32) Consumer price identity without waste.
            [r=s.r,i=s.i,h=s.h], PAh[r,i,h] == PA[r,i,h]
        end)
    end

    @NLconstraints(m, begin
        # (D-33) Other final demand for Armington goods.
        [r=s.r,i=s.i,fdc=s.fdc], XA[r,i,fdc] == αfd[i] * (PFD[r,fdc] / PA[r,i,fdc])^σfd * XFD[r,fdc]
        # (D-34) Other final demand price index.
        [r=s.r,fdc=s.fdc], PFD[r,fdc] == (sum(αfd[i] * PA[r,i,fdc]^(1-σfd) for i in s.i))^(1/(1-σfd))
    end)

    # (D-35) Household CPI as a Fisher price index.
    # The document defines the indicator
    #     QFD[r,h,tp,tq] = sum_i PAh[r,i,h,tp] * XA[r,i,h,tq]
    # and then
    #     PFD[r,h,t] = PFD[r,h,t-1] * sqrt(
    #         QFD[r,h,t,t-1] / QFD[r,h,t-1,t-1] *
    #         QFD[r,h,t,t]   / QFD[r,h,t-1,t]) .
    # In this comparative-static package only current-period JuMP variables are
    # endogenous.  Lagged prices/quantities are benchmark data.  The loops below
    # implement the document equation without inventing extra variables.
    tcur = isempty(s.t) ? "t" : s.t[end]
    tprev = length(s.t) >= 2 ? s.t[end-1] : tcur
    pfd0 = _envisage_flag(data, "PFD0", 1.0)
    pah0 = _envisage_flag(data, "PAh0", 1.0)
    xa0  = _envisage_flag(data, "XA0", 1.0)

    for r in s.r, h in s.h, tp in s.t, tq in s.t
        price_current = (tp == tcur)
        quantity_current = (tq == tcur)
        if price_current && quantity_current
            @NLconstraint(m, QFD[r,h,tp,tq] == sum(PAh[r,i,h] * XA[r,i,h] for i in s.i))
        elseif price_current && !quantity_current
            @NLconstraint(m, QFD[r,h,tp,tq] == sum(PAh[r,i,h] * xa0 for i in s.i))
        elseif !price_current && quantity_current
            @NLconstraint(m, QFD[r,h,tp,tq] == sum(pah0 * XA[r,i,h] for i in s.i))
        else
            @NLconstraint(m, QFD[r,h,tp,tq] == sum(pah0 * xa0 for i in s.i))
        end
    end

    for r in s.r, h in s.h
        @NLconstraint(m,
            PFD[r,h] == pfd0 * sqrt(
                (QFD[r,h,tcur,tprev] / QFD[r,h,tprev,tprev]) *
                (QFD[r,h,tcur,tcur]  / QFD[r,h,tprev,tcur])
            )
        )
    end

    # (D-36) Household nominal final-demand expenditure.  This is NOT a
    # duplicate of D-37: D-37 is the price/quantity identity YFD = PFD*XFD (it
    # determines XFD), while D-36 values the household Armington basket and is
    # what determines YFD[r,h].  An earlier version dropped D-36 as a duplicate,
    # which left XFD[r,h] and XFD[r,gov] with no determining equation.
    @NLconstraints(m, begin
        [r=s.r,h=s.h], YFD[r,h] == sum(PAh[r,i,h] * XA[r,i,h] for i in s.i)
        # (D-37) Nominal/real final demand identity (covers households as well
        # as government and investment, since s.h ⊆ s.fd).
        [r=s.r,fd=s.fd], YFD[r,fd] == PFD[r,fd] * XFD[r,fd]
    end)
    return m
end

function demand_residuals!(res::Dict{String,Function})
    for k in 1:37
        res["D-$k"] = x -> error("Residual D-$k is implemented as ENVISAGE D-$k in demand_block!.")
    end
    return res
end
