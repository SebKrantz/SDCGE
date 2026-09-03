# Initialization helpers for the static LINKAGE MCP model.
# Sets JuMP start values from the balanced SAM and calibrated benchmark parameters.
# Variables removed from Variables.jl (dynamic, accounting, AIDS, legacy) have had
# their start-value blocks removed here.  The _safe_start_value! helpers silently
# skip any name not present in the model, so stale calls are harmless, but keeping
# the file in sync reduces noise in initialization diagnostics.

function _safe_start_value!(model, name::Symbol, index_tuple::Tuple, value)
    haskey(model, name) || return nothing
    container = model[name]
    try
        var = isempty(index_tuple) ? container : container[index_tuple...]
        set_start_value(var, max(float(value), 1.0e-9))
    catch
    end
    return nothing
end

function _safe_start_value_raw!(model, name::Symbol, index_tuple::Tuple, value)
    haskey(model, name) || return nothing
    container = model[name]
    try
        var = isempty(index_tuple) ? container : container[index_tuple...]
        set_start_value(var, float(value))
    catch
    end
    return nothing
end

const LCGE_START_EPS = 1.0e-8
# UE start = ~0 (full employment at benchmark). F_10 says UE*LS = LS - LV_total,
# which at LV = LSupply gives UE = 0. Setting UE start near 0 (not 0.05 as before)
# eliminates a residual of UE_start * LSupply ≈ 1052 for UnSkLab.
const LCGE_UE_START  = 1.0e-6
const LCGE_UE_MAX    = 0.95
const LCGE_RR_START  = 0.99

function _is_finite_number(x)
    return x isa Real && isfinite(float(x))
end

function enforce_nlp_safe_bounds_and_starts!(model; eps::Float64=LCGE_START_EPS)
    # Move nonneg lower bounds slightly inside the feasible region and repair
    # missing/non-finite start values.
    for var in all_variables(model)
        try
            if has_lower_bound(var) && lower_bound(var) == 0.0
                set_lower_bound(var, eps)
            end
        catch
        end
        sv = try start_value(var) catch; nothing end
        if sv === nothing || !(sv isa Real) || !isfinite(float(sv))
            try
                if has_lower_bound(var)
                    lb = lower_bound(var)
                    set_start_value(var, max(float(lb) + 1.0, eps))
                else
                    set_start_value(var, 0.0)
                end
            catch
            end
        elseif has_lower_bound(var) && float(sv) <= lower_bound(var)
            try
                set_start_value(var, lower_bound(var) + eps)
            catch
            end
        end
    end

    # Unemployment rates: keep starts and bounds away from 0 and 1.
    if haskey(model, :UE)
        UE = model[:UE]
        try
            for key in eachindex(UE)
                set_lower_bound(UE[key], eps)
                set_upper_bound(UE[key], LCGE_UE_MAX)
                set_start_value(UE[key], LCGE_UE_START)
            end
        catch
        end
    end

    # RR is a utilisation ratio in (0, 1]. F_24 forces RR=1 at benchmark, so start at 0.99.
    if haskey(model, :RR)
        RR = model[:RR]
        try
            for key in eachindex(RR)
                set_lower_bound(RR[key], eps)
                set_upper_bound(RR[key], 1.0)
                set_start_value(RR[key], LCGE_RR_START)
            end
        catch
        end
    end

    # GammaInv appears inside (1+GammaInv)^nstep; keep the base positive.
    if haskey(model, :GammaInv)
        try
            set_lower_bound(model[:GammaInv], -0.95)
            set_start_value(model[:GammaInv], 0.01)
        catch
        end
    end

    return model
end

function _maybe_lower_bound(var)
    try; return has_lower_bound(var) ? lower_bound(var) : missing; catch; return missing; end
end
function _maybe_upper_bound(var)
    try; return has_upper_bound(var) ? upper_bound(var) : missing; catch; return missing; end
end
function _maybe_start_value(var)
    try; return start_value(var); catch; return nothing; end
