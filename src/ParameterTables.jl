# === LINKAGE-style parameter table ===
# Precompute all scalar/table parameters used by EnvCGE equation blocks.
# Usage:
#   PAR = parameters(data, cal)
# Equation files index PAR directly, e.g. PAR[:sigma_p], PAR[:alpha_i][i].
# Calibration dictionary lookups are kept here, not inside equation files.
# ======================================

const EnvParameters = Dict{Symbol,Any}

_asfloat(x, default=0.0) = try Float64(x) catch; Float64(default) end

function _strdict(d; default=Dict{String,Any}())
    d isa AbstractDict || return deepcopy(default)
    return Dict{String,Any}(String(k)=>v for (k,v) in d)
end

function _numeric_strdict(d)
    out = Dict{String,Float64}()
    if d isa AbstractDict
        for (k,v) in d
            out[String(k)] = _asfloat(v, 0.0)
        end
    end
    return out
end

function _positive_share_dict(values::Dict{String,Float64}, keys; group::String="alpha")
    ks = [String(k) for k in keys]
    vals = Dict{String,Float64}(k => max(get(values, k, 0.0), 0.0) for k in ks)
    total = sum(Base.values(vals))
    if total <= 0.0
        error("Cannot compute $group from Excel data: benchmark total is zero or missing for keys $(join(ks, ", ")).")
    end
    return Dict{String,Float64}(k => vals[k] / total for k in ks)
end

function _positive_share_dict_or_empty(values::Dict{String,Float64}, keys; group::String="alpha")
    isempty(keys) && return Dict{String,Float64}()
    return _positive_share_dict(values, keys; group=group)
end

function _share_dict_with_zeros(values::Dict{String,Float64}, positive_keys, all_keys; group::String="alpha")
    # Compute shares over positive_keys from Excel benchmark values, then add
    # explicit zero entries for the remaining all_keys.  The zeros are not
    # defaults; they encode the Excel set classification used by nests that
    # require a value for every k.
    pos = _positive_share_dict(values, positive_keys; group=group)
    out = Dict{String,Float64}(String(k) => 0.0 for k in all_keys)
    for (k, v) in pos
        out[k] = v
    end
    return out
end

function _is_effectively_uniform(d; atol=1e-10)
    d isa AbstractDict || return true
    vals = [_asfloat(v, 0.0) for (_, v) in d]
    length(vals) <= 1 && return true
    return maximum(vals) - minimum(vals) <= atol
end

function _sum_table_by_key(df, keycol::Symbol, valcol::Symbol=:value)
    out = Dict{String,Float64}()
    if df isa DataFrame && !isempty(df) && keycol in propertynames(df) && valcol in propertynames(df)
        for row in eachrow(df)
            ismissing(row[keycol]) && continue
            k = String(row[keycol])
            out[k] = get(out, k, 0.0) + max(_asfloat(row[valcol], 0.0), 0.0)
        end
    end
    return out
end


function _sum_table_by_region(df, valcol::Symbol=:value)
    out = Dict{String,Float64}()
    if df isa DataFrame && !isempty(df) && (:region in propertynames(df)) && (valcol in propertynames(df))
        for row in eachrow(df)
            ismissing(row[:region]) && continue
            r = String(row[:region])
            out[r] = get(out, r, 0.0) + max(_asfloat(row[valcol], 0.0), 0.0)
        end
    end
    return out
end

function _add_values!(dst::Dict{String,Float64}, src::Dict{String,Float64})
    for (k, v) in src
        dst[k] = get(dst, k, 0.0) + v
    end
    return dst
end

function _sum_waste_by_product(data::EnvData)
    # Optional Excel-only waste source.  If the workbook has no waste table,
    # this remains empty; downstream actual/waste shares then use the observed
    # positive benchmark demand/supply as actual consumption and zero recorded waste.
    vals = Dict{String,Float64}()
    for tbl in ["waste", "food_waste", "consumer_waste"]
        df = get(data.tables, tbl, DataFrame())
        if df isa DataFrame && !isempty(df) && all(sym -> sym in propertynames(df), [:product, :value])
            _add_values!(vals, _sum_table_by_key(df, :product))
        end
    end
    return vals
end

function _actual_waste_share_dict(actual::Dict{String,Float64}, waste::Dict{String,Float64}, keys; group::String="alpha_ac")
    out = Dict{String,Float64}()
    missing = String[]
    for k0 in keys
        k = String(k0)
        a = max(get(actual, k, 0.0), 0.0)
        w = max(get(waste, k, 0.0), 0.0)
        total = a + w
        if total <= 0.0
            push!(missing, k)
        else
            out[k] = group == "alpha_aw" ? w / total : a / total
        end
    end
    isempty(missing) || error("Cannot compute $group from Excel data: actual plus waste benchmark total is zero or missing for keys $(join(missing, ", ")).")
    return out
end

function _sum_factor_demand_by_factor(data::EnvData)
    vals = _sum_table_by_key(get(data.tables, "factor_demand", DataFrame()), :factor)
    if isempty(vals)
        vals = _sum_sam_factor_payments(data.sam)
    end
    return vals
end

function _sum_factor_demand_by_activity(data::EnvData; factors=nothing)
    out = Dict{String,Float64}()
    df = get(data.tables, "factor_demand", DataFrame())
    if df isa DataFrame && !isempty(df) && all(sym -> sym in propertynames(df), [:activity, :value])
        factor_filter = factors === nothing ? nothing : Set(String.(factors))
        for row in eachrow(df)
            ismissing(row[:activity]) && continue
            if factor_filter !== nothing
                (:factor in propertynames(df)) || continue
                ismissing(row[:factor]) && continue
                String(row[:factor]) in factor_filter || continue
            end
            k = String(row[:activity])
            out[k] = get(out, k, 0.0) + max(_asfloat(row[:value], 0.0), 0.0)
        end
    end
    return out
end

function _sam_account_parts(x)
    parts = split(strip(String(x)), ":")
    return length(parts) >= 3 ? (parts[1], parts[2], parts[3]) : ("", "", "")
end

function _sum_sam_rows_by_item(sam::DataFrame, accttype::String)
    out = Dict{String,Float64}()
    if !isempty(sam) && all(sym -> sym in propertynames(sam), [:row, :value])
        for row in eachrow(sam)
            typ, _r, item = _sam_account_parts(row[:row])
            typ == accttype || continue
            out[item] = get(out, item, 0.0) + max(_asfloat(row[:value], 0.0), 0.0)
        end
    end
    return out
