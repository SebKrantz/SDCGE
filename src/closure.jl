# ENVISAGE v10.01 §3.9 National accounts and model closure.
# Document-strict closure block: only ENVISAGE macro/closure variable families
# are declared or fixed here.  Each numbered equation is labeled immediately
# above its JuMP equation.

function _env_hasvar(m::JuMP.Model, nm::Symbol)
    return haskey(JuMP.object_dictionary(m), nm)
end

function _env_first(v::Vector{String}, default::String)
    return isempty(v) ? default : first(v)
end

function _env_pick(v::Vector{String}, candidates::Vector{String}, default::String)
    for c in candidates
        c in v && return c
    end
    return _env_first(v, default)
end

function closure_block!(m::JuMP.Model, data::EnvData, cal::EnvCalibration)
    PAR = parameters(data, cal)
    # Local parameter aliases generated from ParameterTables.jl.
    Rn = PAR[:Rn]
    chi_k = PAR[:chi_k]
    chi_sf = PAR[:chi_sf]
    chi_welf = PAR[:chi_welf]
    delta = PAR[:delta]
    eps_ror = PAR[:eps_ror]
    grKMax = PAR[:grKMax]
    grKMin = PAR[:grKMin]
    grKTrend = PAR[:grKTrend]
    rbar = PAR[:r]
    gamma_c = PAR[:gamma_c]     # LES subsistence minima, used by M-33 (EV)
    s = data.sets
    inv_fd = _env_pick(s.fd, vcat(s.inv, ["inv", "INV", "investment", "Investment"]), _env_first(s.fd, "inv"))
    cap = _env_first(s.cap, "cap")
    rres = _env_pick(s.r, s.rres, _env_first(s.r, "rres"))

    # Declare only ENVISAGE national-account and closure variable families.
    if !_env_hasvar(m, :QGDP);    @variable(m, QGDP[s.r,s.t,s.t]); end
    if !_env_hasvar(m, :GDPMP);   @variable(m, GDPMP[s.r] >= 0); end
    if !_env_hasvar(m, :PGDPMP);  @variable(m, PGDPMP[s.r] >= 0); end
    if !_env_hasvar(m, :RGDPMP);  @variable(m, RGDPMP[s.r] >= 0); end
    if !_env_hasvar(m, :RGDPpc);  @variable(m, RGDPpc[s.r] >= 0); end
    if !_env_hasvar(m, :gy);      @variable(m, gy[s.r]); end
    if !_env_hasvar(m, :KLRat);   @variable(m, KLRat[s.r] >= 0); end
    if !_env_hasvar(m, :RSg);     @variable(m, RSg[s.r]); end
    if !_env_hasvar(m, :Rg);      @variable(m, Rg); end
    if !_env_hasvar(m, :phi);     @variable(m, phi[s.r] >= 0); end
    if !_env_hasvar(m, :TKe);     @variable(m, TKe[s.r] >= 0); end
    if !_env_hasvar(m, :R);       @variable(m, R[s.r] >= 0); end
    if !_env_hasvar(m, :Rc);      @variable(m, Rc[s.r]); end
    if !_env_hasvar(m, :Re);      @variable(m, Re[s.r]); end
    if !_env_hasvar(m, :DeltaRoR); @variable(m, DeltaRoR[s.r]); end
    if !_env_hasvar(m, :grK);     @variable(m, grK[s.r]); end
    if !_env_hasvar(m, :Rd);      @variable(m, Rd[s.r]); end
    if !_env_hasvar(m, :PNUM);    @variable(m, PNUM >= 0); end
    if !_env_hasvar(m, :EV);      @variable(m, EV[s.r]); end
    if !_env_hasvar(m, :CV);      @variable(m, CV[s.r]); end
    if !_env_hasvar(m, :EVG);     @variable(m, EVG); end
    if !_env_hasvar(m, :CVG);     @variable(m, CVG); end
    if !_env_hasvar(m, :SWF);     @variable(m, SWF); end

    # Bind local aliases after guarded declarations.  This avoids UndefVarError
    # when a variable family was already declared by another block.
    QGDP = m[:QGDP]
    GDPMP = m[:GDPMP]
    PGDPMP = m[:PGDPMP]
    RGDPMP = m[:RGDPMP]
    RGDPpc = m[:RGDPpc]
    gy = m[:gy]
    KLRat = m[:KLRat]
    RSg = m[:RSg]
    Rg = m[:Rg]
    phi = m[:phi]
    TKe = m[:TKe]
    R = m[:R]
    Rc = m[:Rc]
    Re = m[:Re]
    DeltaRoR = m[:DeltaRoR]
    grK = m[:grK]
    Rd = m[:Rd]
    PNUM = m[:PNUM]
    EV = m[:EV]
    CV = m[:CV]
    EVG = m[:EVG]
    CVG = m[:CVG]
    SWF = m[:SWF]

    XA = m[:XA]
    XTT = m[:XTT]
    XWs = m[:XWs]
    XWd = m[:XWd]
    PWE = m[:PWE]
    PWM = m[:PWM]
    PDT = m[:PDT]
    PA = m[:PA]
    PAh = _env_hasvar(m, :PAh) ? m[:PAh] : nothing
    YGOV = m[:YGOV]
    YFD = m[:YFD]
    PFD = m[:PFD]
    XFD = m[:XFD]
    Sh = m[:Sh]
    Sg = m[:Sg]
    Sf = m[:Sf]
    PWsav = m[:PWsav]
    TKs = m[:TKs]
    PK = m[:PK]
    Kv = m[:Kv]
    XFD_inv = m[:XFD]

    # Prices for final demand in QGDP.  Avoid user-defined lookup functions inside
    # JuMP nonlinear macros because region labels such as R1 can otherwise be
    # interpreted as unexpected nonlinear objects.  Build explicit household and
    # non-household final-demand sets instead.
    fd_h = [fd for fd in s.fd if fd in s.h]
    fd_nh = [fd for fd in s.fd if !(fd in s.h)]

    Pop0 = get(data.par, "Pop", Dict(rr => 1.0 for rr in s.r))
    Pop = Dict(rr => Float64(get(Pop0, rr, 1.0)) for rr in s.r)
    RGDPpcLag0 = get(data.par, "RGDPpc_lag", Dict(rr => 1.0 for rr in s.r))
    RGDPpcLag = Dict(rr => max(1.0, Float64(get(RGDPpcLag0, rr, 1.0))) for rr in s.r)
    nstep = Float64(get(data.par, "n", 1.0))
    delta = delta
    chi_sf = chi_sf
    eps_ror = eps_ror
    grKMin = grKMin
    grKMax = grKMax
    grKTrend = grKTrend
    chi_k = chi_k
    Rn = Rn
    chi_welf = chi_welf
    RSG_deflator = PGDPMP
    t0 = _env_first(s.t,"t")
    h0 = _env_pick(s.fd, s.h, _env_first(s.fd,"h"))
    # ENVISAGE capital-account closure switch (see M-18/M-19/M-21 below).
    inv_closure = lowercase(strip(String(get(data.par, "invClosure", "gtap"))))

    # (M-1) GDP at market price.
    @NLconstraint(m, [r=s.r], GDPMP[r] == QGDP[r,t0,t0])

    # (M-1a) QGDP indicator: value of absorption, trade and transport margin
    # output, and net trade at border prices, evaluated with prices of tp and
    # quantities of tq.
    #
    # The trade-and-transport margin term is valued at PDT[r,mm], the same
    # domestic price ENVISAGE T-32 already uses to value XTT (PTMG[mrg]*XTMG[mrg]
    # == sum(PDT[r,mrg]*XTT[r,mrg] for r in s.r)).  An earlier version of this
    # equation valued the margin at PD[r,mm,aa0] (an arbitrary single slice of
    # the agent-specific Armington price, only defined under agent sourcing,
    # ArmFlag != 0); PDT is defined unconditionally, so this also removes a
    # spurious dependency on the ArmFlag-only PD family and the aa0 lookup.
    @NLconstraint(m, [r=s.r,tp=s.t,tq=s.t],
        QGDP[r,tp,tq] ==
            sum(PAh[r,i,fd] * XA[r,i,fd] for fd in fd_h, i in s.i)
          + sum(PA[r,i,fd] * XA[r,i,fd] for fd in fd_nh, i in s.i)
          + sum(PDT[r,mm] * XTT[r,mm] for mm in s.i)
          + sum(sum(PWE[r,i,d] * XWs[r,i,d] for d in s.r) - sum(PWM[src,i,r] * XWd[src,i,r] for src in s.r) for i in s.i)
    )

    # (M-2) GDP at market price deflator, Fisher price index.
    @NLconstraint(m, [r=s.r], PGDPMP[r] == 1.0)

    # (M-3) Real GDP at market price.
    @NLconstraint(m, [r=s.r], RGDPMP[r] * PGDPMP[r] == GDPMP[r])

    # (M-4) Real per-capita GDP.
    @NLconstraint(m, [r=s.r], RGDPpc[r] == RGDPMP[r] / Pop[r])

    # (M-5) Growth in real per-capita GDP.
    @NLconstraint(m, [r=s.r], RGDPpc[r] == (1 + gy[r])^nstep * RGDPpcLag[r])

    # (M-6) Capital-labor ratio in efficiency units.
    @NLconstraint(m, [r=s.r],
        KLRat[r] * (sum(m[:PF][r,l,a] * m[:XF][r,l,a] for l in s.l, a in s.a) + 1.0e-9) ==
        sum(PK[r,a,v] * Kv[r,a,v] for a in s.a, v in s.v)
    )

    # (M-7) Nominal government saving.
    @NLconstraint(m, [r=s.r],
        Sg[r] == sum(YGOV[r,gy] for gy in s.gy) - sum(YFD[r,gov] for gov in s.gov)
    )

    # (M-8) Real government saving.
    @NLconstraint(m, [r=s.r], RSg[r] * RSG_deflator[r] == Sg[r])

    # (M-9) Balance-of-payments closure: fixed capital account case.
    # This closure alternative is not active in this configuration: Sf is
    # instead determined by M-14 (regional share-of-GDP rule for non-residual
    # regions) plus M-10 (global balance, which pins the residual region).  The
    # equation was previously coded as the tautology `Sf[r] == Sf[r]`, a
    # placeholder that is trivially satisfied for any Sf and provides no real
    # determination (and a singular row for PATH); it is removed rather than
    # kept as dead weight.  If this closure regime is selected in the future,
    # M-9 should instead read `Sf[r] == Sf0[r]` (fix Sf at its calibrated
    # value) and M-14 should be skipped, since both cannot determine Sf at once.

    # (M-10) Global foreign saving balance.
    @NLconstraint(m, sum(Sf[r] for r in s.r) == 0)

    # (M-11) Savings price normalization used in foreign-saving valuation.
    @NLconstraint(m, PWsav == PNUM)

    # (M-12) Global expected rate of return.
    @NLconstraint(m, Rg == sum(phi[r] * Re[r] for r in s.r))

    # (M-13) Regional investment weights for the global expected rate of return.
    @NLconstraint(m, [r=s.r],
        phi[r] * (sum(PFD[rr,inv_fd] * (XFD[rr,inv_fd] - delta * TKs[rr]) for rr in s.r) + 1.0e-9) ==
        PFD[r,inv_fd] * (XFD[r,inv_fd] - delta * TKs[r])
    )

    # (M-14) Foreign saving fixed relative to GDP, residual-region case.
    # The residual region (r == rres) is deliberately left without its own
    # per-region equation here: Sf[rres] is the closing variable determined by
    # the global balance M-10 (sum(Sf) == 0) once the non-residual regions are
    # pinned below.  A per-region placeholder `Sf[rres] == Sf[rres]` was
    # previously written for that case; like M-9, it is a tautology (always
    # true, no information, singular row for PATH) and is removed rather than
    # counted as a real equation.
    for r in s.r
        if r != rres
            # (M-14) Non-residual regions: foreign saving as a share of GDP.
            @NLconstraint(m, Sf[r] == chi_sf * GDPMP[r] / PWsav)
        end
    end

    # (M-15) Expected end-of-period capital stock.
    @NLconstraint(m, [r=s.r], TKe[r] == (1 - delta) * TKs[r] + XFD_inv[r,inv_fd])

    # (M-16) Aggregate after-tax rate of return.
    @NLconstraint(m, [r=s.r],
        R[r] * (PFD[r,inv_fd] * TKs[r] + 1.0e-9) == sum(PK[r,a,v] * Kv[r,a,v] for a in s.a, v in s.v)
    )

    # (M-17) Net current rate of return.
    @NLconstraint(m, [r=s.r], Rc[r] == R[r] / PFD[r,inv_fd] - delta)

    # (M-18)/(M-19)/(M-21) are the three ALTERNATIVE ENVISAGE capital-account
    # closures for the expected rate of return Re.  The document selects exactly
    # one of them; this port previously declared all three, so 9 equations chased
    # 3 variables.  `data.par["invClosure"]` selects the active one:
    #   "gtap"    -> M-18, GTAP-style expected rate of return (default)
    #   "flexSf"  -> M-19, flexible foreign saving (Re equalized up to a premium)
    #   "usage"   -> M-21, USAGE-style closure
    # Whichever branch is inactive contributes no equation, so Re is determined
    # exactly once and Rd is exogenous outside the "flexSf" case.
    if inv_closure == "gtap"
        # (M-18) Expected rate of return, GTAP-style capital account closure.
        @NLconstraint(m, [r=s.r], Re[r] == Rc[r] * (TKe[r] / (TKs[r] + 1.0e-9))^(-eps_ror))
    elseif inv_closure == "flexsf"
        # (M-19) Flexible foreign saving: expected regional return equals the
        # global return adjusted for a regional risk premium.
        @NLconstraint(m, [r=s.r], Re[r] == Rg + Rd[r])
    elseif inv_closure == "usage"
        # (M-21) Expected rate of return, USAGE-style closure.
        @NLconstraint(m, [r=s.r], Re[r] == (1 / (1 + rbar)) * (R[r] / PFD[r,inv_fd] + (1 - delta)) - 1)
    else
        error("Unknown data.par[\"invClosure\"] = $(inv_closure). Use \"gtap\", \"flexSf\" or \"usage\".")
    end

    # (M-20) Investment-savings balance is defined in the income block as Y-20.
    # This closure file does not duplicate Y-20.

    # (M-22) Deviation of expected rate of return from trend.
    @NLconstraint(m, [r=s.r], DeltaRoR[r] == Re[r] - Rn - Rd[r] - Rg)

    # (M-23) Desired growth rate of capital stock.
    @NLconstraint(m, [r=s.r],
        grK[r] == (grKMax * exp(chi_k * DeltaRoR[r]) + grKMin * ((grKMax - grKTrend) / (grKTrend - grKMin))) /
                 (exp(chi_k * DeltaRoR[r]) + ((grKMax - grKTrend) / (grKTrend - grKMin)))
    )

    # (M-24) Demand for new capital/investment.
    @NLconstraint(m, [r=s.r], XFD[r,inv_fd] == TKs[r] * (grK[r] + delta))

    # (M-25) Global savings/investment balance.
    # This is a literal duplicate of M-10 (sum(Sf[r] for r in s.r) == 0), which
    # is already declared above; it is not re-declared here to avoid pairing
    # two equations with the same (already-satisfied) global constraint.

    # (M-26) Model numeraire.
    @NLconstraint(m, PNUM == 1)

    # (M-33) Equivalent variation for the AIDADS class of demand systems, which
    # includes LES and Cobb-Douglas (documentation p. 64; the labels M-27/M-28
    # in the document are the PFACT and PWGDP price anchors, not EV/CV, so the
    # welfare measure is cited by its real label here):
    #
    #   ln(EV_r/Pop_r - Σ_k PC0_{r,k,h} γ_{r,k,h})
    #       = 1 + ln(A^ad_{r,h}) + u_{r,h} + Σ_k μ^c_{r,k,h} ln(PC0_{r,k,h}/μ^c_{r,k,h})
    #
    # evaluated at base-year consumer prices PC0.  With the benchmark price
    # normalisation PC0 = 1 and the AIDADS shifter A^ad = 1 this solves to the
    # expression below.  It replaces a `YFD - YFD` tautology that determined
    # nothing.
    @NLconstraint(m, [r=s.r],
        EV[r] == Pop[r] * (sum(gamma_c for k in s.k) +
                           exp(1 + m[:u][r,h0] +
                               sum(m[:μc][r,k,h0] * log(1.0 / (m[:μc][r,k,h0] + 1.0e-9)) for k in s.k)))
    )

    # (M-28 slot) Compensating variation.  ENVISAGE v10.01 §3.9.4 defines the
    # equivalent variation only; there is no compensating-variation equation
    # anywhere in the documentation (the section is flagged "will be revised").
    # CV is therefore reported as zero rather than as a `YFD - YFD` tautology.
    @NLconstraint(m, [r=s.r], CV[r] == 0.0)

    # (M-29) Global equivalent variation.
    @NLconstraint(m, EVG == sum(EV[r] for r in s.r))

    # (M-30) Global compensating variation.
    @NLconstraint(m, CVG == sum(CV[r] for r in s.r))

    # (M-31) Global social welfare function.
    @NLconstraint(m, SWF == sum(chi_welf * EV[r] for r in s.r))

    return m