end

function initialization_diagnostics(model; max_items::Int=25)
    rows = NamedTuple[]
    n_missing = 0; n_bad = 0; n_at_or_below_lb = 0
    for var in all_variables(model)
        nm  = name(var)
        sv  = _maybe_start_value(var)
        bad = sv === nothing || !(sv isa Real) || !isfinite(float(sv))
        lb  = _maybe_lower_bound(var)
        ub  = _maybe_upper_bound(var)
        atlb= lb !== missing && sv !== nothing && sv isa Real && float(sv) <= float(lb)
        n_missing += sv === nothing ? 1 : 0
        n_bad     += bad ? 1 : 0
        n_at_or_below_lb += atlb ? 1 : 0
        if (bad || atlb) && length(rows) < max_items
            push!(rows, (variable=nm, start=sv, lower=lb, upper=ub,
                         issue=bad ? "missing_or_nonfinite_start" : "start_at_or_below_lower_bound"))
        end
    end
    return (missing_starts=n_missing, bad_starts=n_bad,
            starts_at_or_below_lower_bound=n_at_or_below_lb, examples=rows)
end

function check_initialization!(model; error_on_bad::Bool=true)
    d = initialization_diagnostics(model)
    if error_on_bad && (d.bad_starts > 0 || d.starts_at_or_below_lower_bound > 0)
        error("Bad model initialization: $(d). Call initialization_diagnostics(model) for details.")
    end
    return d
end