end

function _sum_sam_cols_by_item(sam::DataFrame, accttype::String)
    out = Dict{String,Float64}()
    if !isempty(sam) && all(sym -> sym in propertynames(sam), [:col, :value])
        for row in eachrow(sam)
            typ, _r, item = _sam_account_parts(row[:col])
            typ == accttype || continue
            out[item] = get(out, item, 0.0) + max(_asfloat(row[:value], 0.0), 0.0)
        end
    end
    return out
end

function _sum_sam_factor_payments(sam::DataFrame)
    out = Dict{String,Float64}()
    if !isempty(sam) && all(sym -> sym in propertynames(sam), [:row, :col, :value])
        for row in eachrow(sam)
            rtyp, _rr, f = _sam_account_parts(row[:row])
            ctyp, _cr, _a = _sam_account_parts(row[:col])
            (rtyp == "FAC" && ctyp == "ACT") || continue
            out[f] = get(out, f, 0.0) + max(_asfloat(row[:value], 0.0), 0.0)
        end
    end
    return out
end

function _sum_use_by_product(data::EnvData)
    vals = _sum_table_by_key(get(data.tables, "use", DataFrame()), :product)
    if isempty(vals)
        vals = _sum_sam_rows_by_item(data.sam, "COM")
    end
    return vals
end

function _sum_make_by_product(data::EnvData)
    vals = _sum_table_by_key(get(data.tables, "make", DataFrame()), :product)
    if isempty(vals)
        vals = _sum_sam_rows_by_item(data.sam, "COM")
    end
    return vals
end

function _sum_make_by_activity(data::EnvData)
    vals = _sum_table_by_key(get(data.tables, "make", DataFrame()), :activity)
    if isempty(vals)
        vals = _sum_sam_cols_by_item(data.sam, "ACT")
    end
    return vals
end

function _sum_final_demand_by_product(data::EnvData; fd_filter=nothing)
    out = Dict{String,Float64}()
    df = get(data.tables, "final_demand", DataFrame())
    if df isa DataFrame && !isempty(df) && all(sym -> sym in propertynames(df), [:product, :value])
        for row in eachrow(df)
            if fd_filter !== nothing && (:fd in propertynames(df)) && !(String(row[:fd]) in fd_filter)
                continue
            end
            ismissing(row[:product]) && continue
            k = String(row[:product])
            out[k] = get(out, k, 0.0) + max(_asfloat(row[:value], 0.0), 0.0)
        end
    end
    return out
end



function _sum_use_by_activity(data::EnvData; activities=nothing, products=nothing)
    total = 0.0
    df = get(data.tables, "use", DataFrame())
    if df isa DataFrame && !isempty(df) && all(sym -> sym in propertynames(df), [:activity, :product, :value])
        aset = activities === nothing ? nothing : Set(String.(activities))
        pset = products === nothing ? nothing : Set(String.(products))
        for row in eachrow(df)
            ismissing(row[:activity]) && continue
            ismissing(row[:product]) && continue
            a = String(row[:activity]); p = String(row[:product])
            (aset === nothing || a in aset) || continue
            (pset === nothing || p in pset) || continue
            total += max(_asfloat(row[:value], 0.0), 0.0)
        end
    end
    return total
end

function _sum_factor_by_activity_set(data::EnvData, activities, factors)
    total = 0.0
    df = get(data.tables, "factor_demand", DataFrame())
    if df isa DataFrame && !isempty(df) && all(sym -> sym in propertynames(df), [:activity, :factor, :value])
        aset = Set(String.(activities)); fset = Set(String.(factors))
        for row in eachrow(df)
            ismissing(row[:activity]) && continue
            ismissing(row[:factor]) && continue
            (String(row[:activity]) in aset && String(row[:factor]) in fset) || continue
            total += max(_asfloat(row[:value], 0.0), 0.0)
        end
    end
    return total
end

function _sum_final_demand_by_agent(data::EnvData)
    out = Dict{String,Float64}()
    df = get(data.tables, "final_demand", DataFrame())
    if df isa DataFrame && !isempty(df) && all(sym -> sym in propertynames(df), [:fd, :value])
        for row in eachrow(df)
            ismissing(row[:fd]) && continue
            fd = String(row[:fd])
            out[fd] = get(out, fd, 0.0) + max(_asfloat(row[:value], 0.0), 0.0)
        end
    end
    return out
end

function _sum_use_by_agent_activity(data::EnvData)
    out = Dict{String,Float64}()
    df = get(data.tables, "use", DataFrame())
    if df isa DataFrame && !isempty(df) && all(sym -> sym in propertynames(df), [:activity, :value])
        for row in eachrow(df)
            ismissing(row[:activity]) && continue
            a = String(row[:activity])
            out[a] = get(out, a, 0.0) + max(_asfloat(row[:value], 0.0), 0.0)
        end
    end
    return out
end

function _sum_make_by_region(data::EnvData)
    return _sum_table_by_region(get(data.tables, "make", DataFrame()))
end

function _sum_absorption_by_region(data::EnvData)
    out = Dict{String,Float64}()
    for tbl in ["use", "final_demand"]
        _add_values!(out, _sum_table_by_region(get(data.tables, tbl, DataFrame())))
    end
    return out
end

function _agent_absorption_values(data::EnvData)
    out = _sum_use_by_agent_activity(data)
    _add_values!(out, _sum_final_demand_by_agent(data))
    return out
end

function _sam_region_agent_values(data::EnvData)
    # Values are keyed by "source_region|agent" and derived from COM rows in the SAM.
    # This supplies MRIO/import-origin shares from observed interregional commodity flows.
    out = Dict{String,Float64}()
    sam = data.sam
    if !isempty(sam) && all(sym -> sym in propertynames(sam), [:row, :col, :value])
        for row in eachrow(sam)
            rtyp, sr, _item = _sam_account_parts(row[:row])
            ctyp, _dr, agent = _sam_account_parts(row[:col])
            rtyp == "COM" || continue
            ctyp in ("ACT", "HH", "GOV", "INV") || continue
            key = string(sr, "|", agent)
            out[key] = get(out, key, 0.0) + max(_asfloat(row[:value], 0.0), 0.0)
        end
    end
    return out
