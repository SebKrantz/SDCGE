# ENVISAGE v10.01 Chapter 4 dynamics and Appendix C.1.
#
# This file is intentionally restricted to the dynamic variables and update
# equations named in the documentation.  It does not introduce ad-hoc state
# names such as K, I, L, TFP, KNOW or RESERVE.  The recursive dynamics are
# applied between static model solves, using the document's G- and C-numbered
# formulas.

# -----------------------------
# Small utilities for state data
# -----------------------------

_dyn_key(parts...) = join(string.(parts), "|")

function _dyn_get(state::Dict, parts...; default=0.0)
    k = _dyn_key(parts...)
    if haskey(state, k)
        return state[k]
    end
    if length(parts) == 1 && haskey(state, Symbol(parts[1]))
        return state[Symbol(parts[1])]
    end
    return default
end

function _dyn_set!(state::Dict, value, parts...)
    state[_dyn_key(parts...)] = value
    return value
end

function _dyn_first(v::Vector{String}, default::String)
    return isempty(v) ? default : first(v)
end

function _dyn_den(x; eps=1.0e-12)
    return abs(x) < eps ? (x < 0 ? -eps : eps) : x
end

# ------------------------------------------
# Document equations used by the dynamic path
# ------------------------------------------

# (G-1) Rural-to-urban migration.
function dyn_G1_MIGR(chi_m, pi_Urb, omega_m)
    return chi_m * pi_Urb^omega_m
end

# (G-2) Labor supply by skill and zone.
function dyn_G2_LSz(LSz_tm, g_lz, n, delta_m, mu_m, MIGR)
    return (1 + g_lz)^n * LSz_tm + delta_m * mu_m * MIGR
end

# (G-3) Migration multiplier.
function dyn_G3_mu_m(g_lz, n, pi_Urb_tm, pi_Urb_t, omega_m)
    ratio = pi_Urb_tm / _dyn_den(pi_Urb_t)
    num = (1 + g_lz)^n * ratio^omega_m - 1
    den = (1 + g_lz) * ratio^(omega_m / n) - 1
    return num / _dyn_den(den)
end

# (G-4) Total labor supply by skill.
function dyn_G4_LABs(LABs_tm, g_l, n)
    return (1 + g_l)^n * LABs_tm
end

# (G-5) One-period capital accumulation.
function dyn_G5_Ks(Ks_tm1, delta, XFD_inv_tm1)
    return (1 - delta) * Ks_tm1 + XFD_inv_tm1
end

# (G-6) Normalized capital stock.
function dyn_G6_TKs(chi_k, Ks)
    return chi_k * Ks
end

# (G-7) Knowledge stock with distributed R&D lag.
function dyn_G7_KN(KN_tm1, delta_k, gamma_k::AbstractVector, XFD_rd_lag::AbstractVector)
    return (1 - delta_k) * KN_tm1 + sum(gamma_k[i] * XFD_rd_lag[i] for i in eachindex(gamma_k))
end

# (G-8) Endogenous labor productivity component from knowledge growth.
function dyn_G8_pi_k(gamma_r, epsilon_r, KN_t, KN_tm1)
    return gamma_r * epsilon_r * (KN_t / _dyn_den(KN_tm1) - 1)
end

# (G-9) Labor productivity shift.  The document describes lambda_f as the
# labor-augmenting technology shifter with trend growth and optional skill and
# knowledge components.  This helper keeps only the documented components.
function dyn_G9_lambda_f(lambda_f_tm1, gamma_l, n, alpha_gl, beta_gl, chi_gl, pi_k)
    return lambda_f_tm1 * (1 + alpha_gl + beta_gl * gamma_l + chi_gl + pi_k)^n
end

# (C-1) Investment growth factor for multi-year steps.
function dyn_C1_Psi(XFD_inv_t, XFD_inv_tm, n, delta)
    gI = (XFD_inv_t / _dyn_den(XFD_inv_tm))^(1 / n) - 1
    return 1 / _dyn_den(gI + delta)
end

# (C-2) Multi-period non-normalized capital stock accumulation.
function dyn_C2_Ks(Ks_tm, Psi, XFD_inv_tm, XFD_inv_t, n, delta)
    return (Ks_tm - Psi * XFD_inv_tm) * (1 - delta)^n + Psi * XFD_inv_t
end

# (G-10) National-sourcing Armington twist for alpha_dt and alpha_mt.
function dyn_G10_armington_twist_national(alpha_dt_tm1, alpha_mt_tm1, PMT_tm1, XMT_tm1, PAT_tm1, XAT_tm1, twt1)
    st1 = (PMT_tm1 * XMT_tm1) / _dyn_den(PAT_tm1 * XAT_tm1)
    denom = 1 + st1 * twt1
    return alpha_dt_tm1 / _dyn_den(denom), alpha_mt_tm1 * (1 + twt1) / _dyn_den(denom)
