# === Function usage ===
# Production block: declares production variables and equations.
# Usage:
#   m = Model(PATHSolver.Optimizer)
#   production_block!(m, data, cal)
#
# Normally you do not call this directly; build_model(data, cal) calls it in
# the correct order. Use direct calls only when debugging a single block.
# ======================

function production_block!(m::JuMP.Model, data::EnvData, cal::EnvCalibration)
    PAR = parameters(data, cal)
    # Local parameter aliases generated from ParameterTables.jl.
    alpha_crop_va1_ND2 = PAR[:alpha_crop_va1_ND2]
    alpha_crop_va1_VA2 = PAR[:alpha_crop_va1_VA2]
    alpha_crop_va2_KEF = PAR[:alpha_crop_va2_KEF]
    alpha_crop_va2_LAND = PAR[:alpha_crop_va2_LAND]
    alpha_crop_va_LAB1 = PAR[:alpha_crop_va_LAB1]
    alpha_crop_va_VA1 = PAR[:alpha_crop_va_VA1]
    alpha_def_va1_KEF = PAR[:alpha_def_va1_KEF]
    alpha_def_va1_VA2 = PAR[:alpha_def_va1_VA2]
    alpha_def_va_LAB1 = PAR[:alpha_def_va_LAB1]
    alpha_def_va_VA1 = PAR[:alpha_def_va_VA1]
    alpha_energy = PAR[:alpha_energy]
    alpha_energy_top_ELY = PAR[:alpha_energy_top_ELY]
    alpha_energy_top_NELY = PAR[:alpha_energy_top_NELY]
    alpha_io = PAR[:alpha_io]
    alpha_io2 = PAR[:alpha_io2]
    alpha_kef_ENERGY = PAR[:alpha_kef_ENERGY]
    alpha_kef_KF = PAR[:alpha_kef_KF]
    alpha_kef_KSW = PAR[:alpha_kef_KSW]
    alpha_kef_NRS = PAR[:alpha_kef_NRS]
    alpha_ks_CAP = PAR[:alpha_ks_CAP]
    alpha_ks_LAB2 = PAR[:alpha_ks_LAB2]
    alpha_ksw_KS = PAR[:alpha_ksw_KS]
    alpha_ksw_WAT = PAR[:alpha_ksw_WAT]
    alpha_lab1 = PAR[:alpha_lab1]
    alpha_lab2 = PAR[:alpha_lab2]
    alpha_livestock_va1_KEF = PAR[:alpha_livestock_va1_KEF]
    alpha_livestock_va1_VA2 = PAR[:alpha_livestock_va1_VA2]
    alpha_livestock_va2_FEED = PAR[:alpha_livestock_va2_FEED]
    alpha_livestock_va2_LAND = PAR[:alpha_livestock_va2_LAND]
    alpha_livestock_va_LAB1 = PAR[:alpha_livestock_va_LAB1]
    alpha_livestock_va_VA1 = PAR[:alpha_livestock_va_VA1]
    alpha_livestock_va_VA2 = PAR[:alpha_livestock_va_VA2]
    alpha_nely_COA = PAR[:alpha_nely_COA]
    alpha_nely_OLG = PAR[:alpha_nely_OLG]
    alpha_olg_GAS = PAR[:alpha_olg_GAS]
    alpha_olg_OIL = PAR[:alpha_olg_OIL]
    alpha_top_ND1 = PAR[:alpha_top_ND1]
    alpha_top_VA = PAR[:alpha_top_VA]
    alpha_water = PAR[:alpha_water]
    alpha_water_WAT = PAR[:alpha_water_WAT]
    alpha_xp_XGHG = PAR[:alpha_xp_XGHG]
    alpha_xp_XPX = PAR[:alpha_xp_XPX]
    lambda_ep = PAR[:lambda_ep]
    lambda_f = PAR[:lambda_f]
    lambda_ghg = PAR[:lambda_ghg]
    lambda_io = PAR[:lambda_io]
    lambda_xp = PAR[:lambda_xp]
    sigma_erg = PAR[:sigma_erg]
    sigma_k = PAR[:sigma_k]
    sigma_kef = PAR[:sigma_kef]
    sigma_kf = PAR[:sigma_kf]
    sigma_kw = PAR[:sigma_kw]
    sigma_n1 = PAR[:sigma_n1]
    sigma_n2 = PAR[:sigma_n2]
    sigma_nely = PAR[:sigma_nely]
    sigma_nrg = PAR[:sigma_nrg]
    sigma_olg = PAR[:sigma_olg]
    sigma_p = PAR[:sigma_p]
    sigma_sl = PAR[:sigma_sl]
    sigma_ul = PAR[:sigma_ul]
    sigma_v = PAR[:sigma_v]
    sigma_v1 = PAR[:sigma_v1]
    sigma_v2 = PAR[:sigma_v2]
    sigma_wat = PAR[:sigma_wat]
    sigma_xp = PAR[:sigma_xp]
    tau_uc = PAR[:tau_uc]
    s = data.sets
    n_i = max(length(s.i),1); n_ul = max(length(s.ul),1); n_sl = max(length(s.sl),1); n_nrg = max(length(s.nrg),1); n_wat = max(length(s.wat),1)
    # ENVISAGE P-9:P-17 split `a` into crops, livestock and "all other
    # activities".  `s.ax` from the workbook omits the power activities
    # (`elya`), which left them without a value-added nest, so the document's
    # own default branch a \ (acr ∪ alv) is used instead (see types.jl).
    adef = default_activities(s)
    # Activities that use land: only crops and livestock have a land nest in
    # P-14, so land demand/supply is restricted to them (F-33/F-36).
    aland = [a for a in s.a if a in s.acr || a in s.alv]

    # Parameters are precomputed in ParameterTables.jl and indexed directly as PAR[:...].

    @variables(m, begin
        # Top production nest, P-1:P-8
        XP[s.r,s.a] >= 0; XPv[s.r,s.a,s.v] >= 0; PX[s.r,s.a] >= 0; PXv[s.r,s.a,s.v] >= 0
        UC[s.r,s.a,s.v] >= 0; XPX[s.r,s.a,s.v] >= 0; XGHG[s.r,s.a,s.v] >= 0
        PXP[s.r,s.a,s.v] >= 0; PXGHG[s.r,s.a,s.v] >= 0
        ND1[s.r,s.a] >= 0; PND1[s.r,s.a] >= 0; VA[s.r,s.a,s.v] >= 0; PVA[s.r,s.a,s.v] >= 0
        # Intermediate nests, P-9:P-17
        VA1[s.r,s.a,s.v] >= 0; PVA1[s.r,s.a,s.v] >= 0; VA2[s.r,s.a,s.v] >= 0; PVA2[s.r,s.a,s.v] >= 0
        LAB1[s.r,s.a] >= 0; PLAB1[s.r,s.a] >= 0; LAB2[s.r,s.a] >= 0; PLAB2[s.r,s.a] >= 0
        ND2[s.r,s.a] >= 0; PND2[s.r,s.a] >= 0
        # KEF/KF/KSW/KS, P-18:P-29
        KEF[s.r,s.a,s.v] >= 0; PKEF[s.r,s.a,s.v] >= 0
        KF[s.r,s.a,s.v] >= 0; PKF[s.r,s.a,s.v] >= 0
        KSW[s.r,s.a,s.v] >= 0; PKSW[s.r,s.a,s.v] >= 0
        KS[s.r,s.a,s.v] >= 0; PKS[s.r,s.a,s.v] >= 0
        K[s.r,s.a,s.v] >= 0; PKp[s.r,s.a,s.v] >= 0
        XWAT[s.r,s.a] >= 0; PWAT[s.r,s.a] >= 0
        XF[s.r,s.fp,s.a] >= 0; PFp[s.r,s.fp,s.a] >= 0
        # Intermediate and energy nests, P-30:P-48
        # ENVISAGE has a single Armington purchaser price PA[r,i,aa] (T-5) for
        # every agent aa, activities included.  The former `PAa[r,i,a]` family was
        # a duplicate of the activity slice PA[r,i,a]: it carried no equation of
        # its own (1,260 undetermined instances) while T-5 already prices exactly
        # the same flows.  P-33/P-34/P-35/P-47/P-48 now read PA[r,i,a] directly.
        XA[s.r,s.i,s.aa] >= 0; PA[s.r,s.i,s.aa] >= 0
        XNRG[s.r,s.a,s.v] >= 0; PNRG[s.r,s.a,s.v] >= 0
        XNELY[s.r,s.a,s.v] >= 0; PNELY[s.r,s.a,s.v] >= 0
        XOLG[s.r,s.a,s.v] >= 0; POLG[s.r,s.a,s.v] >= 0
        XAely[s.r,s.a,s.v] >= 0; PAely[s.r,s.a,s.v] >= 0
        XAcoa[s.r,s.a,s.v] >= 0; PAcoa[s.r,s.a,s.v] >= 0
        XAoil[s.r,s.a,s.v] >= 0; PAoil[s.r,s.a,s.v] >= 0
        XAgas[s.r,s.a,s.v] >= 0; PAgas[s.r,s.a,s.v] >= 0
    end)

    @NLconstraints(m, begin
        # (P-1) aggregate unit cost across vintages
        [r=s.r,a=s.a], PX[r,a] * XP[r,a] == sum(PXv[r,a,v] * XPv[r,a,v] for v in s.v)
        # (P-2) tax-adjusted vintage unit cost
        [r=s.r,a=s.a,v=s.v], PXv[r,a,v] == UC[r,a,v] * (1 + tau_uc)
        # (P-3)--(P-4) top CES demands
        [r=s.r,a=s.a,v=s.v], XPX[r,a,v] == alpha_xp_XPX[a] * (lambda_xp * UC[r,a,v] / PXP[r,a,v])^sigma_xp * XPv[r,a,v]
        [r=s.r,a=s.a,v=s.v], XGHG[r,a,v] == alpha_xp_XGHG[a] * (lambda_ghg * UC[r,a,v] / PXGHG[r,a,v])^sigma_xp * XPv[r,a,v]
        # (P-5) top CES dual price
        [r=s.r,a=s.a,v=s.v], UC[r,a,v] == (alpha_xp_XPX[a]*(PXP[r,a,v]/lambda_xp)^(1-sigma_xp) + alpha_xp_XGHG[a]*(PXGHG[r,a,v]/lambda_ghg)^(1-sigma_xp))^(1/(1-sigma_xp))
        # (P-6)--(P-8) ND1/VA split and dual price
        [r=s.r,a=s.a], ND1[r,a] == sum(alpha_top_ND1[a] * (PXP[r,a,v] / PND1[r,a])^sigma_p * XPX[r,a,v] for v in s.v)
        [r=s.r,a=s.a,v=s.v], VA[r,a,v] == alpha_top_VA[a] * (PXP[r,a,v] / PVA[r,a,v])^sigma_p * XPX[r,a,v]
        [r=s.r,a=s.a,v=s.v], PXP[r,a,v] == (alpha_top_ND1[a]*PND1[r,a]^(1-sigma_p) + alpha_top_VA[a]*PVA[r,a,v]^(1-sigma_p))^(1/(1-sigma_p))
        # (P-9)--(P-17) middle nests by Table 3.1 activity subsets.
        # Crops use acr only; livestock uses alv only; default/other activities use ax only.
        [r=s.r,a=s.acr,v=s.v], VA1[r,a,v] == alpha_crop_va_VA1[a] * (PVA[r,a,v]/PVA1[r,a,v])^sigma_v * VA[r,a,v]
        [r=s.r,a=s.alv,v=s.v], VA1[r,a,v] == alpha_livestock_va_VA1[a] * (PVA[r,a,v]/PVA1[r,a,v])^sigma_v * VA[r,a,v]
        [r=s.r,a=adef,v=s.v], VA1[r,a,v] == alpha_def_va_VA1[a] * (PVA[r,a,v]/PVA1[r,a,v])^sigma_v * VA[r,a,v]
        [r=s.r,a=s.acr,v=s.v], VA2[r,a,v] == alpha_crop_va1_VA2[a] * (PVA1[r,a,v]/PVA2[r,a,v])^sigma_v1 * VA1[r,a,v]
        [r=s.r,a=s.alv,v=s.v], VA2[r,a,v] == alpha_livestock_va1_VA2[a] * (PVA1[r,a,v]/PVA2[r,a,v])^sigma_v1 * VA1[r,a,v]
        [r=s.r,a=s.acr,v=s.v], KEF[r,a,v] == alpha_crop_va2_KEF[a] * (PVA2[r,a,v]/PKEF[r,a,v])^sigma_v2 * VA2[r,a,v]
        [r=s.r,a=s.alv,v=s.v], KEF[r,a,v] == alpha_livestock_va1_KEF[a] * (PVA1[r,a,v]/PKEF[r,a,v])^sigma_v1 * VA1[r,a,v]
        [r=s.r,a=adef,v=s.v], KEF[r,a,v] == alpha_def_va1_KEF[a] * (PVA1[r,a,v]/PKEF[r,a,v])^sigma_v1 * VA1[r,a,v]
        [r=s.r,a=s.acr], LAB1[r,a] == sum(alpha_crop_va_LAB1[a] * (PVA[r,a,v]/PLAB1[r,a])^sigma_v * VA[r,a,v] for v in s.v)
        [r=s.r,a=s.alv], LAB1[r,a] == sum(alpha_livestock_va_LAB1[a] * (PVA[r,a,v]/PLAB1[r,a])^sigma_v * VA[r,a,v] for v in s.v)
        [r=s.r,a=adef], LAB1[r,a] == sum(alpha_def_va_LAB1[a] * (PVA[r,a,v]/PLAB1[r,a])^sigma_v * VA[r,a,v] for v in s.v)
        [r=s.r,a=s.acr], ND2[r,a] == sum(alpha_crop_va1_ND2[a] * (PVA1[r,a,v]/PND2[r,a])^sigma_v1 * VA1[r,a,v] for v in s.v)
        [r=s.r,a=s.alv], ND2[r,a] == sum(alpha_livestock_va2_FEED[a] * (PVA2[r,a,v]/PND2[r,a])^sigma_v2 * VA2[r,a,v] for v in s.v)
        # (P-14) land factor demand is restricted to crop and livestock activities and lnd factors.
        [r=s.r,a=s.acr,f=s.lnd], XF[r,f,a] == sum(alpha_crop_va2_LAND[a] * (lambda_f*PVA2[r,a,v]/PFp[r,f,a])^sigma_v2 * VA2[r,a,v] / lambda_f for v in s.v)
        [r=s.r,a=s.alv,f=s.lnd], XF[r,f,a] == sum(alpha_livestock_va2_LAND[a] * (lambda_f*PVA2[r,a,v]/PFp[r,f,a])^sigma_v2 * VA2[r,a,v] / lambda_f for v in s.v)
        # (P-15)--(P-17) CES dual prices for VA, VA1, VA2 by subset.
        [r=s.r,a=s.acr,v=s.v], PVA[r,a,v] == (alpha_crop_va_LAB1[a]*PLAB1[r,a]^(1-sigma_v) + alpha_crop_va_VA1[a]*PVA1[r,a,v]^(1-sigma_v))^(1/(1-sigma_v))
        [r=s.r,a=s.alv,v=s.v], PVA[r,a,v] == (alpha_livestock_va_VA1[a]*PVA1[r,a,v]^(1-sigma_v) + alpha_livestock_va_VA2[a]*PVA2[r,a,v]^(1-sigma_v))^(1/(1-sigma_v))
        [r=s.r,a=adef,v=s.v], PVA[r,a,v] == (alpha_def_va_LAB1[a]*PLAB1[r,a]^(1-sigma_v) + alpha_def_va_VA1[a]*PVA1[r,a,v]^(1-sigma_v))^(1/(1-sigma_v))
        [r=s.r,a=s.acr,v=s.v], PVA1[r,a,v] == (alpha_crop_va1_ND2[a]*PND2[r,a]^(1-sigma_v1) + alpha_crop_va1_VA2[a]*PVA2[r,a,v]^(1-sigma_v1))^(1/(1-sigma_v1))
        [r=s.r,a=s.alv,v=s.v], PVA1[r,a,v] == (alpha_livestock_va1_VA2[a]*PVA2[r,a,v]^(1-sigma_v1) + alpha_livestock_va1_KEF[a]*PKEF[r,a,v]^(1-sigma_v1))^(1/(1-sigma_v1))
        [r=s.r,a=adef,v=s.v], PVA1[r,a,v] == (alpha_def_va1_KEF[a]*PKEF[r,a,v]^(1-sigma_v1) + alpha_def_va1_VA2[a]*PVA2[r,a,v]^(1-sigma_v1))^(1/(1-sigma_v1))
        [r=s.r,a=s.acr,v=s.v], PVA2[r,a,v] == (alpha_crop_va2_LAND[a]*PVA1[r,a,v]^(1-sigma_v2) + alpha_crop_va2_KEF[a]*PKEF[r,a,v]^(1-sigma_v2))^(1/(1-sigma_v2))
        [r=s.r,a=s.alv,v=s.v], PVA2[r,a,v] == (alpha_livestock_va2_LAND[a]*PVA1[r,a,v]^(1-sigma_v2) + alpha_livestock_va2_FEED[a]*PND2[r,a]^(1-sigma_v2))^(1/(1-sigma_v2))
        # (P-18)--(P-20) KEF nest
        [r=s.r,a=s.a,v=s.v], KF[r,a,v] == alpha_kef_KF[a] * (PKEF[r,a,v]/PKF[r,a,v])^sigma_kef * KEF[r,a,v]
        [r=s.r,a=s.a,v=s.v], XNRG[r,a,v] == alpha_kef_ENERGY[a] * (PKEF[r,a,v]/PNRG[r,a,v])^sigma_kef * KEF[r,a,v]
        [r=s.r,a=s.a,v=s.v], PKEF[r,a,v] == (alpha_kef_KF[a]*PKF[r,a,v]^(1-sigma_kef) + alpha_kef_ENERGY[a]*PNRG[r,a,v]^(1-sigma_kef))^(1/(1-sigma_kef))
        # (P-21)--(P-23) KF nest: KSW plus natural resource
        [r=s.r,a=s.a,v=s.v], KSW[r,a,v] == alpha_kef_KSW[a] * (PKF[r,a,v]/PKSW[r,a,v])^sigma_kf * KF[r,a,v]
        [r=s.r,a=s.a,f=s.nrs], XF[r,f,a] == sum(alpha_kef_NRS[a] * (lambda_f*PKF[r,a,v]/PFp[r,f,a])^sigma_kf * KF[r,a,v] / lambda_f for v in s.v)
        [r=s.r,a=s.a,v=s.v], PKF[r,a,v] == (alpha_kef_KSW[a]*PKSW[r,a,v]^(1-sigma_kf) + alpha_kef_NRS[a]*(PKSW[r,a,v])^(1-sigma_kf))^(1/(1-sigma_kf))
        # (P-24)--(P-26) KSW nest: KS and water bundle
        [r=s.r,a=s.a,v=s.v], KS[r,a,v] == alpha_ksw_KS[a] * (PKSW[r,a,v]/PKS[r,a,v])^sigma_kw * KSW[r,a,v]
        [r=s.r,a=s.a], XWAT[r,a] == sum(alpha_ksw_WAT[a] * (PKSW[r,a,v]/PWAT[r,a])^sigma_kw * KSW[r,a,v] for v in s.v)
        [r=s.r,a=s.a,v=s.v], PKSW[r,a,v] == (alpha_ksw_KS[a]*PKS[r,a,v]^(1-sigma_kw) + alpha_ksw_WAT[a]*PWAT[r,a]^(1-sigma_kw))^(1/(1-sigma_kw))
        # (P-27)--(P-29) KS nest: capital by vintage and skilled labor bundle
        [r=s.r,a=s.a,v=s.v], K[r,a,v] == alpha_ks_CAP[a] * (lambda_f*PKS[r,a,v]/PKp[r,a,v])^sigma_k * KS[r,a,v] / lambda_f
        [r=s.r,a=s.a], LAB2[r,a] == sum(alpha_ks_LAB2[a] * (PKS[r,a,v]/PLAB2[r,a])^sigma_k * KS[r,a,v] for v in s.v)
        [r=s.r,a=s.a,v=s.v], PKS[r,a,v] == (alpha_ks_CAP[a]*(PKp[r,a,v]/lambda_f)^(1-sigma_k) + alpha_ks_LAB2[a]*PLAB2[r,a]^(1-sigma_k))^(1/(1-sigma_k))
        # (P-30)--(P-32) labor bundles
        [r=s.r,a=s.a,l=s.ul], XF[r,l,a] == alpha_lab1[(a,l)] * (lambda_f*PLAB1[r,a]/PFp[r,l,a])^sigma_ul * LAB1[r,a] / lambda_f
        [r=s.r,a=s.a,l=s.sl], XF[r,l,a] == alpha_lab2[(a,l)] * (lambda_f*PLAB2[r,a]/PFp[r,l,a])^sigma_sl * LAB2[r,a] / lambda_f
        [r=s.r,a=s.a], PLAB1[r,a] == (sum(alpha_lab1[(a,l)]*(PFp[r,l,a]/lambda_f)^(1-sigma_ul) for l in s.ul))^(1/(1-sigma_ul))
        [r=s.r,a=s.a], PLAB2[r,a] == (sum(alpha_lab2[(a,l)]*(PFp[r,l,a]/lambda_f)^(1-sigma_sl) for l in s.sl))^(1/(1-sigma_sl))
        # (P-33)--(P-37) non-energy intermediate and water bundles
        [r=s.r,a=s.a,i=setdiff(s.i,s.nrg)], XA[r,i,a] == alpha_io[(a,i)] * (lambda_io*PND1[r,a]/PA[r,i,a])^sigma_n1 * ND1[r,a] / lambda_io
        [r=s.r,a=s.a], PND1[r,a] == (sum(alpha_io[(a,i)]*(PA[r,i,a]/lambda_io)^(1-sigma_n1) for i in setdiff(s.i,s.nrg)))^(1/(1-sigma_n1))
        [r=s.r,a=s.a], PND2[r,a] == (sum(alpha_io2[(a,i)]*(PA[r,i,a]/lambda_io)^(1-sigma_n2) for i in setdiff(s.i,s.nrg)))^(1/(1-sigma_n2))
        [r=s.r,a=s.a,f=s.wat], XF[r,f,a] == alpha_water_WAT[a] * (lambda_f*PWAT[r,a]/PFp[r,f,a])^sigma_wat * XWAT[r,a] / lambda_f
        [r=s.r,a=s.a], PWAT[r,a] == (sum(alpha_water[(a,f)]*(PFp[r,f,a]/lambda_f)^(1-sigma_wat) for f in s.wat))^(1/(1-sigma_wat))
        # (P-38)--(P-48) energy nests
        [r=s.r,a=s.a,v=s.v], XAely[r,a,v] == alpha_energy_top_ELY[a] * (PNRG[r,a,v]/PAely[r,a,v])^sigma_erg * XNRG[r,a,v]
        [r=s.r,a=s.a,v=s.v], XNELY[r,a,v] == alpha_energy_top_NELY[a] * (PNRG[r,a,v]/PNELY[r,a,v])^sigma_erg * XNRG[r,a,v]
        [r=s.r,a=s.a,v=s.v], PNRG[r,a,v] == (alpha_energy_top_ELY[a]*PAely[r,a,v]^(1-sigma_erg) + alpha_energy_top_NELY[a]*PNELY[r,a,v]^(1-sigma_erg))^(1/(1-sigma_erg))
        [r=s.r,a=s.a,v=s.v], XAcoa[r,a,v] == alpha_nely_COA[a] * (PNELY[r,a,v]/PAcoa[r,a,v])^sigma_nely * XNELY[r,a,v]
        [r=s.r,a=s.a,v=s.v], XOLG[r,a,v] == alpha_nely_OLG[a] * (PNELY[r,a,v]/POLG[r,a,v])^sigma_nely * XNELY[r,a,v]
        [r=s.r,a=s.a,v=s.v], PNELY[r,a,v] == (alpha_nely_COA[a]*PAcoa[r,a,v]^(1-sigma_nely) + alpha_nely_OLG[a]*POLG[r,a,v]^(1-sigma_nely))^(1/(1-sigma_nely))
        [r=s.r,a=s.a,v=s.v], XAoil[r,a,v] == alpha_olg_OIL[a] * (POLG[r,a,v]/PAoil[r,a,v])^sigma_olg * XOLG[r,a,v]
        [r=s.r,a=s.a,v=s.v], XAgas[r,a,v] == alpha_olg_GAS[a] * (POLG[r,a,v]/PAgas[r,a,v])^sigma_olg * XOLG[r,a,v]
        [r=s.r,a=s.a,v=s.v], POLG[r,a,v] == (alpha_olg_OIL[a]*PAoil[r,a,v]^(1-sigma_olg) + alpha_olg_GAS[a]*PAgas[r,a,v]^(1-sigma_olg))^(1/(1-sigma_olg))
    end)

    # (P-47)/(P-48) Armington demand for, and price of, the energy commodities.
    #
    # The document writes XA_{r,e,a} without a vintage index and with a Σ_v on
    # the right-hand side (documentation p. 20, equation P-47); the previous
    # port omitted that sum and generated one equation per (r,i,a,v), i.e. two
    # equations for every XA instance.  Footnote 11 (p. 19) states that in the
    # GAMS code the four energy carriers ('ely', 'coa', 'oil', 'gas') are extra
    # dimensions of XA^NRG; those carrier bundles are exactly the XAely/XAcoa/
    # XAoil/XAgas leaves of the P-38:P-46 nest declared above, and their price
    # PA^a_{r,e,a} is the Armington purchaser price of the matching commodity.
    # Implementing P-47/P-48 that way both removes the double counting and gives
    # PAely/PAcoa/PAgas the determining equation they previously lacked; the
    # separate XANRG/PANRG aggregate (which no equation determined) is dropped.
    carrier_q = Dict("ELY"=>XAely, "COA"=>XAcoa, "OIL"=>XAoil, "GAS"=>XAgas)
    carrier_p = Dict("ELY"=>PAely, "COA"=>PAcoa, "OIL"=>PAoil, "GAS"=>PAgas)
    for i in s.nrg
        key = _nrg_carrier_key(i)
        key === nothing && error("Energy commodity $(i) does not map to an ENVISAGE energy carrier (ely/coa/oil/gas).")
        Q = carrier_q[key]; P = carrier_p[key]
        for r in s.r, a in s.a
            @NLconstraint(m, XA[r,i,a] == sum(Q[r,a,v] for v in s.v) / lambda_ep)
            for v in s.v
                @NLconstraint(m, P[r,a,v] == PA[r,i,a] / lambda_ep)
            end
        end
    end
    # (P-48) Carriers with no matching commodity in this aggregation (e.g. no
    # crude/refined oil commodity) have an inactive node in the energy nest;
    # their price is pinned to the benchmark value 1 so the nest stays square.
    for key in ["ELY", "COA", "OIL", "GAS"]
        any(_nrg_carrier_key(i) == key for i in s.nrg) && continue
        Pk = carrier_p[key]
        for r in s.r, a in s.a, v in s.v
            @NLconstraint(m, Pk[r,a,v] == 1.0)
        end
    end
    return m
end

"""
    _nrg_carrier_key(i)

Map an ENVISAGE energy commodity label to one of the document's four energy
carriers "ELY", "COA", "OIL", "GAS" (documentation §3.2, footnote 11).
Returns `nothing` when the label does not match a carrier.
"""
function _nrg_carrier_key(i::AbstractString)
    u = uppercase(strip(String(i)))
    (occursin("ELEC", u) || u == "ELY") && return "ELY"
    (occursin("COAL", u) || u == "COA") && return "COA"
    (occursin("GAS", u)) && return "GAS"
    (occursin("OIL", u) || occursin("PETRO", u) || occursin("CRUDE", u) || occursin("REFIN", u)) && return "OIL"
    return nothing
end

function production_residuals!(res::Dict{String,Function})
    for k in 1:48
        res["P-$k"] = x -> error("Residual P-$k is implemented as a JuMP equation in production_block!; use the JuMP model residual/Jacobian for numeric evaluation.")
    end
    return res
end