end

function _agent_region_share_table(data::EnvData, regions, agents; group::String="alpha_wa")
    raw = _sam_region_agent_values(data)
    out = Dict{String,Float64}()
    missing = String[]
    for aa0 in agents
        aa = String(aa0)
        vals = Dict{String,Float64}(String(r) => get(raw, string(r, "|", aa), 0.0) for r in regions)
        total = sum(Base.values(vals))
        if total <= 0.0
            push!(missing, aa)
        else
            for r in regions
                rs = String(r)
                out[string(rs, "|", aa)] = vals[rs] / total
            end
        end
    end
    isempty(missing) || error("Cannot compute $group from Excel SAM data: benchmark total is zero or missing for agents $(join(missing, ", ")).")
    return out
end

function _domestic_import_export_values(data::EnvData)
    # Use interregional COM->COM SAM flows: same-region flows are domestic, cross-region flows are import/export evidence.
    vals = Dict("D" => 0.0, "M" => 0.0, "E" => 0.0)
    sam = data.sam
    if !isempty(sam) && all(sym -> sym in propertynames(sam), [:row, :col, :value])
        for row in eachrow(sam)
            rtyp, sr, _ = _sam_account_parts(row[:row])
            ctyp, dr, _ = _sam_account_parts(row[:col])
            (rtyp == "COM" && ctyp == "COM") || continue
            v = max(_asfloat(row[:value], 0.0), 0.0)
            if sr == dr
                vals["D"] += v
            else
                vals["M"] += v
                vals["E"] += v
            end
        end
    end
    if vals["D"] + vals["M"] <= 0.0
        # Fall back to observed domestic absorption and region-to-region sourcing in the SAM if COM->COM is absent.
        vals["D"] = sum(Base.values(_sum_make_by_region(data)))
        vals["M"] = 0.0
        vals["E"] = 0.0
    end
    return vals
end

function _two_share_dict(values::Dict{String,Float64}, keys; group::String)
    return _positive_share_dict(values, keys; group=group)
end


function _sum_use_by_activity_product(data::EnvData)
    out = Dict{Tuple{String,String},Float64}()
    df = get(data.tables, "use", DataFrame())
    if df isa DataFrame && !isempty(df) && all(sym -> sym in propertynames(df), [:activity, :product, :value])
        for row in eachrow(df)
            (ismissing(row[:activity]) || ismissing(row[:product])) && continue
            a = String(row[:activity]); i = String(row[:product])
            out[(a,i)] = get(out, (a,i), 0.0) + max(_asfloat(row[:value], 0.0), 0.0)
        end
    end
    return out
end

function _sum_make_by_activity_product(data::EnvData)
    out = Dict{Tuple{String,String},Float64}()
    df = get(data.tables, "make", DataFrame())
    if df isa DataFrame && !isempty(df) && all(sym -> sym in propertynames(df), [:activity, :product, :value])
        for row in eachrow(df)
            (ismissing(row[:activity]) || ismissing(row[:product])) && continue
            a = String(row[:activity]); i = String(row[:product])
            out[(a,i)] = get(out, (a,i), 0.0) + max(_asfloat(row[:value], 0.0), 0.0)
        end
    end
    return out
end

function _sum_factor_by_activity_factor(data::EnvData)
    out = Dict{Tuple{String,String},Float64}()
    df = get(data.tables, "factor_demand", DataFrame())
    if df isa DataFrame && !isempty(df) && all(sym -> sym in propertynames(df), [:activity, :factor, :value])
        for row in eachrow(df)
            (ismissing(row[:activity]) || ismissing(row[:factor])) && continue
            a = String(row[:activity]); f = String(row[:factor])
            out[(a,f)] = get(out, (a,f), 0.0) + max(_asfloat(row[:value], 0.0), 0.0)
        end
    end
    return out
end

function _component_share_by_activity(raw::Dict{Tuple{String,String},Float64}, activities, components; group::String, allow_zero::Bool=false)
    (isempty(activities) || isempty(components)) && return Dict{String,Float64}()
    out = Dict{String,Float64}()
    missing = String[]
    for a0 in activities
        a = String(a0)
        vals = Dict{String,Float64}(String(c) => max(get(raw, (a,String(c)), 0.0), 0.0) for c in components)
        total = sum(Base.values(vals))
        if total <= 0.0
            if allow_zero
                for c in components
                    out[string(a,"|",String(c))] = 0.0
                end
            else
                push!(missing, a)
            end
        else
            for c in components
                cs = String(c)
                out[string(a,"|",cs)] = vals[cs] / total
            end
        end
    end
    isempty(missing) || error("Cannot compute $group by activity from Excel data: benchmark total is zero or missing for activities $(join(missing, ", ")).")
    return out
end

function _component_share_by_product(raw::Dict{Tuple{String,String},Float64}, products, components; group::String)
    (isempty(products) || isempty(components)) && return Dict{String,Float64}()
    out = Dict{String,Float64}()
    for i0 in products
        i = String(i0)
        vals = Dict{String,Float64}(String(c) => max(get(raw, (String(c),i), 0.0), 0.0) for c in components)
        total = sum(Base.values(vals))
        if total <= 0.0
            # Excel/SAM benchmark has no observed supply for this product.
            # Keep the parameter Excel-derived by assigning zero shares for
            # every component rather than introducing equal-share/default starts.
            for c in components
                cs = String(c)
                out[string(cs,"|",i)] = 0.0
            end
        else
            for c in components
                cs = String(c)
                out[string(cs,"|",i)] = vals[cs] / total
            end
        end
    end
    return out
end

