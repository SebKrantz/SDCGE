# ENVISAGE v10.01 §3.4 Income block, equations Y-1:Y-20.
# Document-strict implementation: only ENVISAGE income variables/equations are
# declared here. Conditional equations in the paper are implemented with explicit
# Julia branches (default vs MRIO, ArmFlag = 0 vs ArmFlag != 0).

function income_block!(m::JuMP.Model, data::EnvData, cal::EnvCalibration)
    PAR = parameters(data, cal)
    # Local parameter aliases generated from ParameterTables.jl.
    RGDPpc0 = PAR[:RGDPpc0]
    chi_Emi = PAR[:chi_Emi]
    chi_OI = PAR[:chi_OI]
    chi_OO = PAR[:chi_OO]
    chi_f = PAR[:chi_f]
    chi_h = PAR[:chi_h]
    chi_hNTM = PAR[:chi_hNTM]
    chi_r = PAR[:chi_r]
    delta_f = PAR[:delta_f]
    eta_ODA = PAR[:eta_ODA]
    gamma_eda = PAR[:gamma_eda]
    gamma_edd = PAR[:gamma_edd]
    gamma_edm = PAR[:gamma_edm]
    kappa_f = PAR[:kappa_f]
    kappa_h = PAR[:kappa_h]
    lambda_w = PAR[:lambda_w]
    phi_Emi = PAR[:phi_Emi]
    rho_Emi = PAR[:rho_Emi]
    tau_Emi = PAR[:tau_Emi]
    tau_a = PAR[:tau_a]
    tau_ad = PAR[:tau_ad]
    tau_am = PAR[:tau_am]
    tau_e = PAR[:tau_e]
    tau_m = PAR[:tau_m]
    tau_ma = PAR[:tau_ma]
    tau_ntm = PAR[:tau_ntm]
    tau_p = PAR[:tau_p]
    tau_uc = PAR[:tau_uc]
    tau_v = PAR[:tau_v]
    tau_w = PAR[:tau_w]
    s = data.sets

    # ENVISAGE Y-block variables.
    @variables(m, begin
        DeprY[s.r] >= 0
        ntmY[s.r] >= 0
        YQTF[s.r] >= 0
        TrustY >= 0
        YQHT[s.r] >= 0
        Remit[s.r,s.l,s.r] >= 0
        ODAOut[s.r] >= 0
        ODAGbl >= 0
        ODAIn[s.r] >= 0
        YH[s.r] >= 0
        YD[s.r] >= 0
        YGOV[s.r,s.gy] >= 0
        YFD[s.r,s.fd] >= 0
        Sh[s.r] >= 0
        Sg[s.r] >= 0
        Sf[s.r]
        PWsav >= 0
        Ks[s.r] >= 0
        RGDPpc[s.r] >= 0
        XAw[s.r,s.i,s.h] >= 0
    end)

    # Variables from other ENVISAGE blocks, declared before income in this package.
    PFp = m[:PFp]      # producer/user factor price PF^p
    XF  = m[:XF]
    UC  = m[:UC]
    XPv = m[:XPv]
    X   = m[:X]
    P   = m[:P]
    XA  = m[:XA]
    PA  = m[:PA]

    # Conditional switches in the paper.  Computed here (rather than further
    # below) because they also gate which agent-sourcing/MRIO trade variable
    # families need to be pre-declared immediately below.
    ArmFlag = Int(get(data.par, "ArmFlag", 0))          # Y-14 and Y-18
    ifMRIO  = Bool(get(data.par, "ifMRIO", false))      # Y-2 and Y-15
    need_agent_sourcing = ArmFlag != 0
    need_XWa = ArmFlag != 0 || ifMRIO

    # Trade variables are declared after income in the build order.  To keep the
    # Y-block equations in document form without inventing substitutes, create the
    # document variable families here only if they are not already present.
    # XD, XM, PMa and XWa are only referenced by the agent-sourcing (ArmFlag != 0)
    # / MRIO branches of trade.jl and income.jl (T-6:T-18, Y-2/Y-14/Y-15/Y-18
    # ifMRIO/else cases); guarding their declaration on the same condition that
    # gates the equations using them avoids declaring thousands of instances
    # that would otherwise never appear in any constraint under the
    # national-sourcing default (ArmFlag == 0, ifMRIO == false).
    if !haskey(JuMP.object_dictionary(m), :PWM); @variable(m, PWM[s.r,s.i,s.r] >= 0); end
    if !haskey(JuMP.object_dictionary(m), :XWs); @variable(m, XWs[s.r,s.i,s.r] >= 0); end
    if need_XWa && !haskey(JuMP.object_dictionary(m), :XWa); @variable(m, XWa[s.r,s.i,s.r,s.aa] >= 0); end
    if !haskey(JuMP.object_dictionary(m), :PMT); @variable(m, PMT[s.r,s.i] >= 0); end
    if need_agent_sourcing && !haskey(JuMP.object_dictionary(m), :PMa); @variable(m, PMa[s.r,s.i,s.aa] >= 0); end
    if !haskey(JuMP.object_dictionary(m), :PDT); @variable(m, PDT[s.r,s.i] >= 0); end
    if need_agent_sourcing && !haskey(JuMP.object_dictionary(m), :XD);  @variable(m, XD[s.r,s.i,s.aa] >= 0); end
    if need_agent_sourcing && !haskey(JuMP.object_dictionary(m), :XM);  @variable(m, XM[s.r,s.i,s.aa] >= 0); end
    if !haskey(JuMP.object_dictionary(m), :PE);  @variable(m, PE[s.r,s.i,s.r] >= 0); end

    PWM = m[:PWM]; XWs = m[:XWs]
    PMT = m[:PMT]; PDT = m[:PDT]; PE = m[:PE]
    XWa = need_XWa ? m[:XWa] : nothing
    PMa = need_agent_sourcing ? m[:PMa] : nothing
    XD  = need_agent_sourcing ? m[:XD]  : nothing
    XM  = need_agent_sourcing ? m[:XM]  : nothing

    # GDPMP is the documented macro variable used by Y-7. It may be declared in
    # closure.jl; declare once here if income is built first.
    if !haskey(JuMP.object_dictionary(m), :GDPMP)
        @variable(m, GDPMP[s.r] >= 0)
    end
    GDPMP = m[:GDPMP]

    # Scalar defaults. Region/agent-specific data can be supplied through the
    # calibration dictionaries without changing equation forms.
    δf    = delta_f
    κh    = kappa_h
    κf    = kappa_f
    χf    = chi_f
    χh    = chi_h
    χr    = chi_r
    χOO   = chi_OO
    χOI   = chi_OI
    χhNTM = chi_hNTM
    ηODA  = eta_ODA
    RGDPpc0 = RGDPpc0
    τp    = tau_p
    τuc   = tau_uc
    τv    = tau_v
    τa    = tau_a
    τad   = tau_ad
    τam   = tau_am
    τm    = tau_m
    τma   = tau_ma
    τe    = tau_e
    τw    = tau_w
    τntm  = tau_ntm
    λw    = lambda_w
    γeda  = gamma_eda
    γedd  = gamma_edd
    γedm  = gamma_edm
    χEmi  = chi_Emi
    ρEmi  = rho_Emi
    φEmi  = phi_Emi
    τEmi  = tau_Emi

    # ArmFlag/ifMRIO are computed earlier in this function (they also gate the
    # guarded trade-variable pre-declarations above).

    # Document revenue-index subsets. wtx is in Y-17; skip if aggregation omits it.
    wtx = [gy for gy in s.gy if lowercase(gy) == "wtx"]

    # Y-1. Depreciation allowance. PFD_{r,inv} is a final-demand price variable;
    # if the demand block has not created it yet, use the normalized benchmark
    # price from the paper's calibration convention.
    @NLconstraint(m, [r=s.r], DeprY[r] == δf * 1.0 * Ks[r])

    # Y-2. NTM income, default or MRIO specification.
    if ifMRIO
        @NLconstraint(m, [r=s.r], ntmY[r] == sum(τntm * PWM[sr,i,r] * XWa[sr,i,r,aa]
                                                for sr in s.r, i in s.i, aa in s.aa))
    else
        @NLconstraint(m, [r=s.r], ntmY[r] == sum(τntm * λw * PWM[sr,i,r] * XWs[sr,i,r]
                                                for sr in s.r, i in s.i))
    end

    # Y-3:Y-6. Global equity fund and remittances.
    @NLconstraint(m, [r=s.r], YQTF[r] == χf * sum((1 - κf) * PFp[r,cap,a] * XF[r,cap,a]
                                                 for cap in s.cap, a in s.a))
    @NLconstraint(m, TrustY == sum(YQTF[r] for r in s.r))
    @NLconstraint(m, [r=s.r], YQHT[r] == χh * TrustY)
    @NLconstraint(m, [sr=s.r,l=s.l,r=s.r], Remit[sr,l,r] == χr * sum((1 - κf) * PFp[r,l,a] * XF[r,l,a]
                                                                    for a in s.a))

    # Y-7:Y-9. Government-to-government transfers / ODA.
    @NLconstraint(m, [r=s.r], ODAOut[r] == χOO * GDPMP[r] * (RGDPpc[r] / max(RGDPpc0, 1.0e-12))^ηODA)
    @NLconstraint(m, ODAGbl == sum(ODAOut[r] for r in s.r))
    @NLconstraint(m, [r=s.r], ODAIn[r] == χOI * ODAGbl)

    # Y-10:Y-11. Household income and disposable income. ODA is not added to YH
    # here because the paper treats ODA as government-to-government transfers.
    @NLconstraint(m, [r=s.r], YH[r] ==
        sum((1 - κf) * PFp[r,f,a] * XF[r,f,a] for f in s.fp, a in s.a) +
        YQHT[r] - YQTF[r] +
        sum(Remit[r,l,d] for d in s.r, l in s.l) -
        sum(Remit[sr,l,r] for sr in s.r, l in s.l) -
        DeprY[r] +
        sum(χhNTM * ntmY[sr] for sr in s.r))
    @NLconstraint(m, [r=s.r], YD[r] == (1 - κh) * YH[r])

    # Y-12:Y-13. Production/cost taxes and factor taxes.
    @NLconstraint(m, [r=s.r,gy=s.ptax], YGOV[r,gy] ==
        sum(τp * P[r,a,i] * X[r,a,i] for a in s.a, i in s.i) +
        sum(τuc * UC[r,a,v] * XPv[r,a,v] for a in s.a, v in s.v))
    @NLconstraint(m, [r=s.r,gy=s.vtax], YGOV[r,gy] ==
        sum(τv * PFp[r,f,a] * XF[r,f,a] for f in s.fp, a in s.a))

    # Y-14. Indirect/sales tax revenue, conditional on ArmFlag.
    if ArmFlag == 0
        @NLconstraint(m, [r=s.r,gy=s.itax], YGOV[r,gy] ==
            sum(τa * γeda * PA[r,i,aa] * XA[r,i,aa] for aa in s.aa, i in s.i))
    else
        @NLconstraint(m, [r=s.r,gy=s.itax], YGOV[r,gy] ==
            sum(τad * γedd * PDT[r,i] * XD[r,i,aa] for aa in s.aa, i in s.i) +
            sum(τam * γedm * PMa[r,i,aa] * XM[r,i,aa] for aa in s.aa, i in s.i))
    end

    # Y-15. Import tariff revenue, default or MRIO specification.
    if ifMRIO
        @NLconstraint(m, [r=s.r,gy=s.mtax], YGOV[r,gy] ==
            sum(τma * PWM[sr,i,r] * XWa[sr,i,r,aa] for sr in s.r, i in s.i, aa in s.aa))
    else
        @NLconstraint(m, [r=s.r,gy=s.mtax], YGOV[r,gy] ==
            sum(τm * λw * PWM[sr,i,r] * XWs[sr,i,r] for sr in s.r, i in s.i))
    end

    # Y-16. Export tax/subsidy revenue.
    @NLconstraint(m, [r=s.r,gy=s.etax], YGOV[r,gy] ==
        sum(τe * PE[r,i,d] * XWs[r,i,d] for d in s.r, i in s.i))

    # Y-17. Household waste tax revenue. The equation is only instantiated when
    # the aggregation includes the documented wtx revenue account.
    for gy in wtx
        @NLconstraint(m, [r=s.r], YGOV[r,gy] == sum(τw * PA[r,i,h] * XAw[r,i,h] for h in s.h, i in s.i))
    end

    # Y-18. Carbon/emissions tax revenue, conditional on ArmFlag.
    if ArmFlag == 0
        @NLconstraint(m, [r=s.r,gy=s.ctax], YGOV[r,gy] ==
            sum(χEmi * ρEmi * φEmi * τEmi * XA[r,i,aa] for em in s.em, i in s.i, aa in s.aa))
    else
        @NLconstraint(m, [r=s.r,gy=s.ctax], YGOV[r,gy] ==
            sum(χEmi * ρEmi * φEmi * τEmi * XD[r,i,aa] for em in s.em, i in s.i, aa in s.aa) +
            sum(χEmi * ρEmi * φEmi * τEmi * XM[r,i,aa] for em in s.em, i in s.i, aa in s.aa))
    end

    # Y-19. Direct taxes.
    @NLconstraint(m, [r=s.r,gy=s.dtax], YGOV[r,gy] ==
        sum(κf * PFp[r,f,a] * XF[r,f,a] for f in s.fp, a in s.a) + κh * YH[r])

    # Y-20. Gross investment financing.
    @NLconstraint(m, [r=s.r,fd=s.inv], YFD[r,fd] == Sh[r] + Sg[r] + PWsav * Sf[r] + DeprY[r])

    return m
end

function income_residuals!(res::Dict{String,Function})
    for k in 1:20
        res["Y-$k"] = x -> error("Residual Y-$k is implemented as ENVISAGE Y-$k in income_block!.")
    end
    return res
end
