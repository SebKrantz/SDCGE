# Usage:
#   data = init_data(); build_default_large_sam!(data); balance_sam_ras!(data)
#   calibrate_from_sam!(data)
#
# Calibrates every share/scale parameter AND the complete benchmark start-value
# set from the balanced SAM, and stores both in `data.par`.  The start values go
# into `data.par[:bench]`, which `Initialization.jl` reads verbatim: there is a
# single source of truth for the benchmark, so no start value is ever set
# independently of the parameter that determines it.
#
# ── Calibration principle ────────────────────────────────────────────────────
# A CES nest with dual price  P = (Σ_j α_j P_j^(1-σ))^(1/(1-σ))  and demands
# X_j = α_j (P/P_j)^σ X  reproduces the benchmark value shares s_j = P_j X_j/(P X)
# iff
#         α_j = s_j · (P / P_j)^(1-σ)                                     (CES)
# and the analogous CET nest  P = (Σ_j β_j P_j^(1+σ))^(1/(1+σ)),
# X_j = β_j (P_j/P)^σ X  needs
#         β_j = s_j · (P / P_j)^(1+σ)                                     (CET)
# Every α/β below is built with these two formulas from SAM value shares.  When
# all prices in a nest equal the bundle price the formulas collapse to
# α_j = s_j, which is why most shares are plain cost shares.
#
# ── Benchmark price normalisation ────────────────────────────────────────────
#   PP = PA = PD = PMT = PET = PM = PVA = PKT = ... = 1,  W = R = PT = PF = 1
#   PX  = 1/(1+tau_p)      (P-7:  PP = PX (1+tau_p), so PP·XP = SAM output)
#   PND = PEp = Pfert = Pfeed = 1 + tau_Ap
#           (all intermediate bundles carry the intermediate-input tax wedge)
#
# ── Three benchmark conventions that the SAM cannot supply ───────────────────
# (1) LAND (ag-only).  F_Td_nonag / F_Ts_nonag force Td = Ts = 0 outside S[:ag],
#     so land payments of non-agricultural sectors in the SAM are re-assigned to
#     capital (they are a factor payment either way).  TSupply, chi_T and gamma_T
#     then live on S[:ag] only, consistently with F-13/F-14/F-15/F-16.
# (2) BALANCED TRADE.  E-2 (WTFd = lambda_w · WTFs) together with T-21
#     (WPM = WPE/lambda_w) makes the CIF value of imports identically equal to
#     the FOB value of exports for every good, and the model has no
#     balance-of-payments equation that could absorb a difference.  The benchmark
#     is therefore made trade-balanced good by good:
#         ES  = SAM exports (+ margin sales),
#         XMT = (1+tau_m)(1+tau_e) · ES   (imports at domestic prices),
#         lambda_w = (1+tau_m)(1+tau_e)   (units of imports per unit exported).
#     Domestic absorption then has to equal output plus the trade-tax wedge,
#     XA = XP - ES + XMT, so household/government/investment demand is scaled to
#     that level (intermediate demand and all production flows stay exactly at
#     their SAM values).  With the shipped synthetic SAM this scales final demand
#     down by about 12%: that SAM runs a trade deficit financed by a capital
#     inflow, which this model cannot represent.
# (3) SUBSISTENCE = 0.  The ELES subsistence quantities theta_k,h are set to 0
#     (the SAM carries no information on them), so D-1/D-2 reduce to
#     XH_k = mu_c_k · YC and mu_c is calibrated from benchmark consumption.
#     The direct-tax rate kappa_h is then the one remaining free parameter and is
#     solved for so that C-9 delivers exactly the benchmark investment level.

# Benchmark elasticities.  The SAM carries no elasticity information, so every
# nest uses the same value; it is written into `par` (and therefore overrides the
# ParameterTables default) so calibration and equations can never drift apart.
const LCGE_SIGMA = 0.5