function _activity_component_values(data::EnvData)
    s = data.sets
    useap = _sum_use_by_activity_product(data)
    facap = _sum_factor_by_activity_factor(data)
    energy = Set(String.(s.nrg)); nonenergy = Set(String.(setdiff(s.i, s.nrg)))
    ul = Set(String.(s.ul)); sl = Set(String.(s.sl)); cap = Set(String.(s.cap)); lnd = Set(String.(s.lnd)); wat = Set(String.(s.wat)); nrs = Set(String.(s.nrs))
    out = Dict{Tuple{String,String},Float64}()
    for a0 in s.a
        a = String(a0)
        use_non = sum((v for ((aa,i),v) in useap if aa == a && i in nonenergy); init=0.0)
        use_en  = sum((v for ((aa,i),v) in useap if aa == a && i in energy); init=0.0)
        use_all = use_non + use_en
        lab1 = sum((v for ((aa,f),v) in facap if aa == a && f in ul); init=0.0)
        lab2 = sum((v for ((aa,f),v) in facap if aa == a && f in sl); init=0.0)
        kval = sum((v for ((aa,f),v) in facap if aa == a && f in cap); init=0.0)
        land = sum((v for ((aa,f),v) in facap if aa == a && f in lnd); init=0.0)
        water = sum((v for ((aa,f),v) in facap if aa == a && f in wat); init=0.0)
        nrsv = sum((v for ((aa,f),v) in facap if aa == a && f in nrs); init=0.0)
        ftotal = lab1 + lab2 + kval + land + water + nrsv
        va1 = max(ftotal - lab1, 0.0)
        va2 = va1
        kef = kval + lab2 + water + nrsv + use_en
        kf = kval + lab2
        ksw = kf + water
        out[(a,"LAB1")] = lab1; out[(a,"VA1")] = va1; out[(a,"ND2")] = use_all; out[(a,"VA2")] = va2
        out[(a,"KEF")] = kef; out[(a,"LAND")] = land; out[(a,"ENERGY")] = use_en; out[(a,"KF")] = kf; out[(a,"KSW")] = ksw; out[(a,"NRS")] = nrsv
        out[(a,"KS")] = kf; out[(a,"WAT")] = water; out[(a,"CAP")] = kval; out[(a,"LAB2")] = lab2
        out[(a,"ND1")] = use_non; out[(a,"VA")] = ftotal; out[(a,"XGHG")] = 0.0; out[(a,"XPX")] = max(get(_sum_make_by_activity(data), a, 0.0), 0.0)
        ely = sum(get(useap, (a,String(i)), 0.0) for i in s.ely)
        nely = sum(get(useap, (a,String(i)), 0.0) for i in setdiff(s.nrg, s.ely))
        coal = get(useap, (a,"COAL"), 0.0); gas = get(useap, (a,"GAS"), 0.0); oil = get(useap, (a,"OIL"), 0.0)
        out[(a,"ELY")] = ely; out[(a,"NELY")] = nely; out[(a,"COA")] = coal; out[(a,"OLG")] = gas + oil; out[(a,"GAS")] = gas; out[(a,"OIL")] = oil
        feed = sum(get(useap, (a,String(i)), 0.0) for i in intersect(s.i, ["CEREALS", "ROOTS", "OILSEEDS", "FOOD", "FOOD_PROC"]))
        out[(a,"FEED")] = feed
    end
    return out
end

function _factor_share_by_activity(data::EnvData, factors; group::String)
    rawfac = _sum_factor_by_activity_factor(data)
    raw = Dict{Tuple{String,String},Float64}()
    for a in data.sets.a, f in factors
        raw[(String(a),String(f))] = get(rawfac, (String(a),String(f)), 0.0)
    end
    return _component_share_by_activity(raw, data.sets.a, factors; group=group, allow_zero=true)
end

function _use_share_by_activity(data::EnvData, products; group::String)
    useap = _sum_use_by_activity_product(data)
    raw = Dict{Tuple{String,String},Float64}()
    for a in data.sets.a, i in products
        raw[(String(a),String(i))] = get(useap, (String(a),String(i)), 0.0)
    end
    return _component_share_by_activity(raw, data.sets.a, products; group=group, allow_zero=true)
end

function _make_gamma_by_activity(data::EnvData)
    makeap = _sum_make_by_activity_product(data)
    return _component_share_by_activity(makeap, data.sets.a, data.sets.i; group="gamma_p")
end

function _make_alpha_by_product(data::EnvData)
    makeap = _sum_make_by_activity_product(data)
    return _component_share_by_product(makeap, data.sets.i, data.sets.a; group="alpha_s")
end

function _power_generation_by_block_product_activity(data::EnvData)
    s = data.sets
    makeap = _sum_make_by_activity_product(data)
    out_pb = Dict{Tuple{String,String},Float64}()      # (ely,pb)
    out_a  = Dict{Tuple{String,String},Float64}()      # (pb|ely,a) encoded later
    elyset = Set(String.(s.ely)); elyaset = Set(String.(s.elya))
    for ((a,i),v) in makeap
        (a in elyaset && i in elyset) || continue
        pb = _power_block_from_activity(a, s.pb)
        pb == "" && continue
        out_pb[(i,pb)] = get(out_pb, (i,pb), 0.0) + v
        out_a[(string(pb,"|",i),a)] = get(out_a, (string(pb,"|",i),a), 0.0) + v
    end
    return out_pb, out_a
end

function _table_from_group2(alpha::Dict{String,Any}, group::String, keys1, keys2)
    (isempty(keys1) || isempty(keys2)) && return Dict{Tuple{String,String},Float64}()
    haskey(alpha, group) || error("Missing Excel-derived alpha group: $group")
    g = _strdict(alpha[group])
    out = Dict{Tuple{String,String},Float64}()
    missing = String[]
    for k1 in keys1, k2 in keys2
        key = string(k1,"|",k2)
        if haskey(g, key)
            out[(String(k1),String(k2))] = _asfloat(g[key], NaN)
        else
            push!(missing, key)
        end
    end
    isempty(missing) || error("Missing Excel-derived alpha[$group] entries: $(join(missing, ", "))")
    return out
end

function _table_from_group_activity_component(alpha::Dict{String,Any}, group::String, activities, components)
    return _table_from_group2(alpha, group, activities, components)
end