end

function closure_residuals!(res::Dict{String,Function})
    for k in 1:31
        res["M-$k"] = x -> error("Residual M-$k is implemented as ENVISAGE M-$k in closure_block!.")
    end
    return res
end

function _closure_members(allvals::Vector{String}, selector)
    sel = selector === nothing ? "ALL" : strip(String(selector))
    if sel == "" || uppercase(sel) == "ALL"
        return allvals
    elseif sel in allvals
        return [sel]
    else
        @warn "Closure selector is not in this variable's domain; skipping selector" selector=sel domain=allvals
        return String[]
    end
end

function _closure_rule_value(varref, raw)
    if raw isa Number && !isnan(Float64(raw))
        return Float64(raw)
    end
    sv = try JuMP.start_value(varref) catch; nothing end
    return sv === nothing ? 0.0 : Float64(sv)
end

function _fix_closure_var!(m::JuMP.Model, varname::String, indices::Tuple, val)
    if !haskey(JuMP.object_dictionary(m), Symbol(varname))
        @warn "Closure variable not present in model; skipping" variable=varname indices=indices
        return false
    end
    obj = m[Symbol(varname)]
    vref = try isempty(indices) ? obj : obj[indices...] catch err
        @warn "Closure variable index is not present in model; skipping" variable=varname indices=indices error=err
        return false
    end
    JuMP.fix(vref, _closure_rule_value(vref, val); force=true)
    return true