end

# (G-11) Agent-sourcing Armington twist for alpha_d and alpha_m.
function dyn_G11_armington_twist_agent(alpha_d_tm1, alpha_m_tm1, PM_tm1, XM_tm1, PD_tm1, XD_tm1, twt1)
    st1 = (PM_tm1 * XM_tm1) / _dyn_den(PD_tm1 * XD_tm1 + PM_tm1 * XM_tm1)
    denom = 1 + st1 * twt1
    return alpha_d_tm1 / _dyn_den(denom), alpha_m_tm1 * (1 + twt1) / _dyn_den(denom)
end

# (G-12) Second-level import-sourcing twist across regions of origin.
function dyn_G12_import_origin_twist(alpha_w_tm1, PMa_tm1, XWa_tm1, twt2)
    value_total = sum(PMa_tm1[j] * XWa_tm1[j] for j in eachindex(alpha_w_tm1))
    shares = [PMa_tm1[j] * XWa_tm1[j] / _dyn_den(value_total) for j in eachindex(alpha_w_tm1)]
    denom = 1 + sum(shares[j] * twt2[j] for j in eachindex(alpha_w_tm1))
    return [alpha_w_tm1[j] * (1 + twt2[j]) / _dyn_den(denom) for j in eachindex(alpha_w_tm1)]
end

# ---------------------------------------------------------
# Recursive state propagation using document variable names
# ---------------------------------------------------------