function _production_scalar_groups(data::EnvData)
    s = data.sets
    raw = _activity_component_values(data)
    out = Dict{String,Any}()
    out["crop_va"] = _component_share_by_activity(raw, s.acr, ["LAB1","VA1"]; allow_zero=true, group="crop_va")
    out["crop_va1"] = _component_share_by_activity(raw, s.acr, ["ND2","VA2"]; allow_zero=true, group="crop_va1")
    out["crop_va2"] = _component_share_by_activity(raw, s.acr, ["KEF","LAND"]; allow_zero=true, group="crop_va2")
    out["def_va"] = _component_share_by_activity(raw, default_activities(s), ["LAB1","VA1"]; allow_zero=true, group="def_va")
    out["def_va1"] = _component_share_by_activity(raw, default_activities(s), ["KEF","VA2"]; allow_zero=true, group="def_va1")
    out["livestock_va"] = _component_share_by_activity(raw, s.alv, ["LAB1","VA1","VA2"]; allow_zero=true, group="livestock_va")
    out["livestock_va1"] = _component_share_by_activity(raw, s.alv, ["KEF","VA2"]; allow_zero=true, group="livestock_va1")
    out["livestock_va2"] = _component_share_by_activity(raw, s.alv, ["FEED","LAND"]; allow_zero=true, group="livestock_va2")
    out["energy_top"] = _component_share_by_activity(raw, s.a, ["ELY","NELY"]; allow_zero=true, group="energy_top")
    out["kef"] = _component_share_by_activity(raw, s.a, ["ENERGY","KF","KSW","NRS"]; allow_zero=true, group="kef")
    out["ks"] = _component_share_by_activity(raw, s.a, ["CAP","LAB2"]; allow_zero=true, group="ks")
    out["ksw"] = _component_share_by_activity(raw, s.a, ["KS","WAT"]; allow_zero=true, group="ksw")
    out["nely"] = _component_share_by_activity(raw, s.a, ["COA","OLG"]; allow_zero=true, group="nely")
    out["olg"] = _component_share_by_activity(raw, s.a, ["GAS","OIL"]; allow_zero=true, group="olg")
    out["top"] = _component_share_by_activity(raw, s.a, ["ND1","VA"]; allow_zero=true, group="top")
    out["xp"] = _component_share_by_activity(raw, s.a, ["XGHG","XPX"]; allow_zero=true, group="xp")
    return out
end

function _power_block_from_activity(activity::AbstractString, pbs)
    # Infer a power-block label from Excel activity names when the workbook has
    # generation activities but no explicit power-block table.  This is not an
    # equal/default share: the resulting shares are still weighted by Excel
    # benchmark make/output values for the mapped generation activities.
    a = uppercase(String(activity))
    pbset = Set(uppercase.(String.(pbs)))
    if ("PEAK" in pbset) && (occursin("GAS", a) || occursin("OIL", a) || occursin("DIESEL", a))
        return first(String(pb) for pb in pbs if uppercase(String(pb)) == "PEAK")
    elseif "BASE" in pbset
        return first(String(pb) for pb in pbs if uppercase(String(pb)) == "BASE")
    elseif !isempty(pbs)
        return String(first(pbs))
    else
        return ""
    end
end

function _sum_power_generation_by_block(data::EnvData)
    s = data.sets
    out = Dict{String,Float64}()
    make = get(data.tables, "make", DataFrame())
    if make isa DataFrame && !isempty(make) && all(sym -> sym in propertynames(make), [:activity, :product, :value])
        elyset = Set(String.(s.ely))
        elyaset = Set(String.(s.elya))
        for row in eachrow(make)
            ismissing(row[:activity]) && continue
            ismissing(row[:product]) && continue
            a = String(row[:activity])
            p = String(row[:product])
            (a in elyaset && p in elyset) || continue
            pb = _power_block_from_activity(a, s.pb)
            pb == "" && continue
            out[pb] = get(out, pb, 0.0) + max(_asfloat(row[:value], 0.0), 0.0)
        end
    end
    return out
end