function calibrate_from_sam!(data::LinkageData)
    default_sets!(data)
    if length(data.sam_accounts) == 0 || size(data.balanced_sam,1) == 0
        build_default_large_sam!(data)
        balance_sam_ras!(data)
    end
    M   = data.balanced_sam
    S   = data.sets
    i = S[:i]; v = S[:v]; h = S[:h]; l = S[:l]; f = S[:f]; k = S[:k]
    r = S[:r]; rp = S[:rp]; gz = S[:gz]
    cr = S[:cr]; lv = S[:lv]; ag = S[:ag]; ip = S[:ip]
    eset = Set(S[:e]); ftset = Set(S[:ft]); fdset = Set(S[:fd])
    agset = Set(ag); crset = Set(cr); lvset = Set(lv)
    idx = data.sam_index
    par = data.par
    nv  = max(length(v), 1)
    EPS = 1.0e-9
    sg  = LCGE_SIGMA

    hh_col = idx["HH"]; gov_col = idx["GOV"]; inv_col = idx["INV"]; row_col = idx["ROW"]
    mrg_col = idx["TRD_MRG"]

    # ── 1. Raw SAM flows ────────────────────────────────────────────────────
    IOc  = Dict{Any,Float64}()                       # IOc[(good, sector)]
    for jj in i, ii in i
        IOc[(jj,ii)] = max(M[idx["COM_"*jj], idx["ACT_"*ii]], 0.0)
    end
    uld = Dict(p => max(M[idx["LAB_UNSK"], idx["ACT_"*p]], 0.0) for p in i)
    sld = Dict(p => max(M[idx["LAB_SK"],   idx["ACT_"*p]], 0.0) for p in i)
    cap = Dict(p => max(M[idx["CAP"],      idx["ACT_"*p]], 0.0) for p in i)
    lnd = Dict(p => max(M[idx["LAND"],     idx["ACT_"*p]], 0.0) for p in i)
    nrs = Dict(p => max(M[idx["NRES"],     idx["ACT_"*p]], 0.0) for p in i)
    txo = Dict(p => max(M[idx["TAX_OUT"],  idx["ACT_"*p]], 0.0) for p in i)
    txi = Dict(p => max(M[idx["TAX_INT"],  idx["ACT_"*p]], 0.0) for p in i)

    # Convention (1): land outside S[:ag] is re-assigned to capital.
    for p in i
        if !(p in agset) && lnd[p] > 0.0
            cap[p] += lnd[p]
            lnd[p]  = 0.0
        end
    end

    interm = Dict(p => sum(IOc[(jj,p)] for jj in i) for p in i)
    X      = Dict(p => interm[p] + uld[p] + sld[p] + cap[p] + lnd[p] + nrs[p] +
                       txo[p] + txi[p] for p in i)
    for p in i; X[p] = max(X[p], EPS); end

    # ── 2. Tax rates that have a SAM account ────────────────────────────────
    # P-7: PP = PX (1+tau_p) with PP=1, so the output tax is a mark-up on the
    # net-of-tax producer price:  tau_p = TAX_OUT / (output - TAX_OUT).
    tau_p  = Dict(p => txo[p] / max(X[p] - txo[p], EPS) for p in i)
    # Intermediate-input tax: a uniform ad-valorem wedge on sector p's whole
    # intermediate bill, so PND = Pfert = Pfeed = PEp = 1 + tau_Ap.
    tau_Ap_s = Dict(p => txi[p] / max(interm[p], EPS) for p in i)
    PXv  = Dict(p => 1.0 / (1 + tau_p[p]) for p in i)
    PNDv = Dict(p => 1.0 + tau_Ap_s[p] for p in i)

    # ── 3. Production nests: which goods belong to the ND bundle ────────────
    # Crops take fertiliser through P-25/26 and energy through P-27/28,
    # livestock take feed through P-49/50 and energy through P-51/52,
    # other sectors take energy through P-67/68; the rest is the ND bundle.
    in_ndset(jj, ii) = ii in crset ? !(jj in ftset || jj in eset) :
                       ii in lvset ? !(jj in fdset || jj in eset) :
                                     !(jj in eset)
    ndq   = Dict(p => sum(IOc[(jj,p)] for jj in i if in_ndset(jj,p)) for p in i)
    enrgq = Dict(p => sum(IOc[(jj,p)] for jj in S[:e]) for p in i)
    fertq = Dict(p => (p in crset ? sum(IOc[(jj,p)] for jj in S[:ft]) : 0.0) for p in i)
    feedq = Dict(p => (p in lvset ? sum(IOc[(jj,p)] for jj in S[:fd]) : 0.0) for p in i)

    ndval = Dict(p => PNDv[p] * ndq[p] for p in i)                 # PND · ND
    vaval = Dict(p => max((X[p] - txo[p]) - ndval[p], EPS) for p in i)  # PVA · VA

    # ── 4. Trade: convention (2), balanced trade good by good ───────────────
    expv = Dict(p => max(M[idx["COM_"*p], row_col], 0.0) for p in i)
    mrgb = Dict(p => max(M[idx["COM_"*p], mrg_col], 0.0) for p in i)   # margin sales
    impv = Dict(p => max(M[row_col, idx["COM_"*p]], 0.0) for p in i)
    tarv = Dict(p => max(M[idx["TAX_IMP"], idx["COM_"*p]], 0.0) for p in i)
    mrgi = Dict(p => max(M[mrg_col, idx["COM_"*p]], 0.0) for p in i)   # margin on imports

    # Margin services sold to the international transport pool count as exports;
    # the margin embodied in each commodity's imports counts as an import (the
    # GTAP convention).  XMgr is 0 at the benchmark because zeta_t = 0 (T-23).
    ES0  = Dict(p => max(expv[p] + mrgb[p], EPS) for p in i)
    tau_m_s = Dict(p => tarv[p] / max(impv[p] + mrgi[p], EPS) for p in i)
    tau_e   = max(M[idx["TAX_EXP"], row_col], 0.0) / max(sum(values(ES0)), EPS)
    lam_w   = Dict(p => (1 + tau_m_s[p]) * (1 + tau_e) for p in i)
    XMT0 = Dict(p => lam_w[p] * ES0[p] for p in i)
    XA0  = Dict(p => X[p] - ES0[p] + XMT0[p] for p in i)
    XDd0 = Dict(p => XA0[p] - XMT0[p] for p in i)     # = XDs0 = X - ES0  (E-1)

    # ── 5. Final demand scaled to the balanced-trade absorption level ───────
    iorow = Dict(p => sum(IOc[(p,jj)] for jj in i) for p in i)   # uses of good p
    c_sam = Dict(p => max(M[idx["COM_"*p], hh_col],  0.0) for p in i)
    g_sam = Dict(p => max(M[idx["COM_"*p], gov_col], 0.0) for p in i)
    i_sam = Dict(p => max(M[idx["COM_"*p], inv_col], 0.0) for p in i)
    C0 = Dict{String,Float64}(); G0 = Dict{String,Float64}(); I0 = Dict{String,Float64}()
    n_short = 0
    for p in i
        fdtot = XA0[p] - iorow[p]
        base  = c_sam[p] + g_sam[p] + i_sam[p]
        if fdtot <= EPS || base <= EPS
            n_short += 1
            fdtot = max(fdtot, EPS)
            C0[p] = fdtot; G0[p] = EPS; I0[p] = EPS
        else
            C0[p] = fdtot * c_sam[p] / base
            G0[p] = fdtot * g_sam[p] / base
            I0[p] = fdtot * i_sam[p] / base
        end
    end
    n_short > 0 && @warn "Benchmark absorption below intermediate demand for $n_short good(s); final demand floored there."

    HH0     = max(sum(values(C0)), EPS)
    GOV0    = max(sum(values(G0)), EPS)
    INVEST0 = max(sum(values(I0)), EPS)
    GDP0    = sum(values(X))

    # ── 6. Factor incomes, tax revenue and the direct-tax closure ───────────
    delta_f = 0.05                                  # Y-6 depreciation rate
    TY0 = max(sum(lnd[p] for p in i), EPS)          # only ag has land now
    FY0 = max(sum(nrs[p] for p in i), EPS)
    KY0 = max(sum(cap[p] for p in i), EPS)
    LY0 = Dict("UnSkLab" => max(sum(uld[p] for p in i), EPS),
               "SkLab"   => max(sum(sld[p] for p in i), EPS))
    FactorInc = TY0 + FY0 + KY0 + sum(values(LY0))
    DeprY0 = delta_f * KY0
    YH0    = FactorInc - DeprY0                     # Y-5 with phi = 1, TRG = 0

    # C-1 at the benchmark: WPM = 1/(1+tau_m), sum_{r,rp} WTFd = XMT.
    TarY0 = sum(tau_m_s[p] * XMT0[p] / (1 + tau_m_s[p]) for p in i)
    # C-3 export-tax term: WPE = 1+tau_e, sum_{r,rp} WTFs = ES.
    ExpTax0 = sum(tau_e * (1 + tau_e) * ES0[p] for p in i)
    # Every other tax instrument in C-3 (tau_l, tau_t, tau_k, tau_Ac, tau_Af,
    # tau_trq_share) has no SAM account (TAX_FACT = TAX_INC = 0), so its rate is
    # 0 and it contributes nothing.
    Tother = sum(values(txo)) + sum(values(txi)) + TarY0 + ExpTax0

    # Closure: D-3 gives SAV = YC - HH0, Y-8 gives YC = YD - SAV,
    # Y-7 gives YD = (1-kappa)·YH0, C-4 gives Sg = YG - GOV0 and C-9 requires
    # FD[Inv] = INVEST0.  Eliminating YC, YD, Sg and YG leaves
    SAV0 = FactorInc + Tother - INVEST0 - HH0 - GOV0
    if SAV0 <= 0.0
        @warn "Benchmark household saving is non-positive ($SAV0); flooring at 1e-6."
        SAV0 = 1.0e-6
    end
    kappa = 1.0 - (HH0 + 2 * SAV0) / YH0
    YG0   = Tother + kappa * YH0
    Sg0   = YG0 - GOV0
    YC0   = HH0 + SAV0
    YD0   = YC0 + SAV0

    # ── 7. Per-vintage nest quantities (all prices in the nest = 1 except the
    #       tax-inclusive intermediate bundles) ───────────────────────────────
    B = Dict{Symbol,Any}()
    bKT=Dict{Any,Float64}(); bHKT=Dict{Any,Float64}(); bHKTE=Dict{Any,Float64}()
    bHKTEF=Dict{Any,Float64}(); bKTEL=Dict{Any,Float64}(); bTFD=Dict{Any,Float64}()
    bVA=Dict{Any,Float64}();  bXEp=Dict{Any,Float64}()
    for p in i
        uld_v = uld[p]/nv; sld_v = sld[p]/nv; k_v = cap[p]/nv
        nrs_v = nrs[p]/nv; lnd_v = lnd[p]/nv
        enrg_v = PNDv[p]*enrgq[p]/nv
        fert_v = PNDv[p]*fertq[p]/nv
        feed_v = PNDv[p]*feedq[p]/nv
        if p in crset
            kt = k_v + lnd_v + nrs_v; hkt = kt + sld_v; hkte = hkt + enrg_v
            hktef = hkte + fert_v;    va = hktef + uld_v
            ktel = 0.0; tfd = 0.0
        elseif p in lvset
            kt = k_v + nrs_v;         hkt = kt + sld_v; hkte = hkt + enrg_v
            ktel = hkte + uld_v;      tfd = feed_v + lnd_v; va = ktel + tfd
            hktef = 0.0
        else
            kt = k_v + nrs_v;         hkt = kt + sld_v; hkte = hkt + enrg_v
            va = hkte + uld_v;        hktef = 0.0; ktel = 0.0; tfd = 0.0
        end
        for vv in v
            bKT[(p,vv)]=kt; bHKT[(p,vv)]=hkt; bHKTE[(p,vv)]=hkte
            bHKTEF[(p,vv)]=hktef; bKTEL[(p,vv)]=ktel; bTFD[(p,vv)]=tfd
            bVA[(p,vv)]=va; bXEp[(p,vv)]=enrgq[p]/nv
        end
    end

    # ── 8. CES/CET share parameters ─────────────────────────────────────────
    alpha_nd=Dict{Any,Float64}(); alpha_va=Dict{Any,Float64}()
    alpha_l=Dict{Any,Float64}();  alpha_hktef=Dict{Any,Float64}()
    alpha_fert=Dict{Any,Float64}(); alpha_hkte=Dict{Any,Float64}()
    alpha_e=Dict{Any,Float64}();  alpha_hkt=Dict{Any,Float64}()
    alpha_h=Dict{Any,Float64}();  alpha_kt=Dict{Any,Float64}()
    alpha_k=Dict{Any,Float64}();  alpha_t=Dict{Any,Float64}(); alpha_ff=Dict{Any,Float64}()
    alpha_ktel=Dict{Any,Float64}(); alpha_tfd=Dict{Any,Float64}()
    alpha_feed=Dict{Any,Float64}(); alpha_hkte_liv=Dict{Any,Float64}()
    for p in i, vv in v
        uld_v = uld[p]/nv; sld_v = sld[p]/nv; k_v = cap[p]/nv
        nrs_v = nrs[p]/nv; lnd_v = lnd[p]/nv
        enrg_v = PNDv[p]*enrgq[p]/nv; fert_v = PNDv[p]*fertq[p]/nv
        feed_v = PNDv[p]*feedq[p]/nv
        kt=bKT[(p,vv)]; hkt=bHKT[(p,vv)]; hkte=bHKTE[(p,vv)]
        hktef=bHKTEF[(p,vv)]; ktel=bKTEL[(p,vv)]; tfd=bTFD[(p,vv)]; va=bVA[(p,vv)]

        # P-1..P-4 top nest: alpha = share · (PX/P_j)^(1-sigma_p)
        s_nd = ndval[p] / max(X[p]-txo[p], EPS)
        s_va = vaval[p] / max(X[p]-txo[p], EPS)
        alpha_nd[(p,vv)] = s_nd * (PXv[p]/PNDv[p])^(1-sg)
        alpha_va[(p,vv)] = s_va * (PXv[p]/1.0)^(1-sg)

        # capital / land / natural-resource nest (P-21..P-24, P-46..P-48, P-64..P-66)
        alpha_k[(p,vv)]  = kt > EPS ? k_v/kt   : 1.0
        alpha_ff[(p,vv)] = kt > EPS ? nrs_v/kt : 0.0
        # skilled-labour + KT nest (P-18..P-20, P-43..P-45, P-61..P-63)
        alpha_h[(p,vv)]  = hkt > EPS ? sld_v/hkt : 0.0
        alpha_kt[(p,vv)] = hkt > EPS ? kt/hkt    : 1.0
        # energy + HKT nest (P-15..P-17, P-40..P-42, P-58..P-60): PEp = PND
        s_e = hkte > EPS ? enrg_v/hkte : 0.0
        alpha_e[(p,vv)]   = s_e * (1.0/PNDv[p])^(1-sg)
        alpha_hkt[(p,vv)] = hkte > EPS ? hkt/hkte : 1.0

        if p in crset
            alpha_t[(p,vv)] = kt > EPS ? lnd_v/kt : 0.0
            s_f = hktef > EPS ? fert_v/hktef : 0.0
            alpha_fert[(p,vv)] = s_f * (1.0/PNDv[p])^(1-sg)
            alpha_hkte[(p,vv)] = hktef > EPS ? hkte/hktef : 1.0
            alpha_l[(p,vv)]     = va > EPS ? uld_v/va  : 0.0
            alpha_hktef[(p,vv)] = va > EPS ? hktef/va  : 1.0
            alpha_ktel[(p,vv)]=0.0; alpha_tfd[(p,vv)]=0.0
            alpha_feed[(p,vv)]=0.0; alpha_hkte_liv[(p,vv)]=0.0
        elseif p in lvset
            alpha_ktel[(p,vv)] = va > EPS ? ktel/va : 1.0
            alpha_tfd[(p,vv)]  = va > EPS ? tfd/va  : 0.0
            s_fd = tfd > EPS ? feed_v/tfd : 0.0
            alpha_feed[(p,vv)] = s_fd * (1.0/PNDv[p])^(1-sg)
            alpha_t[(p,vv)]    = tfd > EPS ? lnd_v/tfd : 0.0
            alpha_l[(p,vv)]        = ktel > EPS ? uld_v/ktel : 0.0
            alpha_hkte_liv[(p,vv)] = ktel > EPS ? hkte/ktel  : 1.0
            alpha_fert[(p,vv)]=0.0; alpha_hkte[(p,vv)]=1.0; alpha_hktef[(p,vv)]=0.0
        else
            alpha_l[(p,vv)]    = va > EPS ? uld_v/va  : 0.0
            alpha_hkte[(p,vv)] = va > EPS ? hkte/va   : 1.0
            alpha_t[(p,vv)]=0.0; alpha_fert[(p,vv)]=0.0; alpha_hktef[(p,vv)]=0.0
            alpha_ktel[(p,vv)]=0.0; alpha_tfd[(p,vv)]=0.0
            alpha_feed[(p,vv)]=0.0; alpha_hkte_liv[(p,vv)]=0.0
        end
    end

    # Composition of the intermediate bundles (all shares sum to 1 within their
    # own bundle, so PND = Pfert = Pfeed = PEp = 1 + tau_Ap).
    a_nd=Dict{Any,Float64}(); alpha_ep=Dict{Any,Float64}()
    alpha_ft=Dict{Any,Float64}(); alpha_fd=Dict{Any,Float64}()
    ne = max(length(S[:e]),1); nft = max(length(S[:ft]),1); nfd = max(length(S[:fd]),1)
    # A sector may buy nothing at all from a bundle (e.g. an energy sector whose
    # only intermediate inputs are energy, so its ND bundle is empty).  The
    # bundle quantity is then 0 through the top-nest share, but its price index
    # still has to be well defined, so the composition falls back to uniform
    # shares that sum to 1 - exactly as for the energy/fertiliser/feed bundles.
    nnd = Dict(p => max(count(jj -> in_ndset(jj,p), i), 1) for p in i)
    for jj in i, ii in i
        a_nd[(jj,ii)] = !in_ndset(jj,ii) ? 0.0 :
                        (ndq[ii] > EPS ? IOc[(jj,ii)]/ndq[ii] : 1.0/nnd[ii])
        alpha_ep[(jj,ii)] = enrgq[ii] > EPS ? IOc[(jj,ii)]/enrgq[ii] : 1.0/ne
        alpha_ft[(jj,ii)] = fertq[ii] > EPS ? IOc[(jj,ii)]/fertq[ii] : 1.0/nft
        alpha_fd[(jj,ii)] = feedq[ii] > EPS ? IOc[(jj,ii)]/feedq[ii] : 1.0/nfd
    end

    # ── 9. Store parameters ─────────────────────────────────────────────────
    par[:output0] = X
    par[:intermediate0] = Dict(p => ndq[p] for p in i)     # = ND at the benchmark
    par[:value_added0]  = Dict(p => vaval[p] for p in i)   # = PVA · VA
    par[:intermediate_share] = Dict(p => ndval[p]/max(X[p]-txo[p],EPS) for p in i)
    par[:value_added_share]  = Dict(p => vaval[p]/max(X[p]-txo[p],EPS) for p in i)
    par[:AT] = Dict(p => 1.0 for p in i)

    par[:alpha_nd]=alpha_nd; par[:alpha_va]=alpha_va
    par[:alpha_l]=alpha_l;   par[:alpha_hktef]=alpha_hktef
    par[:alpha_fert]=alpha_fert; par[:alpha_hkte]=alpha_hkte
    par[:alpha_e]=alpha_e;   par[:alpha_hkt]=alpha_hkt
    par[:alpha_h]=alpha_h;   par[:alpha_kt]=alpha_kt
    par[:alpha_k]=alpha_k;   par[:alpha_t]=alpha_t; par[:alpha_ff]=alpha_ff
    par[:alpha_ktel]=alpha_ktel; par[:alpha_tfd]=alpha_tfd
    par[:alpha_feed]=alpha_feed; par[:alpha_hkte_liv]=alpha_hkte_liv
    par[:a_nd]=a_nd; par[:alpha_ep]=alpha_ep; par[:alpha_ft]=alpha_ft; par[:alpha_fd]=alpha_fd

    # Efficiency / technical-change indices are 1 in the benchmark year.
    for key in (:lambda_k, :lambda_t, :lambda_f)
        par[key] = Dict{Any,Float64}((p,vv) => 1.0 for p in i for vv in v)
    end
    for key in (:lambda_ep, :lambda_ft, :lambda_fd)
        par[key] = Dict{Any,Float64}((jj,ii) => 1.0 for jj in i for ii in i)
    end
    par[:lambda_l] = Dict{Any,Float64}((ll,p) => 1.0 for ll in l for p in i)
    par[:lambda_w] = Dict{Any,Float64}((rr,rrp,p) => lam_w[p]
                                        for rr in r for rrp in rp for p in i)

    # Elasticities: locked to the value the shares above were built with.
    for key in (:sigma_p, :sigma_v, :sigma_f, :sigma_e, :sigma_h, :sigma_k, :sigma_feed)
        par[key] = Dict{Any,Float64}((p,vv) => sg for p in i for vv in v)
    end
    for key in (:sigma_ep, :sigma_ft, :sigma_fd)
        par[key] = Dict{Any,Float64}((jj,ii) => sg for jj in i for ii in i)
    end

    # Exogenous factor supplies (also consumed by RecursiveDynamic/PolicyScenarios).
    par[:LSupply] = Dict("UnSkLab" => LY0["UnSkLab"], "SkLab" => LY0["SkLab"])
    par[:KSupply] = Dict{Any,Float64}((p,vv) => max(cap[p]/nv, EPS) for p in i for vv in v)
    par[:TSupply] = Dict(p => lnd[p] for p in i)          # 0 outside S[:ag]
    par[:FSupply] = Dict(p => max(nrs[p], EPS) for p in i)
    par[:K0]      = Dict(p => max(cap[p]/nv, EPS) for p in i)
    par[:LV0]     = Dict{Any,Float64}()
    for p in i
        par[:LV0][("UnSkLab", p)] = uld[p]
        par[:LV0][("SkLab",   p)] = sld[p]
    end
    par[:LS0] = Dict{Any,Float64}()
    for ll in l
        par[:LS0][(ll,"rural")]    = par[:LSupply][ll]/2
        par[:LS0][(ll,"urban")]    = par[:LSupply][ll]/2
        par[:LS0][(ll,"national")] = par[:LSupply][ll]
    end

    # Land: ag-only CET (F-13/F-14/F-15).
    tot_land = sum(lnd[p] for p in ag)
    par[:chi_T]   = Dict(:land => max(tot_land, EPS))
    par[:gamma_T] = Dict(p => (p in agset && tot_land > EPS) ? lnd[p]/tot_land : 0.0 for p in i)
    # Sector-specific factor (F-18/F-19) and capital CET (F-21).
    par[:chi_F]   = Dict(p => max(nrs[p], EPS) for p in i)
    tot_cap_old = sum(cap[p]/nv for p in i)
    par[:gamma_K] = Dict(p => tot_cap_old > EPS ? (cap[p]/nv)/tot_cap_old : 1.0/length(i) for p in i)

    # Tax rates.
    par[:tau_p]  = tau_p
    par[:tau_Ap] = Dict{Any,Float64}((jj,ii) => tau_Ap_s[ii] for jj in i for ii in i)
    par[:tau_m]  = Dict{Any,Float64}((rr,rrp,p) => tau_m_s[p]
                                      for rr in r for rrp in rp for p in i)
    par[:tau_e]  = Dict{Any,Float64}((rr,rrp,p) => tau_e
                                      for rr in r for rrp in rp for p in i)
    par[:kappa_h] = Dict(hh => kappa for hh in h)
    par[:chi_kappa] = 1.0

    # Armington / CET trade shares (all nest prices are 1, so shares are values).
    par[:beta_m] = Dict(p => XMT0[p]/max(XA0[p],EPS) for p in i)
    par[:beta_d] = Dict(p => XDd0[p]/max(XA0[p],EPS) for p in i)
    par[:beta_es] = Dict(p => ES0[p]/max(X[p],EPS) for p in i)
    par[:beta_xd] = Dict(p => (X[p]-ES0[p])/max(X[p],EPS) for p in i)
    par[:alpha_dc] = Dict{Any,Float64}((p,hh) => par[:beta_d][p] for p in i for hh in h)
    par[:alpha_mc] = Dict{Any,Float64}((p,hh) => par[:beta_m][p] for p in i for hh in h)
    par[:alpha_df] = Dict{Any,Float64}((p,ff) => par[:beta_d][p] for p in i for ff in f)
    par[:alpha_mf] = Dict{Any,Float64}((p,ff) => par[:beta_m][p] for p in i for ff in f)

    # Final-demand system.
    par[:theta]  = Dict{Any,Float64}((kk,hh) => 0.0 for kk in k for hh in h)   # convention (3)
    par[:mu_c]   = Dict{Any,Float64}((kk,hh) => C0[kk]/YC0 for kk in k for hh in h)
    par[:GammaC] = Dict{Any,Float64}((p,kk,hh) => (p == kk ? 1.0 : 0.0)
                                      for p in i for kk in k for hh in h)
    par[:a_f]    = Dict{Any,Float64}()
    for p in i
        par[:a_f][(p,"Gov")] = G0[p]/GOV0
        par[:a_f][(p,"Inv")] = I0[p]/INVEST0
    end
    par[:chi_gov] = GOV0/max(GDP0,EPS)

    # Macro anchors used elsewhere (RecursiveDynamic, PolicyScenarios, reports).
    par[:TY0]=TY0; par[:FY0]=FY0; par[:KY0]=KY0; par[:LY0]=LY0
    par[:GDP0]=GDP0; par[:RGDP0]=GDP0; par[:PGDP0]=1.0
    par[:INVEST0]=INVEST0; par[:GOV0]=GOV0; par[:HH0]=HH0
    par[:YH0]=Dict(hh => YH0 for hh in h)
    par[:YG0]=YG0; par[:Sg0]=Sg0
    par[:XAc0]=Dict{Any,Float64}((p,hh) => C0[p] for p in i for hh in h)
    par[:XAf0]=Dict{Any,Float64}()
    for p in i
        par[:XAf0][(p,"Gov")] = G0[p]; par[:XAf0][(p,"Inv")] = I0[p]
    end
    par[:XAp0]=IOc
    par[:XA0]=XA0

    # ── 10. Benchmark start values (single source of truth) ─────────────────
    B[:XP]=X; B[:XPv]=Dict{Any,Float64}((p,vv)=>X[p]/nv for p in i for vv in v)
    B[:ND]=ndq; B[:VA]=bVA
    B[:PX]=PXv; B[:PP]=Dict(p=>1.0 for p in i); B[:UVC]=PXv
    B[:PND]=PNDv
    B[:Pfert]=Dict(p => p in crset ? PNDv[p] : 1.0 for p in i)
    B[:Pfeed]=Dict(p => p in lvset ? PNDv[p] : 1.0 for p in i)
    B[:PEp]=PNDv
    B[:KT]=bKT; B[:HKT]=bHKT; B[:HKTE]=bHKTE; B[:HKTEF]=bHKTEF
    B[:KTEL]=bKTEL; B[:TFD]=bTFD; B[:XEp]=bXEp
    B[:fert]=Dict(p => p in crset ? fertq[p] : 0.0 for p in i)
    B[:feed]=Dict(p => p in lvset ? feedq[p] : 0.0 for p in i)
    B[:Kvd]=Dict{Any,Float64}((p,vv)=>cap[p]/nv for p in i for vv in v)
    B[:CHIv]=Dict{Any,Float64}((p,vv)=>(cap[p]/nv)/max(X[p]/nv,EPS) for p in i for vv in v)
    B[:Td]=lnd; B[:Ts]=lnd; B[:Fd]=nrs; B[:Fs]=nrs
    B[:ULD]=uld; B[:SLD]=sld
    B[:XAp]=IOc; B[:XA]=XA0; B[:XDd]=XDd0; B[:XDs]=XDd0
    B[:XMT]=XMT0; B[:ES]=ES0
    B[:C]=C0; B[:G]=G0; B[:I]=I0
    B[:TY]=TY0; B[:FY]=FY0; B[:KY]=KY0; B[:LY]=LY0
    B[:YH]=YH0; B[:YD]=YD0; B[:YC]=YC0; B[:SAV]=SAV0; B[:YSTAR]=YC0
    B[:DeprY]=DeprY0; B[:YG]=YG0; B[:Sg]=Sg0; B[:TarY]=TarY0
    B[:GDP]=GDP0; B[:InvSh]=INVEST0/max(GDP0,EPS)
    B[:HH]=HH0; B[:GOV]=GOV0; B[:INV]=INVEST0
    B[:KS]=sum(cap[p] for p in i)
    B[:KSs]=Dict(p => cap[p] for p in i)
    B[:TLnd]=tot_land
    B[:kappa]=kappa; B[:tau_e]=tau_e
    B[:WPE]=Dict(p => 1.0 + tau_e for p in i)
    B[:WPM]=Dict(p => (1.0 + tau_e)/lam_w[p] for p in i)
    par[:bench] = B

    return data
end