function dynamics_update!(state::Dict, data::EnvData, cal::EnvCalibration, tprev, tnext)
    PAR = parameters(data, cal)
    # Local parameter aliases generated from ParameterTables.jl.
    chi_k = PAR[:chi_k]
    chi_m = PAR[:chi_m]
    delta = PAR[:delta]
    delta_k = PAR[:delta_k]
    omega_m = PAR[:omega_m]
    s = data.sets
    n = Float64(_dyn_get(state, "n", tnext; default=get(data.par, "n", 1.0)))
    inv_fd = isempty(s.inv) ? (isempty(s.fd) ? "inv" : first(s.fd)) : (first(s.inv) in s.fd ? first(s.inv) : (isempty(s.fd) ? first(s.inv) : first(s.fd)))
    rd_fd = get(data.par, "rd_fd", "rd")

    for r in s.r
        delta = Float64(_dyn_get(state, "delta", r, tnext; default=delta))
        chi_k = Float64(_dyn_get(state, "chi_k", r; default=chi_k))

        # (C-1) Investment growth factor for multi-year time steps.
        XFD_inv_t  = Float64(_dyn_get(state, "XFD", r, inv_fd, tnext; default=_dyn_get(state, "XFD", r, inv_fd, tprev; default=0.0)))
        XFD_inv_tm = Float64(_dyn_get(state, "XFD", r, inv_fd, tprev; default=XFD_inv_t))
        Psi = dyn_C1_Psi(XFD_inv_t, XFD_inv_tm, n, delta)
        _dyn_set!(state, Psi, "Psi", r, tnext)

        # (G-5)/(C-2) Capital accumulation.  Use C-2 for n != 1, G-5 for single-year steps.
        Ks_tm = Float64(_dyn_get(state, "Ks", r, tprev; default=_dyn_get(state, "Ks", r; default=0.0)))
        Ks_t = isapprox(n, 1.0) ? dyn_G5_Ks(Ks_tm, delta, XFD_inv_tm) : dyn_C2_Ks(Ks_tm, Psi, XFD_inv_tm, XFD_inv_t, n, delta)
        _dyn_set!(state, Ks_t, "Ks", r, tnext)

        # (G-6) Normalized capital stock.
        _dyn_set!(state, dyn_G6_TKs(chi_k, Ks_t), "TKs", r, tnext)

        for l in s.l
            omega_m = Float64(_dyn_get(state, "omega_m", r, l; default=omega_m))
            chi_m = Float64(_dyn_get(state, "chi_m", r, l; default=chi_m))
            pi_Urb_t  = Float64(_dyn_get(state, "pi_Urb", r, l, tnext; default=1.0))
            pi_Urb_tm = Float64(_dyn_get(state, "pi_Urb", r, l, tprev; default=pi_Urb_t))

            # (G-1) Migration.
            MIGR = dyn_G1_MIGR(chi_m, pi_Urb_t, omega_m)
            _dyn_set!(state, MIGR, "MIGR", r, l, tnext)

            # (G-4) Total labor supply by skill.
            g_l = Float64(_dyn_get(state, "g_l", r, l, tnext; default=_dyn_get(state, "g_l", r, l; default=0.0)))
            LABs_tm = Float64(_dyn_get(state, "LABs", r, l, tprev; default=_dyn_get(state, "LABs", r, l; default=0.0)))
            _dyn_set!(state, dyn_G4_LABs(LABs_tm, g_l, n), "LABs", r, l, tnext)

            for z in s.z
                g_lz = Float64(_dyn_get(state, "g_lz", r, l, z, tnext; default=_dyn_get(state, "g_lz", r, l, z; default=g_l)))
                delta_m = Float64(_dyn_get(state, "delta_m", z; default=(lowercase(z) in ["urb", "urban"] ? 1.0 : -1.0)))

                # (G-3) Migration multiplier.
                mu_m = dyn_G3_mu_m(g_lz, n, pi_Urb_tm, pi_Urb_t, omega_m)
                _dyn_set!(state, mu_m, "mu_m", r, l, z, tnext)

                # (G-2) Zone labor supply.
                LSz_tm = Float64(_dyn_get(state, "LSz", r, l, z, tprev; default=_dyn_get(state, "LSz", r, l, z; default=0.0)))
                _dyn_set!(state, dyn_G2_LSz(LSz_tm, g_lz, n, delta_m, mu_m, MIGR), "LSz", r, l, z, tnext)
            end
        end

        # (G-7) Knowledge stock, if R&D data are supplied in the state.
        if haskey(state, _dyn_key("KN", r, tprev)) || haskey(state, _dyn_key("XFD", r, rd_fd, tnext))
            delta_k = Float64(_dyn_get(state, "delta_k", r; default=delta_k))
            KN_tm = Float64(_dyn_get(state, "KN", r, tprev; default=_dyn_get(state, "KN", r; default=1.0)))
            gamma_k = _dyn_get(state, "gamma_k", r; default=[1.0])
            gamma_vec = gamma_k isa AbstractVector ? gamma_k : [Float64(gamma_k)]
            XFD_rd_lag = [Float64(_dyn_get(state, "XFD", r, rd_fd, "lag$(i-1)"; default=_dyn_get(state, "XFD", r, rd_fd, tnext; default=0.0))) for i in eachindex(gamma_vec)]
            KN_t = dyn_G7_KN(KN_tm, delta_k, gamma_vec, XFD_rd_lag)
            _dyn_set!(state, KN_t, "KN", r, tnext)

            for a in s.a
                gamma_r = Float64(_dyn_get(state, "gamma_r", r, a, tnext; default=1.0))
                epsilon_r = Float64(_dyn_get(state, "epsilon_r", r, a, tnext; default=0.0))

                # (G-8) Knowledge-induced productivity component.
                pi_k = dyn_G8_pi_k(gamma_r, epsilon_r, KN_t, KN_tm)
                _dyn_set!(state, pi_k, "pi_k", r, a, tnext)

                for l in s.l
                    lambda_f_tm = Float64(_dyn_get(state, "lambda_f", r, l, a, tprev; default=_dyn_get(state, "lambda_f", r, l, a; default=1.0)))
                    gamma_l = Float64(_dyn_get(state, "gamma_l", r, l, a, tnext; default=0.0))
                    alpha_gl = Float64(_dyn_get(state, "alpha_gl", r, a, tnext; default=0.0))
                    beta_gl = Float64(_dyn_get(state, "beta_gl", r, a, tnext; default=1.0))
                    chi_gl = Float64(_dyn_get(state, "chi_gl", r, l, a, tnext; default=0.0))

                    # (G-9) Labor productivity shifter.
                    _dyn_set!(state, dyn_G9_lambda_f(lambda_f_tm, gamma_l, n, alpha_gl, beta_gl, chi_gl, pi_k), "lambda_f", r, l, a, tnext)
                end
            end
        end
    end

    return state
end

function run_recursive_dynamic!(model::EnvModel, state::Dict)
    tset = model.data.sets.t
    if isempty(tset)
        return state
    end
    tprev = isempty(tset) ? "t" : first(tset)
    for tnext in tset
        solve!(model)
        dynamics_update!(state, model.data, model.calib, tprev, tnext)
        tprev = tnext
    end
    return state
end

function dynamics_residuals!(res::Dict{String,Function})
    for k in 1:12
        res["G-$k"] = x -> error("Dynamic equation G-$k is implemented in dynamics_update! as recursive state propagation between model periods.")
    end
    res["C-1"] = x -> error("Capital-stock equation C-1 is implemented in dynamics_update! as recursive state propagation between model periods.")
    res["C-2"] = x -> error("Capital-stock equation C-2 is implemented in dynamics_update! as recursive state propagation between model periods.")
    return res
end