function _excel_alpha_shares(data::EnvData)
    s = data.sets
    out = Dict{String,Any}()

    use_by_product = _sum_use_by_product(data)
    make_by_product = _sum_make_by_product(data)
    make_by_activity = _sum_make_by_activity(data)
    fd_all = _sum_final_demand_by_product(data)
    fd_hh = _sum_final_demand_by_product(data; fd_filter=Set(["HH", "HOU", "HOUSEHOLD"]))
    waste_by_product = _sum_waste_by_product(data)
    actual_by_product = Dict{String,Float64}()
    _add_values!(actual_by_product, make_by_product)
    _add_values!(actual_by_product, use_by_product)
    _add_values!(actual_by_product, fd_all)
    fac = _sum_factor_demand_by_factor(data)
    cap_by_activity = _sum_factor_demand_by_activity(data; factors=s.cap)
    land_by_activity = _sum_factor_demand_by_activity(data; factors=s.lnd)
    water_by_activity = _sum_factor_demand_by_activity(data; factors=s.wat)

    out["gamma_p"] = _make_gamma_by_activity(data)
    out["alpha_s"] = _make_alpha_by_product(data)
    out["alpha_i"] = _positive_share_dict(isempty(fd_hh) ? fd_all : fd_hh, s.i; group="alpha_i")
    out["alpha_fd"] = _positive_share_dict(fd_all, s.i; group="alpha_fd")
    out["io"] = _use_share_by_activity(data, setdiff(s.i, s.nrg); group="io")
    out["io2"] = deepcopy(out["io"])
    out["energy"] = _use_share_by_activity(data, s.nrg; group="energy")
    out["lab1"] = _factor_share_by_activity(data, s.ul; group="lab1")
    out["lab2"] = _factor_share_by_activity(data, s.sl; group="lab2")
    out["water"] = _factor_share_by_activity(data, s.wat; group="water")
    out["alpha_mg"] = _positive_share_dict(use_by_product, s.i; group="alpha_mg")

    # Actual-consumption and waste split.  The numerator data are taken only
    # from Excel benchmark flows.  If no waste table is present in Excel, the
    # recorded waste value is zero, so alpha_ac=1 and alpha_aw=0 for products
    # that have positive benchmark make/use/final-demand flows.
    out["alpha_ac"] = _actual_waste_share_dict(actual_by_product, waste_by_product, s.i; group="alpha_ac")
    out["alpha_aw"] = _actual_waste_share_dict(actual_by_product, waste_by_product, s.i; group="alpha_aw")

    # Trade/agent shares derived from Excel SAM/use/final-demand flows.
    agent_abs = _agent_absorption_values(data)
    out["gamma_aa"] = _positive_share_dict(agent_abs, s.aa; group="gamma_aa")
    out["alpha_w"] = _positive_share_dict(_sum_make_by_region(data), s.r; group="alpha_w")
    out["alpha_tt"] = _positive_share_dict(_sum_absorption_by_region(data), s.r; group="alpha_tt")
    out["alpha_wa"] = _agent_region_share_table(data, s.r, s.aa; group="alpha_wa")
    dme = _domestic_import_export_values(data)
    dm = _positive_share_dict(dme, ["D", "M"]; group="alpha_dm")
    de = _positive_share_dict(dme, ["D", "E"]; group="gamma_de")
    out["alpha_dt"] = Dict("D" => dm["D"])
    out["alpha_mt"] = Dict("M" => dm["M"])
    out["alpha_d"] = Dict("D" => dm["D"])
    out["alpha_m"] = Dict("M" => dm["M"])
    out["gamma_d"] = Dict("D" => de["D"])
    out["gamma_e"] = Dict("E" => de["E"])
    merge!(out, _production_scalar_groups(data))

    # Electricity supply shares. These are derived only from Excel benchmark
    # make/use data and are limited to the sets actually used by supply.jl.
    # If an optional set such as etd is empty, the corresponding share table is
    # empty and no default/equal-share values are introduced.
    begin
        pb_by_e, elya_by_pbe = _power_generation_by_block_product_activity(data)
        out["alpha_pb"] = _component_share_by_activity(pb_by_e, s.ely, s.pb; group="alpha_pb")
        # alpha_elya is indexed as pb|ely|activity and normalized within each pb/ely bundle.
        tmp_elya = Dict{String,Float64}()
        for e in s.ely, pb in s.pb
            pbe = string(pb,"|",e)
            vals = Dict{String,Float64}(String(a)=>get(elya_by_pbe, (pbe,String(a)), 0.0) for a in s.elya)
            total = sum(Base.values(vals))
            if total > 0.0
                for a in s.elya
                    tmp_elya[string(pb,"|",e,"|",a)] = vals[String(a)] / total
                end
            end
        end
        out["alpha_elya"] = tmp_elya
        out["alpha_etd"] = _component_share_by_product(_sum_make_by_activity_product(data), s.ely, s.etd; group="alpha_etd")
        out["alpha_pow"] = _positive_share_dict_or_empty(make_by_product, s.ely; group="alpha_pow")
    end

    # Household/final-demand commodity shares. These are computed only where the
    # Excel commodity sets overlap with the requested model sets.
    out["alpha_c"] = _positive_share_dict(fd_all, s.k; group="alpha_c")
    # D-9:D-11 index alpha_cnnrg/alpha_cnrg over every consumer good k.
    # Use Excel final-demand values to compute the non-energy and energy shares,
    # and fill the opposite side of each Excel set split with explicit zeros so
    # every k has an entry without introducing equal-share/default values.
    out["alpha_cnnrg"] = _share_dict_with_zeros(fd_all, setdiff(s.k, s.nrg), s.k; group="alpha_cnnrg")
    out["alpha_cnrg"] = _share_dict_with_zeros(fd_all, intersect(s.k, s.nrg), s.k; group="alpha_cnrg")

    # Activity allocation shares for factor/resource supply blocks.
    out["capital_supply"] = _positive_share_dict(cap_by_activity, s.a; group="capital_supply")
    out["land_activity"] = _positive_share_dict(land_by_activity, s.a; group="land_activity")
    out["water_activity"] = _positive_share_dict(water_by_activity, s.a; group="water_activity")

    # Land and water supply-tree shares from observed Excel factor demand.
    land_crop = _sum_factor_by_activity_set(data, s.acr, s.lnd)
    land_pasture = _sum_factor_by_activity_set(data, s.alv, s.lnd)
    out["land_top"] = _share_dict_with_zeros(Dict("CROP"=>land_crop, "PASTURE"=>land_pasture), ["CROP", "PASTURE"], union(s.lb, ["XNLB"]); group="land_top")
    out["land_nlb"] = _positive_share_dict(Dict("CROP"=>land_crop, "PASTURE"=>land_pasture), setdiff(s.lb, ["XNLB"]); group="land_nlb")
    wat_total = get(fac, "WAT", 0.0)
    out["water_top"] = _share_dict_with_zeros(Dict("WAT"=>wat_total), ["WAT"], ["WAT", "XWAT"]; group="water_top")
    wat_irr = _sum_factor_by_activity_set(data, s.acr, s.wat)
    wat_nonirr = max(wat_total - wat_irr, 0.0)
    out["water_second"] = _positive_share_dict(Dict("IRR"=>wat_irr, "NONIRR"=>wat_nonirr), s.wbnd; group="water_second")

    return out
end


function _merge_default!(d::Dict{String,Any}, key::String, value)
    haskey(d, key) || (d[key] = value)
    return d[key]
end

function _table_from_group(alpha::Dict{String,Any}, group::String, keys)
    isempty(keys) && return Dict{String,Float64}()
    haskey(alpha, group) || error("Missing Excel-derived alpha group: $group")
    g = _strdict(alpha[group])
    out = Dict{String,Float64}()
    missing = String[]
    for k0 in keys
        k = String(k0)
        if haskey(g, k)
            out[k] = _asfloat(g[k], NaN)
        else
            push!(missing, k)
        end
    end
    isempty(missing) || error("Missing Excel-derived alpha[$group] entries: $(join(missing, ", "))")
    return out
end

function _scalar_from_group(alpha::Dict{String,Any}, group::String, item::String)
    haskey(alpha, group) || error("Missing Excel-derived alpha group: $group")
    g = _strdict(alpha[group])
    haskey(g, item) || error("Missing Excel-derived alpha[$group][$item]")
    return _asfloat(g[item], NaN)
end

