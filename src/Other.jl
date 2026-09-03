# Usage: add_other_equations!(model, data, PAR)
# Paper-numbered LINKAGE equations coded as JuMP constraints.

function add_other_equations!(model, data::LinkageData, PAR)
    S=data.sets; default_sets!(data)
    i=S[:i]; j=S[:j]; k=S[:k]; r=S[:r]; rp=S[:rp]; v=S[:v]; l=S[:l]; h=S[:h]; f=S[:f]; ins=S[:in]; t=S[:t]
    cr=S[:cr]; lv=S[:lv]; ip=S[:ip]; e=S[:e]; ft=S[:ft]; fd=S[:fd]; nf=S[:nf]; nnft=S[:nnft]; nnfd=S[:nnfd]; gz=S[:gz]

    GDP=model[:GDP]; RGDP=model[:RGDP]; CPI=model[:CPI]; PGDP=model[:PGDP]; PNUM=model[:PNUM]; XP=model[:XP]; PP=model[:PP]; PC=model[:PC]
    GOVDEM=model[:GOVDEM]; INVDEM=model[:INVDEM]; PA=model[:PA]; PAp=model[:PAp]; XAf=model[:XAf]

    # (M-1) Nominal GDP at producer prices: sum of gross output valued at gross output prices.
    @constraint(model, M_1[rr in r], (GDP[rr]) - (sum(PP[ii]*XP[ii] for ii in i)) ⟂ GDP[rr])

    # (M-2) Real GDP index: unweighted sum of gross output volumes (base-year prices implicit in calibration).
    @constraint(model, M_2[rr in r], (RGDP[rr]) - (sum(XP[ii] for ii in i)) ⟂ RGDP[rr])

    # (M-3) GDP implicit price deflator: PGDP * RGDP = GDP, for all regions.
    @constraint(model, M_3[rr in r], (PGDP[rr]*RGDP[rr]) - (GDP[rr]) ⟂ PGDP[rr])

    # (M-4) Consumer price index: unweighted average of bundle prices across the k consumption bundles.
    @constraint(model, M_4[rr in r], (CPI[rr]) - (sum(PC[kk] for kk in k)/length(k)) ⟂ CPI[rr])

    # (M-5) Numeraire: PNUM fixed at 1 (self-referencing identity so PNUM has a
    # non-zero Jacobian on its own equation, required for PATH).
    @constraint(model, M_5, (PNUM) - (1.0) ⟂ PNUM)

    # Stub equations for GOVDEM and INVDEM (government and investment demand by good).
    # These equal the fixed-coefficient breakdowns of aggregate final demand FD[gov/inv].
    # D_8 (Demand.jl) already applies a_f[i,f] to get XAf[ii,ff] = a_f[(ii,ff)]*FD[ff],
    # so GOVDEM/INVDEM should just read off the corresponding XAf column directly.
    # The previous formula re-multiplied by a_f[(ii,gov/inv)] AND summed XAf over
    # every category ff in f (not just gov/inv), double-applying the gov/inv share
    # and mixing in the other category's demand -- a large, spurious residual
    # source (up to ~143 for M_INVDEM, ~93 for M_GOVDEM at the benchmark start).
    gov = ("Gov" in f) ? "Gov" : first(f)
    inv = ("Inv" in f) ? "Inv" : last(f)
    @constraint(model, M_GOVDEM[ii in i],
        (GOVDEM[ii]) - (XAf[ii,gov]) ⟂ GOVDEM[ii])
    @constraint(model, M_INVDEM[ii in i],
        (INVDEM[ii]) - (XAf[ii,inv]) ⟂ INVDEM[ii])

    # PAp off-diagonal wedge: PAp[j,i] = (1+tau_Ap[j,i]) * PA[j] for j ≠ i.
    # (Diagonal already handled by P_aux_PAp_wedge in Production.jl.)
    @constraint(model, M_PAp_offdiag[jj in i, ii in i; jj != ii],
        (PAp[jj,ii]) - ((1 + PAR[:tau_Ap][(jj,ii)]) * PA[jj]) ⟂ PAp[jj,ii])

    return model
end
