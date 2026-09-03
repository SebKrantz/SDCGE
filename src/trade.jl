# ENVISAGE v10.01 §3.6 International trade block, equations T-1:T-32.
# Document-strict implementation: uses the ENVISAGE trade variable families only
# (XAT, XDTd, XDTs, XMT, PAT, PDT, PMT, XD, XM, PA, PD, PM, XWd,
# XWa, PMa, PDMa, XET, PET, XWs, PE, PWE, PWM, PDM, XWMG, XMG,
# PWMG, XTMG, XTT, PTMG). Document cases follow ArmFlag and the omega-infinity cases only.

function trade_block!(m::JuMP.Model, data::EnvData, cal::EnvCalibration)
    PAR = parameters(data, cal)
    # Local parameter aliases generated from ParameterTables.jl.
    alpha_aa = PAR[:alpha_aa]
    alpha_d = PAR[:alpha_d]
    alpha_dt = PAR[:alpha_dt]
    alpha_m = PAR[:alpha_m]
    alpha_mg = PAR[:alpha_mg]
    alpha_mt = PAR[:alpha_mt]
    alpha_tt = PAR[:alpha_tt]
    alpha_w = PAR[:alpha_w]
    alpha_wa = PAR[:alpha_wa]
    chi_Emi = PAR[:chi_Emi]
    gamma_d = PAR[:gamma_d]
    gamma_e = PAR[:gamma_e]
    gamma_eda = PAR[:gamma_eda]
    gamma_edd = PAR[:gamma_edd]
    gamma_edm = PAR[:gamma_edm]
    gamma_esd = PAR[:gamma_esd]
    gamma_ese = PAR[:gamma_ese]
    gamma_ew = PAR[:gamma_ew]
    lambda_mg = PAR[:lambda_mg]
    lambda_w = PAR[:lambda_w]
    omega_w = PAR[:omega_w]
    omega_x = PAR[:omega_x]
    phi_Emi = PAR[:phi_Emi]
    rho_Emi = PAR[:rho_Emi]
    rho_Emid = PAR[:rho_Emid]
    rho_Emim = PAR[:rho_Emim]
    sigma_m = PAR[:sigma_m]
    sigma_mg = PAR[:sigma_mg]
    sigma_mt = PAR[:sigma_mt]
    sigma_w = PAR[:sigma_w]
    sigma_wa = PAR[:sigma_wa]
    tau_Emi = PAR[:tau_Emi]
    tau_a = PAR[:tau_a]
    tau_ad = PAR[:tau_ad]
    tau_am = PAR[:tau_am]
    tau_e = PAR[:tau_e]
    tau_m = PAR[:tau_m]
    tau_ma = PAR[:tau_ma]
    tau_ntm = PAR[:tau_ntm]
    zeta_mg = PAR[:zeta_mg]
    s = data.sets
    nr = max(length(s.r), 1)
    ni = max(length(s.i), 1)
    naa = max(length(s.aa), 1)

    # ArmFlag is the document's top-level sourcing control: 0 => national sourcing,
    # nonzero => agent sourcing. No additional trade-regime switch is used.
    ArmFlag = Int(get(data.par, "ArmFlag", 0))

    # Declare ENVISAGE trade variable families using standard JuMP syntax.
    # PD, PM and PDMa are the agent-specific domestic/import prices used only by
    # the agent-sourcing equations T-6:T-10 and T-15:T-18 (ArmFlag != 0 branch
    # below); guard their declaration on ArmFlag so they are not left as
    # thousands of undetermined instances under the national-sourcing default.
    @variables(m, begin
        XAT[s.r, s.i] >= 0
        XDTd[s.r, s.i] >= 0
        XDTs[s.r, s.i] >= 0
        XMT[s.r, s.i] >= 0
        PAT[s.r, s.i] >= 0
        PDM[s.r, s.i, s.r] >= 0
        XWd[s.r, s.i, s.r] >= 0
        XET[s.r, s.i] >= 0
        PET[s.r, s.i] >= 0
        PWE[s.r, s.i, s.r] >= 0
        PWMG[s.r, s.i, s.r] >= 0
        XWMG[s.r, s.i, s.r] >= 0
        XMG[s.i, s.r, s.i, s.r] >= 0
        XTMG[s.i] >= 0
        PTMG[s.i] >= 0
        XTT[s.r, s.i] >= 0
    end)
    if ArmFlag != 0
        @variables(m, begin
            PD[s.r, s.i, s.aa] >= 0
            PM[s.r, s.i, s.aa] >= 0
            PDMa[s.r, s.i, s.r, s.aa] >= 0
        end)
    end

    # These variables are declared in earlier blocks and are used here by
    # the trade equations exactly as named in the ENVISAGE document.
    XA = m[:XA]
    PA = m[:PA]
    XS = m[:XS]
    PS = m[:PS]
    PDT = m[:PDT]
    PMT = m[:PMT]
    XWs = m[:XWs]
    PE = m[:PE]
    PWM = m[:PWM]
    XD  = ArmFlag != 0 ? m[:XD]  : nothing
    XM  = ArmFlag != 0 ? m[:XM]  : nothing
    XWa = haskey(JuMP.object_dictionary(m), :XWa) ? m[:XWa] : nothing
    PMa = ArmFlag != 0 ? m[:PMa] : nothing
    PD  = ArmFlag != 0 ? m[:PD]   : nothing
    PM  = ArmFlag != 0 ? m[:PM]   : nothing
    PDMa = ArmFlag != 0 ? m[:PDMa] : nothing

    σmt = sigma_mt
    σm  = sigma_m
    σwa = sigma_wa
    σw  = sigma_w
    ωx  = omega_x
    ωw  = omega_w
    σmg = sigma_mg

    τa  = tau_a
    τad = tau_ad
    τam = tau_am
    τma = tau_ma
    τm  = tau_m
    τe  = tau_e
    τntm = tau_ntm
    ζmg = zeta_mg
    λw = lambda_w
    λmg = lambda_mg
    γeda = gamma_eda
    γesd = gamma_esd
    γese = gamma_ese
    γew = gamma_ew
    γedd = gamma_edd
    γedm = gamma_edm

    χEmi = chi_Emi
    ρEmi = rho_Emi
    ρEmid = rho_Emid
    ρEmim = rho_Emim
    φEmi = phi_Emi
    τEmi = tau_Emi

    αaa = alpha_aa
    αdt = alpha_dt
    αmt = alpha_mt
    αd  = alpha_d
    αm  = alpha_m
    αw  = alpha_w
    αwa = alpha_wa
    γd  = gamma_d
    γe  = gamma_e
    αmg = alpha_mg
    αtt = alpha_tt

    if ArmFlag == 0
        # National sourcing of aggregate imports: T-1:T-5.
        @NLconstraints(m, begin
            # (T-1)
            [r=s.r,i=s.i], XAT[r,i] == sum(γeda * XA[r,i,aa] for aa in s.aa)
            # (T-2)
            [r=s.r,i=s.i], XDTd[r,i] == αdt * (PAT[r,i] / PDT[r,i])^σmt * XAT[r,i] + XTT[r,i]
            # (T-3)
            [r=s.r,i=s.i], XMT[r,i] == αmt * (PAT[r,i] / PMT[r,i])^σmt * XAT[r,i]
            # (T-4)
            [r=s.r,i=s.i], PAT[r,i] == (αdt * PDT[r,i]^(1-σmt) + αmt * PMT[r,i]^(1-σmt))^(1/(1-σmt))
            # (T-5)
            [r=s.r,i=s.i,aa=s.aa], PA[r,i,aa] == (1 + τa) * γeda * PAT[r,i] + sum(χEmi * ρEmi * φEmi * τEmi for em in s.em)
        end)

        # Standard second-level Armington nest: T-13:T-14.
        @NLconstraints(m, begin
            # (T-13)
            [sr=s.r,i=s.i,r=s.r], XWd[sr,i,r] == αw[sr] * (PMT[r,i] / PDM[sr,i,r])^σw * XMT[r,i]
            # (T-14)
            [r=s.r,i=s.i], PMT[r,i] == (sum(αw[sr] * PDM[sr,i,r]^(1-σw) for sr in s.r))^(1/(1-σw))
        end)
    else
        # Agent sourcing of aggregate imports: T-6:T-12.
        @NLconstraints(m, begin
            # (T-6)
            [r=s.r,i=s.i,aa=s.aa], XD[r,i,aa] == αd * (PA[r,i,aa] / PD[r,i,aa])^σmt * XA[r,i,aa]
            # (T-7)
            [r=s.r,i=s.i,aa=s.aa], XM[r,i,aa] == αm * (PA[r,i,aa] / PM[r,i,aa])^σmt * XA[r,i,aa]
            # (T-8)
            [r=s.r,i=s.i,aa=s.aa], PA[r,i,aa] == (αd * PD[r,i,aa]^(1-σmt) + αm * PM[r,i,aa]^(1-σmt))^(1/(1-σmt))
            # (T-9)
            [r=s.r,i=s.i,aa=s.aa], PD[r,i,aa] == (1 + τad) * γedd * PDT[r,i] + sum(χEmi * ρEmid * φEmi * τEmi for em in s.em)
            # (T-10)
            [r=s.r,i=s.i,aa=s.aa], PM[r,i,aa] == (1 + τam) * γedm * PMa[r,i,aa] + sum(χEmi * ρEmim * φEmi * τEmi for em in s.em)
            # (T-11)
            [r=s.r,i=s.i], XDTd[r,i] == sum(γedd * XD[r,i,aa] for aa in s.aa) + XTT[r,i]
            # (T-12)
            [r=s.r,i=s.i], XMT[r,i] == sum(γedm * XM[r,i,aa] for aa in s.aa)
        end)

        # Standard second-level Armington nest: T-13:T-14.
        @NLconstraints(m, begin
            # (T-13)
            [sr=s.r,i=s.i,r=s.r], XWd[sr,i,r] == αw[sr] * (PMT[r,i] / PDM[sr,i,r])^σw * XMT[r,i]
            # (T-14)
            [r=s.r,i=s.i], PMT[r,i] == (sum(αw[sr] * PDM[sr,i,r]^(1-σw) for sr in s.r))^(1/(1-σw))
        end)

        # MRIO equations from the document, T-15:T-18. They are included only
        # with agent sourcing, as stated in footnote 40; no non-document flag is used.
        @NLconstraints(m, begin
            # (T-15)
            [sr=s.r,i=s.i,r=s.r,aa=s.aa], XWa[sr,i,r,aa] == αwa[(sr,aa)] * (PMa[r,i,aa] / PDMa[sr,i,r,aa])^σwa * XM[r,i,aa]
            # (T-16)
            [r=s.r,i=s.i,aa=s.aa], PMa[r,i,aa] * XM[r,i,aa] == sum(PDMa[sr,i,r,aa] * XWa[sr,i,r,aa] for sr in s.r)
            # (T-17)
            [sr=s.r,i=s.i,r=s.r,aa=s.aa], PDMa[sr,i,r,aa] == (1 + τma) * PWM[sr,i,r]
            # (T-18)
            [sr=s.r,i=s.i,r=s.r], XWd[sr,i,r] == sum(XWa[sr,i,r,aa] for aa in s.aa)
        end)
    end

    # Export supply, T-19:T-23. The if branches are the document's own
    # ω = ∞ cases in T-19, T-20 and T-22.
    if isinf(ωx)
        @NLconstraints(m, begin
            # (T-19), ωx = ∞
            [r=s.r,i=s.i], PDT[r,i] == γesd * PS[r,i]
            # (T-20), ωx = ∞
            [r=s.r,i=s.i], PET[r,i] == γese * PS[r,i]
        end)
    else
        @NLconstraints(m, begin
            # (T-19), ωx != ∞
            [r=s.r,i=s.i], XDTs[r,i] == γd * γesd^(-ωx - 1) * (PDT[r,i] / PS[r,i])^ωx * XS[r,i]
            # (T-20), ωx != ∞
            [r=s.r,i=s.i], XET[r,i] == γe * γese^(-ωx - 1) * (PET[r,i] / PS[r,i])^ωx * XS[r,i]
        end)
    end
    # (T-21)
    @NLconstraint(m, [r=s.r,i=s.i], PS[r,i] * XS[r,i] == PDT[r,i] * XDTs[r,i] + PET[r,i] * XET[r,i])

    if isinf(ωw)
        # (T-22), ωw = ∞
        @NLconstraint(m, [r=s.r,i=s.i,d=s.r], PE[r,i,d] == γew * PET[r,i])
    else
        # (T-22), ωw != ∞
        @NLconstraint(m, [r=s.r,i=s.i,d=s.r], XWs[r,i,d] == αw[d] * γew^(-ωw - 1) * (PE[r,i,d] / PET[r,i])^ωw * XET[r,i])
    end
    # (T-23)
    @NLconstraint(m, [r=s.r,i=s.i], PET[r,i] * XET[r,i] == sum(PE[r,i,d] * XWs[r,i,d] for d in s.r))

    @NLconstraints(m, begin
        # (T-24)
        [r=s.r,i=s.i,d=s.r], PWE[r,i,d] == (1 + τe) * PE[r,i,d]
        # (T-25)
        [r=s.r,i=s.i,d=s.r], PWM[r,i,d] == (PWE[r,i,d] + PWMG[r,i,d] * ζmg) / λw
        # (T-26)
        [r=s.r,i=s.i,d=s.r], PDM[r,i,d] == (1 + τm + τntm) * PWM[r,i,d]
        # (T-27)
        [r=s.r,i=s.i,d=s.r], XWMG[r,i,d] == ζmg * XWs[r,i,d]
        # (T-28)
        [mrg=s.i,r=s.r,i=s.i,d=s.r], XMG[mrg,r,i,d] == αmg[mrg] * XWMG[r,i,d] / λmg
        # (T-29)
        [r=s.r,i=s.i,d=s.r], PWMG[r,i,d] == sum(αmg[mrg] * PTMG[mrg] / λmg for mrg in s.i)
        # (T-30)
        [mrg=s.i], XTMG[mrg] == sum(XMG[mrg,r,i,d] for r in s.r, i in s.i, d in s.r)
        # (T-31)
        [r=s.r,mrg=s.i], XTT[r,mrg] == αtt[r] * (PTMG[mrg] / PDT[r,mrg])^σmg * XTMG[mrg]
        # (T-32)
        [mrg=s.i], PTMG[mrg] * XTMG[mrg] == sum(PDT[r,mrg] * XTT[r,mrg] for r in s.r)
    end)
    return m
end

function trade_residuals!(res::Dict{String,Function})
    for k in 1:32
        res["T-$k"] = x -> error("Residual T-$k is implemented as ENVISAGE T-$k in trade_block!.")
    end
    return res
end