function precompute_parameters(data::EnvData, cal::EnvCalibration)
    s = data.sets
    n_i = max(length(s.i), 1); n_a = max(length(s.a), 1); n_k = max(length(s.k), 1)
    n_r = max(length(s.r), 1); n_nrg = max(length(s.nrg), 1); n_ul = max(length(s.ul), 1)
    n_sl = max(length(s.sl), 1); n_wat = max(length(s.wat), 1)
    n_pb = max(length(s.pb), 1); n_etd = max(length(s.etd), 1); n_elya = max(length(s.elya), 1)

    # Alpha/share parameters are computed strictly from Excel benchmark tables.
    # Do not use calibrated equal-share placeholders or hard-coded defaults here.
    alpha = _excel_alpha_shares(data)
    sigma = _strdict(cal.sigma)
    lambda = _strdict(cal.lambda)
    taxes = _strdict(cal.taxes)
    benchmark = _strdict(cal.benchmark)
    emissions = _strdict(cal.emissions)
    climate = _strdict(cal.climate)

    # Alpha tables above are Excel-derived only; missing benchmark flows now raise errors.

    for (k, v) in _default_sigma(); _merge_default!(sigma, k, v); end

    for (k, v) in ["omega_s"=>4.0, "sigma_el"=>0.0, "sigma_pow"=>3.0, "sigma_mt"=>2.0, "sigma_wa"=>4.0, "sigma_w"=>4.0, "omega_x"=>2.0, "omega_w"=>2.0, "sigma_mg"=>1.0,
                   "nu_c"=>0.5, "nu_nnrg"=>0.5, "nu_e"=>0.5, "nu_nely"=>0.5, "nu_olg"=>0.5, "nu_carrier"=>0.5, "sigma_ac"=>0.5, "sigma_fd"=>0.0,
                   "eps_ror"=>1.0, "omega_m"=>0.0, "omega_rwg"=>0.0, "omega_rwue"=>0.0, "omega_rwp"=>1.0, "omega_k"=>1.0, "eta_I"=>1.0, "eta_t"=>1.0,
                   "eta_w"=>1.0, "omega_t"=>1.0, "omega_nlb"=>1.0, "omega_lb"=>1.0, "omega_w1"=>1.0, "omega_w2"=>1.0, "epsilon_h2ob"=>0.0,
                   "eta_h2ob"=>1.0, "eta_nrs_lo"=>1.0, "eta_nrs_hi"=>1.0, "eta_nrs"=>1.0]
        _merge_default!(sigma, k, v)
    end
    for (k, v) in _default_climate(); _merge_default!(climate, k, v); end

    for k in ["lambda_f","lambda_ep","lambda_io","lambda_xp","lambda_ghg","lambda_s","lambda_pow","lambda_pb","lambda_ac","lambda_aw","lambda_w","lambda_mg","gamma_eda","gamma_esd","gamma_ese","gamma_ew","gamma_edd","gamma_edm","chi_Emi","phi_Emi","chi_Cap","chi_m"]
        _merge_default!(lambda, k, 1.0)
    end
    for (k, v) in ["delta"=>0.05, "delta_f"=>0.05, "r"=>0.04, "RGDPpc0"=>1.0, "beta_c"=>1.0, "P_sav"=>1.0, "chi_s"=>1.0,
                   "grKMin"=>-0.05, "grKMax"=>0.10, "grKTrend"=>0.03, "chi_k"=>1.0, "Rn"=>0.04, "chi_welf"=>1.0,
                   "kappa_nrs"=>30.0, "chi_rw"=>1.0, "chi_t"=>1.0, "gamma_tl"=>1.0, "TLandMax"=>10.0,
                   "chi_h2o"=>1.0, "gamma_tw"=>1.0, "TH2OMax"=>10.0, "alpha_h2ob"=>1.0, "lambda_h2ob"=>1.0,
                   "lambda_nrs"=>1.0, "chi_nrs"=>1.0, "chi_w_nrs"=>1.0, "chi_nrsp"=>1.0]
        _merge_default!(taxes, k, v)
    end
    for k in ["tau_uc","tau_x","tau_a","tau_ad","tau_am","tau_m","tau_ma","tau_e","tau_ntm","tau_f","tau_c","tau_d","tau_w","tau_waste","tau_p","tau_v","kappa_h","kappa_f","chi_f","chi_h","chi_r","chi_OO","chi_OI","chi_hNTM","eta_ODA","rho_Emi","rho_Emid","rho_Emim","rho_Emi_d","rho_Emi_m","tau_Emi","gamma_c","mu_s","aps","zeta_mg","chi_sf","delta_k"]
        _merge_default!(taxes, k, 0.0)
    end

    PAR = EnvParameters()
    PAR[:alpha] = alpha; PAR[:sigma] = sigma; PAR[:lambda] = lambda; PAR[:taxes] = taxes
    PAR[:benchmark] = benchmark; PAR[:emissions] = emissions; PAR[:climate] = climate
    PAR[:controls] = Dict{String,Any}(String(k)=>v for (k,v) in data.par)

    # Scalars from calibration groups. Equation files read these directly.
    for (k,v) in sigma; PAR[Symbol(k)] = _asfloat(v, 0.0); end
    for (k,v) in lambda; PAR[Symbol(k)] = _asfloat(v, 1.0); end
    for (k,v) in taxes; PAR[Symbol(k)] = _asfloat(v, 0.0); end
    for (k,v) in climate; PAR[Symbol(k)] = _asfloat(v, 0.0); end

    # Table parameters by equation-local names. Every alpha table below must
    # already have been computed from Excel benchmark data.
    PAR[:alpha_energy] = _table_from_group2(alpha, "energy", s.a, s.nrg)
    PAR[:alpha_io] = _table_from_group2(alpha, "io", s.a, setdiff(s.i, s.nrg))
    PAR[:alpha_io2] = _table_from_group2(alpha, "io2", s.a, setdiff(s.i, s.nrg))
    PAR[:alpha_lab1] = _table_from_group2(alpha, "lab1", s.a, s.ul)
    PAR[:alpha_lab2] = _table_from_group2(alpha, "lab2", s.a, s.sl)
    PAR[:alpha_water] = _table_from_group2(alpha, "water", s.a, s.wat)
    PAR[:gamma_p_val] = _table_from_group2(alpha, "gamma_p", s.a, s.i)
    PAR[:alpha_s_val] = _table_from_group2(alpha, "alpha_s", s.a, s.i)
    PAR[:alpha_etd_val] = _table_from_group2(alpha, "alpha_etd", s.etd, s.ely)
    PAR[:alpha_pow_val] = _table_from_group(alpha, "alpha_pow", s.ely)
    PAR[:alpha_pb_val] = _table_from_group2(alpha, "alpha_pb", s.ely, s.pb)
    PAR[:alpha_elya_val] = Dict((String(pb),String(e),String(a)) => _scalar_from_group(alpha, "alpha_elya", string(pb,"|",e,"|",a)) for pb in s.pb, e in s.ely, a in s.elya if haskey(_strdict(alpha["alpha_elya"]), string(pb,"|",e,"|",a)))
    PAR[:alpha_c] = _table_from_group(alpha, "alpha_c", s.k)
    PAR[:alpha_cnnrg] = _table_from_group(alpha, "alpha_cnnrg", s.k)
    PAR[:alpha_cnrg] = _table_from_group(alpha, "alpha_cnrg", s.k)
    PAR[:alpha_i] = _table_from_group(alpha, "alpha_i", s.i)
    PAR[:alpha_fd] = _table_from_group(alpha, "alpha_fd", s.i)
    PAR[:alpha_ac] = _table_from_group(alpha, "alpha_ac", s.i)
    PAR[:alpha_aw] = _table_from_group(alpha, "alpha_aw", s.i)
    PAR[:alpha_aa] = _table_from_group(alpha, "gamma_aa", s.aa)
    PAR[:alpha_w] = _table_from_group(alpha, "alpha_w", s.r)
    PAR[:alpha_mg] = _table_from_group(alpha, "alpha_mg", s.i)
    PAR[:alpha_tt] = _table_from_group(alpha, "alpha_tt", s.r)

    # Dynamic/set-specific lambda tables.
    PAR[:lambda_s_val] = Dict(i => _asfloat(get(lambda, "lambda_s_" * String(i), get(lambda, "lambda_s", 1.0)), 1.0) for i in s.i)
    PAR[:lambda_pow_val] = Dict(pb => _asfloat(get(lambda, "lambda_pow_" * String(pb), get(lambda, "lambda_pow", 1.0)), 1.0) for pb in s.pb)
    PAR[:lambda_pb_val] = Dict(a => _asfloat(get(lambda, "lambda_pb_" * String(a), get(lambda, "lambda_pb", 1.0)), 1.0) for a in s.a)

    # Two-key table from Excel-derived alpha data.
    PAR[:alpha_wa] = Dict((r,aa) => _scalar_from_group(alpha, "alpha_wa", string(r,"|",aa)) for r in s.r, aa in s.aa)

    # Scalar alphas used in production/trade equations.
    scalar_specs = [
        (:alpha_crop_va_LAB1,"crop_va","LAB1"),(:alpha_crop_va_VA1,"crop_va","VA1"),(:alpha_crop_va1_ND2,"crop_va1","ND2"),(:alpha_crop_va1_VA2,"crop_va1","VA2"),(:alpha_crop_va2_KEF,"crop_va2","KEF"),(:alpha_crop_va2_LAND,"crop_va2","LAND"),
        (:alpha_def_va_LAB1,"def_va","LAB1"),(:alpha_def_va_VA1,"def_va","VA1"),(:alpha_def_va1_KEF,"def_va1","KEF"),(:alpha_def_va1_VA2,"def_va1","VA2"),
        (:alpha_energy_top_ELY,"energy_top","ELY"),(:alpha_energy_top_NELY,"energy_top","NELY"),(:alpha_kef_ENERGY,"kef","ENERGY"),(:alpha_kef_KF,"kef","KF"),(:alpha_kef_KSW,"kef","KSW"),(:alpha_kef_NRS,"kef","NRS"),
        (:alpha_ks_CAP,"ks","CAP"),(:alpha_ks_LAB2,"ks","LAB2"),(:alpha_ksw_KS,"ksw","KS"),(:alpha_ksw_WAT,"ksw","WAT"),
        (:alpha_livestock_va_LAB1,"livestock_va","LAB1"),(:alpha_livestock_va_VA1,"livestock_va","VA1"),(:alpha_livestock_va_VA2,"livestock_va","VA2"),(:alpha_livestock_va1_KEF,"livestock_va1","KEF"),(:alpha_livestock_va1_VA2,"livestock_va1","VA2"),(:alpha_livestock_va2_FEED,"livestock_va2","FEED"),(:alpha_livestock_va2_LAND,"livestock_va2","LAND"),
        (:alpha_nely_COA,"nely","COA"),(:alpha_nely_OLG,"nely","OLG"),(:alpha_olg_GAS,"olg","GAS"),(:alpha_olg_OIL,"olg","OIL"),(:alpha_top_ND1,"top","ND1"),(:alpha_top_VA,"top","VA"),(:alpha_water_WAT,"water","WAT"),(:alpha_xp_XGHG,"xp","XGHG"),(:alpha_xp_XPX,"xp","XPX"),
        (:alpha_dt,"alpha_dt","D"),(:alpha_mt,"alpha_mt","M"),(:alpha_d,"alpha_d","D"),(:alpha_m,"alpha_m","M"),(:gamma_d,"gamma_d","D"),(:gamma_e,"gamma_e","E")
    ]
    for (sym, group, item) in scalar_specs
        if group in ["alpha_dt","alpha_mt","alpha_d","alpha_m","gamma_d","gamma_e"]
            PAR[sym] = _scalar_from_group(alpha, group, item)
        else
            acts = occursin("crop", group) ? s.acr : occursin("livestock", group) ? s.alv : occursin("def_", group) ? default_activities(s) : s.a
            PAR[sym] = Dict(String(a) => _scalar_from_group(alpha, group, string(a,"|",item)) for a in acts)
        end
    end

    # Factors-specific tables.
    land_rest = setdiff(s.lb, ["XNLB"])
    wb1s = ["WAT", "XWAT"]
    wb2s = s.wbnd
    PAR[:alpha_capital_supply] = _table_from_group(alpha, "capital_supply", s.a)
    PAR[:alpha_land_top] = _table_from_group(alpha, "land_top", union(s.lb, ["XNLB"]))
    PAR[:alpha_land_nlb] = _table_from_group(alpha, "land_nlb", land_rest)
    PAR[:alpha_land_activity] = _table_from_group(alpha, "land_activity", s.a)
    PAR[:alpha_water_top] = _table_from_group(alpha, "water_top", wb1s)
    PAR[:alpha_water_second] = _table_from_group(alpha, "water_second", wb2s)
    PAR[:alpha_water_activity] = _table_from_group(alpha, "water_activity", s.a)


    return PAR
end

"""Return the precomputed EnvCGE LINKAGE-style parameter table, computing and caching it if needed."""
function parameters(data::EnvData, cal::EnvCalibration)
    cached = safeget(data.par, "PAR", nothing)
    if cached isa Dict{Symbol,Any}
        return cached
    end
    PAR = precompute_parameters(data, cal)
    data.par["PAR"] = PAR
    return PAR
end