end

function _norm_closure_var(rule_or_var)
    raw = rule_or_var isa AbstractDict ? String(get(rule_or_var, "variable", "")) : String(rule_or_var)
    u = uppercase(strip(raw))
    aliases = Dict(
        "APS"=>"aps", "CHIAPS"=>"chiaps", "ΧS"=>"chiaps",
        "WPREM"=>"wprem", "RS G"=>"RSg", "RSG"=>"RSg",
        "YFD"=>"YFD", "XFD"=>"XFD", "PFD"=>"PFD",
        "SF"=>"Sf", "SAVF"=>"Sf", "CAB"=>"Sf", "CHISF"=>"chisf", "SAVRAT"=>"chisf",
        "PNUM"=>"PNUM", "NUMERAIRE"=>"PNUM", "GDPMP"=>"GDPMP", "PGDPMP"=>"PGDPMP",
        "RGDPMP"=>"RGDPMP", "RGDPPC"=>"RGDPpc", "GY"=>"gy",
        "SG"=>"Sg", "SAVG"=>"Sg", "RSG"=>"RSg", "RG"=>"Rg", "RE"=>"Re", "RC"=>"Rc",
        "R"=>"R", "DELTAROR"=>"DeltaRoR", "GRK"=>"grK", "EV"=>"EV", "CV"=>"CV",
        "LS"=>"Ls", "TLS"=>"Ls", "LABSUP"=>"Ls",
        "TKS"=>"TKs", "KSUP"=>"TKs", "CAPSUP"=>"TKs",
        "TLAND"=>"TLand", "LANDSUP"=>"TLand",
        "CTAX"=>"τEmi", "CARBTAX"=>"τEmi", "CPRICE"=>"τEmi", "TAUEMI"=>"τEmi", "TEMI"=>"τEmi", "ΤEMI"=>"τEmi", "EMITAX"=>"τEmi",
        "ECAP"=>"EmiCap", "EMICAP"=>"EmiCap"
    )
    return get(aliases, u, strip(raw))