function initialize_from_sam!(model, data::LinkageData)
    default_sets!(data)
    S  = data.sets
    i  = S[:i]; j = S[:j]; k = S[:k]; r = S[:r]; rp = S[:rp]
    v  = S[:v]; l = S[:l]; h = S[:h]; f = S[:f]; t  = S[:t]
    gz = S[:gz]; e = S[:e]

    PAR = parameters(data)

    # ── Prices (benchmark = 1) ────────────────────────────────────────────────
    for nm in [:PX, :PP, :PND, :PA, :Pfeed, :PKTEL, :PTFD, :PT, :NPT, :PF,
               :PC, :PMT, :PD, :PET, :CPI, :PGDP]
        haskey(model, nm) || continue
        obj = model[nm]
        try; for key in eachindex(obj); set_start_value(obj[key], 1.0); end; catch; end
    end
    for nm in [:PNUM, :PABS, :PTLnd, :WXMg, :WPMg, :WRR]
        _safe_start_value!(model, nm, (), 1.0)
    end

    # ── Sector-level quantities (each from SAM benchmark) ─────────────────────
    cr_set = data.sets[:cr]; lv_set = data.sets[:lv]; ag_set = data.sets[:ag]
    nv = max(length(v), 1)
    for ii in i
        x0  = get(PAR[:output0],       ii, 1.0)
        nd0 = get(PAR[:intermediate0], ii, 1.0)
        va0 = get(PAR[:value_added0],  ii, 1.0)
        k0  = max(get(PAR[:K0], ii, 1.0), 1.0e-9)

        _safe_start_value!(model, :XP,  (ii,), x0)
        # XA = domestic Armington demand from SAM (excludes exports).
        xa0 = max(get(get(PAR, :XA0, Dict()), ii, x0 * 0.92), 1.0e-9)
        _safe_start_value!(model, :XA,  (ii,), xa0)
        # XDs/ES ≈ CET split of (XP - XMgr) from beta_xd/beta_es (calibrated from
        # the SAM's domestic-vs-export commodity split; T-14/T-15 in Trade.jl).
        # A hardcoded generic 0.90/0.05 split ignored the calibrated shares and
        # was the dominant source of the T_14/T_15/T_16 residuals at start.
        xmgr0 = x0 * 0.02
        beta_xd_val = get(get(PAR, :beta_xd, Dict()), ii, 0.95)
        beta_es_val = get(get(PAR, :beta_es, Dict()), ii, 0.05)
        _safe_start_value!(model, :XDs, (ii,), max(beta_xd_val * (x0 - xmgr0), 1.0e-9))
        # XDd ≈ domestic share of XA from beta_d (calibrated).
        beta_d_val = get(get(PAR, :beta_d, Dict()), ii, 0.92)
        beta_m_val = get(get(PAR, :beta_m, Dict()), ii, 0.08)
        _safe_start_value!(model, :XDd, (ii,), max(beta_d_val * xa0, 1.0e-9))
        _safe_start_value!(model, :XMT, (ii,), max(beta_m_val * xa0, 1.0e-9))
        _safe_start_value!(model, :ES,  (ii,), max(beta_es_val * (x0 - xmgr0), 1.0e-9))
        _safe_start_value!(model, :ND,  (ii,), nd0)
        _safe_start_value!(model, :UVC, (ii,), 1.0)
        _safe_start_value!(model, :AC,  (ii,), 1.0)
        _safe_start_value!(model, :Nfirm, (ii,), 1.0)
        # At benchmark: PX = AC (unit cost), so PROFIT = XP*(PX-AC) = 0.
        _safe_start_value!(model, :PROFIT,(ii,), 1.0e-9)
        # Labor demand by skill: unskilled ≈ 0.20*output, skilled ≈ 0.08*output (SAM shares).
        _safe_start_value!(model, :ULD, (ii,), max(0.20*x0, 1.0e-9))
        _safe_start_value!(model, :SLD, (ii,), max(0.08*x0, 1.0e-9))
        # Fertilizer / feed: only relevant for crop / livestock sectors (stubbed to 0 elsewhere).
        _safe_start_value!(model, :fert, (ii,), ii in cr_set ? max(va0 * 0.1, 1.0e-9) : 1.0e-9)
        _safe_start_value!(model, :feed, (ii,), ii in lv_set ? max(va0 * 0.1, 1.0e-9) : 1.0e-9)
        # Land / specific factor: Td=Ts and Fd=Fs at equilibrium (full calibrated supply).
        _safe_start_value!(model, :Td,  (ii,), max(get(PAR[:TSupply], ii, 1.0), 1.0e-9))
        _safe_start_value!(model, :Fd,  (ii,), max(get(PAR[:FSupply], ii, 1.0), 1.0e-9))
        _safe_start_value!(model, :Fs,  (ii,), max(get(PAR[:FSupply], ii, 1.0), 1.0e-9))
        _safe_start_value!(model, :Ts,  (ii,), max(get(PAR[:TSupply], ii, 1.0), 1.0e-9))
        # K0 is the full capital stock per sector (from SAM CAP row).
        _safe_start_value!(model, :K0,  (ii,), k0)
        _safe_start_value!(model, :KF_d,(ii,), 0.0)
        # GOV/INV demand per commodity from SAM (XAf0 already covers fine grain).
        _safe_start_value!(model, :GOVDEM, (ii,), max(get(get(PAR, :XAf0, Dict()), (ii,"Gov"), 0.05*x0), 1.0e-9))
        _safe_start_value!(model, :INVDEM, (ii,), max(get(get(PAR, :XAf0, Dict()), (ii,"Inv"), 0.10*x0), 1.0e-9))
        _safe_start_value!(model, :XMgr, (ii,), max(x0 * 0.02, 1.0e-9))

        # Per-vintage quantities: bottom-up benchmark from SAM factor payments.
        # Stub equations force KTEL/TFD = 0 for non-livestock, HKTEF/fert = 0 for
        # non-crops, feed = 0 for non-livestock — initialize those to 1e-9.
        xp_per_v = x0 / nv
        va_per_v = va0 / nv
        nres_v   = max(get(PAR[:FSupply], ii, 0.0), 0.0) / nv
        land_v   = (ii in ag_set ? max(get(PAR[:TSupply], ii, 0.0), 0.0) : 0.0) / nv
        ksk_v    = 0.08 * xp_per_v
        # Use SAM-calibrated fert / energy use per sector when available.
        fert_total = max(get(get(PAR, :fert0, Dict()), ii, 0.10 * va0), 0.0)
        enrg_total = max(get(get(PAR, :enrg0, Dict()), ii, 0.05 * va0), 0.0)
        fert_v = ii in cr_set ? fert_total / nv : 0.0
        feed_v = ii in lv_set ? 0.10 * va_per_v : 0.0
        xep_v  = enrg_total / nv
        for vv in v
            kvd_val = max(get(PAR[:KSupply], (ii,vv), k0), 1.0e-9)
            # Capital-land-NR nest (KT) at benchmark = K + T + F per vintage.
            # Livestock land enters the feed nest (TFD), so exclude T from KT for lv.
            kt_val    = (ii in lv_set) ? (kvd_val + nres_v) : (kvd_val + land_v + nres_v)
            hkt_val   = kt_val + ksk_v
            hkte_val  = hkt_val + xep_v
            hktef_val = ii in cr_set ? hkte_val + fert_v : 1.0e-9     # 0 for non-crops (stub)
            ktel_val  = ii in lv_set ? hkte_val + ksk_v : 1.0e-9      # 0 for non-livestock (stub)
            tfd_val   = ii in lv_set ? land_v + feed_v  : 1.0e-9      # 0 for non-livestock (stub)
            _safe_start_value!(model, :XPv,   (ii,vv), max(xp_per_v, 1.0e-9))
            _safe_start_value!(model, :VA,    (ii,vv), max(va_per_v, 1.0e-9))
            _safe_start_value!(model, :UVCv,  (ii,vv), 1.0)
            _safe_start_value!(model, :Kvd,   (ii,vv), kvd_val)
            _safe_start_value!(model, :KT,    (ii,vv), max(kt_val, 1.0e-9))
            _safe_start_value!(model, :HKT,   (ii,vv), max(hkt_val, 1.0e-9))
            _safe_start_value!(model, :HKTE,  (ii,vv), max(hkte_val, 1.0e-9))
            _safe_start_value!(model, :HKTEF, (ii,vv), hktef_val)
            _safe_start_value!(model, :KTEL,  (ii,vv), ktel_val)
            _safe_start_value!(model, :TFD,   (ii,vv), tfd_val)
            _safe_start_value!(model, :CHIv,  (ii,vv), max(kvd_val / max(xp_per_v, 1.0e-9), 1.0e-6))
            for nm in [:PVA,:PHKTEF,:PHKTE,:PEp,:PHKT,:PKT,:PKTEL,:PTFD,:R,:NR]
                _safe_start_value!(model, nm, (ii,vv), 1.0)
            end
            _safe_start_value!(model, :XEp, (ii,vv), max(xep_v, 1.0e-9))
            _safe_start_value!(model, :RR,  (ii,vv), 0.99)
        end
        # Labor demand per (skill, sector) from SAM labor-payment cells (LV0).
        # Y_3 holds at start when LV = SAM labor cell, NW=1, LF_d=0, Nfirm=1.
        for ll in l
            lv_val = max(get(get(PAR, :LV0, Dict()), (ll, ii),
                             ll == "UnSkLab" ? 0.20 * x0 : 0.08 * x0), 1.0e-9)
            _safe_start_value!(model, :LF_d, (ll,ii), 0.0)
            _safe_start_value!(model, :LV,   (ll,ii), lv_val)
            _safe_start_value!(model, :W,    (ll,ii), 1.0)
            _safe_start_value!(model, :NW,   (ll,ii), 1.0)
        end
    end

    # ── Intermediate demand (from SAM input-output cells) ─────────────────────
    for jj in j, ii in i
        xap0 = max(get(get(PAR, :XAp0, Dict()), (jj,ii),
                       get(PAR[:intermediate0], jj, 1.0) / max(length(i),1)), 1.0e-9)
        _safe_start_value!(model, :XAp, (jj,ii), xap0)
        _safe_start_value!(model, :PAp, (jj,ii), 1.0)
    end

    # ── Consumer demand & income (anchored to SAM-calibrated values) ──────────
    # All quantity starts come from the balanced SAM via PAR[:*0] keys so the
    # income block (Y_1..Y_8) and savings-investment closure (C_9) start at the
    # benchmark with near-zero residuals.
    total_output = max(get(PAR, :GDP0, sum(get(PAR[:output0], ii, 0.0) for ii in i)), 1.0)
    TY_start = get(PAR, :TY0, sum(get(PAR[:TSupply], ii, 0.0) for ii in i))
    FY_start = get(PAR, :FY0, sum(get(PAR[:FSupply], ii, 0.0) for ii in i))
    KY_start = get(PAR, :KY0, sum(get(PAR[:KSupply], (ii,vv), 0.0) for ii in i for vv in v))
    LY_total = sum(get(PAR[:LSupply], ll, 0.0) for ll in l)
    INV_start = get(PAR, :INVEST0, 0.20 * total_output)
    GOV_start = get(PAR, :GOV0,    0.20 * total_output)
    HH_value  = get(PAR, :HH0,     0.50 * total_output)
    DeprY_start = 0.05 * KY_start    # rough depreciation share (matches Y_6 with delta_f≈0.05)
    # Y_5: YH = TY + FY + LY + (KY - DeprY) + transfers. With phi=1 and transfers=0.
    YH_start = max(TY_start + FY_start + LY_total + KY_start - DeprY_start, 1.0)
    # C_9: PFD[Inv]*FD[Inv] = sum(SAV+DeprY) + Sg + Sf  →  SAV = INV − DeprY − Sg.
    Sg_init   = get(PAR, :Sg0, get(PAR, :YG0, 0.0) - GOV_start)
    SAV_start = max(INV_start - DeprY_start - Sg_init, 1.0)
    YC_start  = max(YH_start - SAV_start, 1.0)
    min_bundle = sum(get(PAR[:PopH], hh, 1.0) * get(PAR[:theta], (kk,hh), 0.0)
                     for kk in k for hh in h)
    YSTAR_start = max(YC_start - min_bundle, 1.0)
    # XH from ELES formula (PC=1 at benchmark) so D_2/D_3 hold at start:
    # XH[k,h] = popH·θ + μ_c · YSTAR
    for kk in k, hh in h
        xh_val = max(get(PAR[:PopH], hh, 1.0) * get(PAR[:theta], (kk,hh), 0.0) +
                     get(PAR[:mu_c], (kk,hh), 0.0) * YSTAR_start, 1.0e-6)
        _safe_start_value!(model, :XH, (kk,hh), xh_val)
    end
    for hh in h
        _safe_start_value!(model, :YH,    (hh,), YH_start)
        _safe_start_value!(model, :DeprY, (hh,), DeprY_start)
        _safe_start_value!(model, :YD,    (hh,), YH_start)
        _safe_start_value!(model, :YC,    (hh,), YC_start)
        _safe_start_value!(model, :SAV,   (hh,), SAV_start)
        _safe_start_value!(model, :YSTAR, (hh,), YSTAR_start)
        _safe_start_value!(model, :CPIH,  (hh,), 1.0)
        for ii in i
            # XAc start = household consumption of good ii from SAM
            xac0 = max(get(get(PAR, :XAc0, Dict()), (ii,hh), HH_value/length(i)), 1.0e-6)
            _safe_start_value!(model, :XAc,  (ii,hh), xac0)
            _safe_start_value!(model, :PAc,  (ii,hh), 1.0)
            _safe_start_value!(model, :XDc,  (ii,),   0.9 * xac0)
            _safe_start_value!(model, :XMc,  (ii,),   0.1 * xac0)
        end
    end
    # Factor-income aggregates referenced in Y_1..Y_4 (from SAM).
    _safe_start_value!(model, :TY, (), max(TY_start, 1.0))
    _safe_start_value!(model, :FY, (), max(FY_start, 1.0))
    _safe_start_value!(model, :KY, (), max(KY_start, 1.0))
    for ll in l
        _safe_start_value!(model, :LY, (ll,),
            max(get(get(PAR, :LY0, Dict()), ll, get(PAR[:LSupply], ll, 1.0)), 1.0))
    end

    # ── Other final demand (Gov, Inv) from SAM final-demand columns ───────────
    fd_start = Dict("Gov" => GOV_start, "Inv" => INV_start)
    for ff in f
        fdv = max(get(fd_start, ff, 0.10 * total_output), 1.0)
        _safe_start_value!(model, :FD,  (ff,), fdv)
        _safe_start_value!(model, :PFD, (ff,), 1.0)
        for ii in i
            # Per-commodity demand from SAM column XAf0[(i, "Gov")] / XAf0[(i, "Inv")]
            xafv = max(get(get(PAR, :XAf0, Dict()), (ii,ff),
                           get(PAR[:a_f], (ii,ff), 1.0/length(i)) * fdv), 1.0e-6)
            _safe_start_value!(model, :XAf, (ii,ff), xafv)
            _safe_start_value!(model, :XDf, (ii,ff), 0.9 * xafv)
            _safe_start_value!(model, :XMf, (ii,ff), 0.1 * xafv)
        end
    end

    # ── Labor market stocks (LS calibrated from SAM via LS0 split by zone) ────
    for ll in l
        _safe_start_value!(model, :LY,   (ll,), get(PAR[:LSupply], ll, 1.0))
        _safe_start_value_raw!(model, :MIGR, (ll,), 0.0)
        for gg in gz
            # LS[ll, "rural"/"urban"] = LSupply/2, LS[ll, "national"] = LSupply
            lsval = max(get(PAR[:LS0], (ll,gg),
                            gg == "national" ? get(PAR[:LSupply], ll, 1.0) :
                                               get(PAR[:LSupply], ll, 1.0) / 2), 1.0e-9)
            _safe_start_value!(model, :LS,   (ll,gg), lsval)
            _safe_start_value!(model, :AVGW, (ll,gg), 1.0)
            _safe_start_value!(model, :TW,   (ll,gg), 1.0)
            _safe_start_value!(model, :WMIN, (ll,gg), 1.0)
            # F_10 demands UE ≈ 0 at full employment; start very small.
            _safe_start_value!(model, :UE,   (ll,gg), 1.0e-3)
        end
    end

    # ── Bilateral trade ───────────────────────────────────────────────────────
    # All trade prices stay at the benchmark numeraire of 1.0 (tau_out/tau_in/
    # zeta_t/lambda_w default to 0/0/0/1, so T-20/T-21/T-25 hold with no wedge;
    # tau_m/tau_e are SAM-calibrated and generally nonzero, so T-6/T-8/T-10/
    # T-22 retain a small residual from that tariff wedge -- see report).  With
    # prices equal within every nest, each CES/CET share equation collapses to
    # "quantity = share * upstream aggregate" (price-ratio terms = 1^elasticity
    # = 1), so bilateral quantities must be built top-down from the already-set
    # aggregate starts (XMT, ES) using the beta_1/beta_2/beta_w/beta_z shares --
    # not left at a flat 1.0 regardless of XMT/ES's scale.  Previously this was
    # the dominant source of the T-5..T-27 residuals at start (e.g. T_5[R1,P075]
    # off by two orders of magnitude, per the Diagnostics residual audit).
    for ii in i
        xmt0 = max(start_value(model[:XMT][ii]), 1.0e-9)
        es0  = max(start_value(model[:ES][ii]),  1.0e-9)

        # T-5/T-7: XM1[rr,ii] = beta_1[(rr,ii)]*XMT[ii]; XM2[rr,ii] = beta_2[(rr,ii)]*XM1[rr,ii].
        xm1 = Dict(rr => get(get(PAR, :beta_1, Dict()), (rr,ii), 1.0/length(r)) * xmt0 for rr in r)
        xm2 = Dict(rr => get(get(PAR, :beta_2, Dict()), (rr,ii), 1.0/length(r)) * xm1[rr] for rr in r)
        for rr in r
            _safe_start_value!(model, :XM1, (rr,ii), xm1[rr])
            _safe_start_value!(model, :PM1, (rr,ii), 1.0)
            _safe_start_value!(model, :XM2, (rr,ii), xm2[rr])
            _safe_start_value!(model, :PM2, (rr,ii), 1.0)
        end

        for rr in r, rrp in rp
            # T-9: WTFd[rr,rrp,ii] = beta_w[(rr,rrp,ii)]*XM2[rrp,ii] (source region rrp's pool).
            wtfd_val = get(get(PAR, :beta_w, Dict()), (rr,rrp,ii), 1.0/length(r)) * xm2[rrp]
            _safe_start_value!(model, :WTFd, (rr,rrp,ii), wtfd_val)
            # T-11/T_WTFin/T-13: TRQ non-binding at benchmark -> WTFin=WTFq=WTFd, WTFout≈0.
            _safe_start_value!(model, :WTFin,  (rr,rrp,ii), wtfd_val)
            _safe_start_value!(model, :WTFq,   (rr,rrp,ii), wtfd_val)
            _safe_start_value!(model, :WTFout, (rr,rrp,ii), 0.0)
            # T-12: TauPR = tau_out - tau_in (both default to 0.0).
            tauin  = get(get(PAR, :tau_in,  Dict()), (rr,rrp,ii), 0.0)
            tauout = get(get(PAR, :tau_out, Dict()), (rr,rrp,ii), 0.0)
            _safe_start_value!(model, :TauPR, (rr,rrp,ii), max(tauout - tauin, 0.0))
            # T-18: WTFs[rr,rrp,ii] = beta_z[(rr,rrp,ii)]*ES[ii] (beta_z normalized
            # over the full (rr,rrp) grid so it sums to 1 -- see ParameterTables.jl).
            beta_z_val = get(get(PAR, :beta_z, Dict()), (rr,rrp,ii), 1.0/(length(r)*length(rp)))
            _safe_start_value!(model, :WTFs, (rr,rrp,ii), beta_z_val * es0)
            for nm in [:PM,:PE,:WPE,:WPM]
                _safe_start_value!(model, nm, (rr,rrp,ii), 1.0)
            end
        end
    end

    # ── Trade margin ─────────────────────────────────────────────────────────
    for rr in r
        _safe_start_value!(model, :AXMg, (rr,), 1.0)
        _safe_start_value!(model, :APMg, (rr,), 1.0)
    end
    _safe_start_value!(model, :WXMg, (), 1.0)
    _safe_start_value!(model, :WPMg, (), 1.0)

    # ── Land market ───────────────────────────────────────────────────────────
    # F-13 (Factors.jl) says TLnd = chi_T[:land] * (PTLnd/PABS)^eta_T, and
    # chi_T[:land] is calibrated (Calibration.jl) as sum(TSupply) over ALL
    # sectors i, not just :ag (TSupply is itself defined, floored at 1e-9, for
    # every sector). Summing only over :ag here undercounted the non-ag floor
    # contributions relative to chi_T's own calibration domain, producing a
    # large F_13_unbounded_land residual at start; sum over the same domain
    # chi_T was calibrated over.
    _safe_start_value!(model, :TLnd,  (), max(sum(get(PAR[:TSupply], ii, 1.0) for ii in i), 1.0e-9))
    _safe_start_value!(model, :PTLnd, (), 1.0)
    for ii in i
        _safe_start_value!(model, :PT,  (ii,), 1.0)
        _safe_start_value!(model, :NPT, (ii,), 1.0)
        _safe_start_value!(model, :Ts,  (ii,), max(get(PAR[:TSupply], ii, 1.0), 1.0e-9))
    end

    # ── Capital aggregates (SAM-calibrated; static identities) ────────────────
    # K0[i]:    OLD-vintage capital stock from SAM = M[CAP, ACT_i] / |v| (for F_30).
    # KSupply[(i,v)]: capital supply per vintage = M[CAP, ACT_i] / |v|.
    # Kvd[(i,v)]:   capital demand per vintage = KSupply at benchmark.
    # KSs[i]:   F_22 says KSs = sum_v Kvd = sum_v KSupply (full per-sector capital).
    # KS:       F_25 says KS  = sum_iv Kvd  = sum_iv KSupply (total capital).
    # KActual:  F_32 makes KActual = KS in the static model.
    KS_start = max(sum(get(PAR[:KSupply], (ii,vv), 0.0) for ii in i for vv in v), 1.0e-9)
    _safe_start_value!(model, :KS,       (), KS_start)
    _safe_start_value!(model, :TR,       (), 1.0)
    _safe_start_value!(model, :KActual,  (), KS_start)
    _safe_start_value!(model, :KNorm,    (), 1.0)
    _safe_start_value!(model, :FDInv,    (), INV_start)
    for ii in i
        kii_total = sum(get(PAR[:KSupply], (ii,vv), 0.0) for vv in v)   # sum across vintages
        kii_old   = max(get(PAR[:K0], ii, get(PAR[:KSupply], (ii,"Old"), 1.0)), 1.0e-9)
        _safe_start_value!(model, :KSs, (ii,), max(kii_total, 1.0e-9))
        _safe_start_value!(model, :K0,  (ii,), kii_old)
    end

    # ── Macro / closure (all from SAM-calibrated values) ──────────────────────
    # TY, FY, KY, LY are set in the consumer-demand block above; do not override.
    GDP_start = max(total_output, 1.0)
    YG_start  = max(get(PAR, :YG0, 0.07 * total_output), 1.0)   # SAM gov revenue
    Sg_start  = get(PAR, :Sg0, YG_start - GOV_start)             # gov saving (may be negative)
    for nm in [:PABS,:WRR,:PNUM,:InvSh]
        _safe_start_value!(model, nm, (), 1.0)
    end
    _safe_start_value!(model, :FDInv,  (), INV_start)            # F_31: FDInv = FD[Inv]
    _safe_start_value!(model, :GDPMPr, (), GDP_start)
    _safe_start_value!(model, :YG,     (), YG_start)
    # Tariff revenue from SAM: sum(WPM · τ_m · WTFd) at PP=1, WTFd=1.
    tariff_est = sum(get(PAR[:tau_m], (rr,rrp,ii), 0.0) for rr in r for rrp in rp for ii in i)
    _safe_start_value!(model, :TarY,   (), max(tariff_est, 1.0))
    _safe_start_value!(model, :RTarY,  (), max(tariff_est, 1.0))
    _safe_start_value_raw!(model, :GammaInv, (), 0.0)
    _safe_start_value_raw!(model, :Sg,    (), Sg_start)
    _safe_start_value_raw!(model, :RSg,   (), Sg_start)
    for rr in r
        _safe_start_value_raw!(model, :Sf, (rr,), 0.0)
        _safe_start_value!(model,  :GDP,  (rr,), GDP_start)
        _safe_start_value!(model,  :RGDP, (rr,), GDP_start)
        _safe_start_value!(model,  :CPI,  (rr,), 1.0)
        _safe_start_value!(model,  :PGDP, (rr,), 1.0)
    end

    # ── Zone price level PS ───────────────────────────────────────────────────
    for gg in gz
        _safe_start_value!(model, :PS, (gg,), 1.0)
    end
    _safe_start_value!(model, :PABS, (), 1.0)

    enforce_nlp_safe_bounds_and_starts!(model)
    return model
end