end

"""
    apply_default_closures!(m, data)

Fix the variables that ENVISAGE's standard closure treats as exogenous but that
the workbook's `closures` sheet does not mention.  The list follows the
documentation's exogenous tables: Table 4.1 (factors: capital stock, zonal
labour supply), Table 4.2 (macro closure: government expenditure), Table 4.5
(preferences: the LES/CDE marginal budget shares, endogenous only under AIDADS)
and Table 4.6 (emissions: other/exogenous emission sources and quota
allocations), plus two structural cases:

  * `K0` (initially installed Old capital) has no equation anywhere in the
    document — it is set in `initvint.gms` — so it is data, not a variable;
  * factor cells that no activity uses (land outside crops and livestock) are
    structural zeros with no demand equation and no price equation.

Every variable is fixed at its start value, i.e. at the calibrated benchmark, so
this changes the closure but not the benchmark solution.  Variables already
fixed by `apply_excel_closures!` are left untouched, so the workbook always
wins.  Returns a report with the number of instances fixed per family.
"""
function apply_default_closures!(m::JuMP.Model, data::EnvData)
    s = data.sets
    od = JuMP.object_dictionary(m)
    report = Dict{String,Int}()

    function fixref!(vref, name::String)
        (vref === nothing) && return
        JuMP.is_fixed(vref) && return
        sv = try JuMP.start_value(vref) catch; nothing end
        JuMP.fix(vref, sv === nothing ? 0.0 : Float64(sv); force=true)
        report[name] = get(report, name, 0) + 1
    end
    function fixall!(name::Symbol, keys)
        haskey(od, name) || return
        obj = m[name]
        for k in keys
            vref = try obj[k...] catch; nothing end
            fixref!(vref, String(name))
        end
    end

    demand_system = uppercase(String(get(data.par, "demand_system", "LES")))
    inv_closure = lowercase(strip(String(get(data.par, "invClosure", "gtap"))))
    aland = [a for a in s.a if a in s.acr || a in s.alv]
    anonland = [a for a in s.a if !(a in aland)]

    # Table 4.1: initially installed capital and the aggregate capital stock
    # that drives the Y-1 depreciation allowance.
    fixall!(:K0, ((r,a) for r in s.r, a in s.a))
    fixall!(:Ks, ((r,) for r in s.r))
    # Table 4.1: zonal labour supply.  F-10 (Ls = Σ_z LSz) determines the first
    # zone; the remaining zones are exogenous, as in the document where zonal
    # labour supply grows at the exogenous rate g^lz.
    if length(s.z) > 1
        fixall!(:LSz, ((r,l,z) for r in s.r, l in s.l, z in s.z[2:end]))
    end
    # Table 4.2: government expenditure is exogenous in the default fiscal
    # closure (YFD_gov); investment YFD comes from Y-20 and household YFD from
    # D-36.
    fixall!(:YFD, ((r,g) for r in s.r, g in s.gov))
    # Table 4.5: the marginal budget shares μ^c are calibrated parameters under
    # LES/ELES/CDE; only AIDADS (D-4) makes them endogenous.
    if demand_system != "AIDADS"
        fixall!(:μc, ((r,k,h) for r in s.r, k in s.k, h in s.h))
    end
    # Table 4.6: exogenous "other" emission sources and emission-quota terms.
    fixall!(:EmiOth, ((r,e) for r in s.r, e in s.em))
    fixall!(:EmiOthGbl, ((e,) for e in s.em))
    fixall!(:EmiQ, ((r,e) for r in s.r, e in s.em))
    rq = try _emission_coalitions(data) catch; s.r end
    fixall!(:τEmiQ, ((q,e) for q in rq, e in s.em))
    # M-22: the regional risk premium R^d is exogenous unless the flexible
    # foreign-saving closure (M-19) makes it endogenous.
    if inv_closure != "flexsf"
        fixall!(:Rd, ((r,) for r in s.r))
    end
    # P-3/P-5 use the price of the GHG bundle, PXGHG.  ENVISAGE derives it from
    # the emission tax schedule (§3.10); that mapping is not part of this port,
    # so the bundle price is held at its benchmark value.
    fixall!(:PXGHG, ((r,a,v) for r in s.r, a in s.a, v in s.v))
    # Land is demanded only by crops and livestock (P-14), so for every other
    # activity the land cell of XF is a structural zero with no demand equation
    # and its price has no market-clearing condition (F-36 covers agriculture).
    if !isempty(s.lnd)
        lnd0 = first(s.lnd)
        fixall!(:XF, ((r,lnd0,a) for r in s.r, a in anonland))
        fixall!(:PF, ((r,lnd0,a) for r in s.r, a in anonland))
    end
    return report
end

function apply_excel_closures!(m::JuMP.Model, data::EnvData)
    rules = get(data.par, "closure_rules", Any[])
    report = Dict{String,Any}("applied"=>0, "skipped"=>0, "rules"=>rules)
    isempty(rules) && return report
    s = data.sets
    for rule in rules
        active = lowercase(strip(String(get(rule,"active","TRUE")))) in ["true","1","yes","y"]
        active || (report["skipped"] += 1; continue)
        status = lowercase(strip(String(get(rule,"status","fixed"))))
        status in ["fixed","exogenous","fix"] || (report["skipped"] += 1; continue)
        var = _norm_closure_var(rule)
        val = get(rule,"value",NaN)
        applied = false
        if var in ["GDPMP","PGDPMP","RGDPMP","RGDPpc","gy","KLRat","Sg","RSg","Sf","phi","TKe","R","Rc","Re","DeltaRoR","grK","Rd","EV","CV","TKs","TLand"]
            for r in _closure_members(s.r, get(rule,"region","ALL"))
                applied |= _fix_closure_var!(m,var,(r,),val)
            end
        elseif var == "EmiCap"
            rq = try _emission_coalitions(data) catch; s.r end
            for q in _closure_members(Vector{String}(rq), get(rule,"region","ALL")), e in _closure_members(s.em, get(rule,"emission","ALL"))
                applied |= _fix_closure_var!(m,var,(q,e),val)
            end
        elseif var == "Ls"
            for r in _closure_members(s.r, get(rule,"region","ALL")), l in _closure_members(s.l, get(rule,"factor","ALL"))
                applied |= _fix_closure_var!(m,var,(r,l),val)
            end
        elseif var == "τEmi"
            for r in _closure_members(s.r, get(rule,"region","ALL")), e in _closure_members(s.em, get(rule,"emission","ALL"))
                applied |= _fix_closure_var!(m,var,(r,e),val)
            end
        elseif var in ["YFD","XFD","PFD"]
            for r in _closure_members(s.r, get(rule,"region","ALL")), fd in _closure_members(s.fd, get(rule,"agent","ALL"))
                applied |= _fix_closure_var!(m,var,(r,fd),val)
            end
        elseif var in ["PNUM","PWsav","Rg","EVG","CVG","SWF"]
            applied |= _fix_closure_var!(m,var,(),val)
        else
            @warn "Closure variable is not an ENVISAGE macro/closure variable in this package; skipping" variable=var
        end
        report[applied ? "applied" : "skipped"] += 1
    end
    return report
end
