# === Function usage ===
# PATHSolver equation-to-variable mapping and consistency checks.
# Usage:
#   model = build_model(data, cal; audit_mapping=true)
#   report = path_mapping_report(model)
#   assert_path_ready!(model; require_square=false)
#   assert_path_ready!(model; require_square=true)  # before solve!
#
# Edit equation_variable_map(data) when adding/removing equation numbers.
# ======================

# PATHSolver mapping and consistency checks.
#
# PATH solves a square mixed-complementarity problem.  This file keeps a
# single registry that links every documented equation number to the variable
# family that closes that equation in the JuMP/PATH model.  The audit routines
# are intentionally strict: solve! will not call PATH if an equation number is
# missing a mapping, if a mapping refers to an undeclared variable family, or if
# the generated JuMP model is not square after excluding variable-bound sets.

function equation_variable_map(data::EnvData)
    m = OrderedDict{String,String}()
    # Production block P-1:P-48
    prod_vars = [
        "XP", "PXv", "XPX", "XGHG", "UC", "ND1", "VA", "PXP",
        "VA1", "VA2", "LAB1", "KEF", "ND2", "XF", "PVA", "PVA1", "PVA2",
        "KF", "XNRG", "PKEF", "KSW", "XF", "PKF", "KS", "XWAT", "PKSW",
        "K", "LAB2", "PKS", "XF", "PLAB1", "PLAB2", "XA", "PND1", "PND2",
        "XF", "PWAT", "XAely", "XNELY", "PNRG", "XAcoa", "XOLG", "PNELY",
        "XAoil", "XAgas", "POLG", "XA", "PAely"
    ]
    for (k, v) in enumerate(prod_vars); m["P-$k"] = v; end

    supply_vars = ["X","XP","PP","X","PS","X","XPOW","PS","XPB","PPOWN","PPOW","X","PPBN","PPB"]
    for (k, v) in enumerate(supply_vars); m["S-$k"] = v; end

    income_vars = ["DeprY","ntmY","YQTF","TrustY","YQHT","Remit","ODAOut","ODAGbl","ODAIn","YH","YD","YGOV","YGOV","YGOV","YGOV","YGOV","YGOV","YGOV","YGOV","YFD"]
    for (k, v) in enumerate(income_vars); m["Y-$k"] = v; end

    demand_vars = ["Ysup","XC","u","μc","ZC","shr","ZC","shr","XCnnrg","XCnrg","PC","XAh","PCnnrg","XCely","XCnely","PCnrg","XCcoa","XColg","PCnely","XCoil","XCgas","PColg","XAh","PCely","Sh","Sh","XAc","XAw","PACC","PAc","PAw","PAh","XA","PFD","QFD","YFD","XFD"]
    for (k, v) in enumerate(demand_vars); m["D-$k"] = v; end

    trade_vars = ["XAT","XDTd","XMT","PAT","PA","XD","XM","PA","PD","PM","XDTd","XMT","XWd","PMT","XWa","PMa","PDMa","XWd","XDTs","XET","PS","XWs","PET","PWE","PWM","PDM","XWMG","XMG","PWMG","XTMG","XTT","PTMG"]
    for (k, v) in enumerate(trade_vars); m["T-$k"] = v; end

    # T-6:T-10 and T-15:T-18 are the ENVISAGE agent-sourcing/MRIO equations
    # (trade.jl's ArmFlag != 0 branch). trade.jl/income.jl only declare XD, XM,
    # PD, PM, PMa, PDMa (and, unless ifMRIO, XWa) when that branch is actually
    # built. Since T-2/T-11 and T-3/T-12 already reuse the same variable across
    # both sourcing regimes in this table, extend that precedent here rather
    # than pointing these labels at variables that do not exist under the
    # active national-sourcing closure: reuse each inactive equation's national-
    # sourcing counterpart so the mapping always names a variable the current
    # build actually declares.
    inactive = _inactive_closure_families(data)
    if "XD" in inactive;   m["T-6"]  = "XDTd"; end
    if "XM" in inactive;   m["T-7"]  = "XMT";  end
    if "PD" in inactive;   m["T-9"]  = "PDT";  end
    if "PM" in inactive;   m["T-10"] = "PMT";  end
    if "XWa" in inactive;  m["T-15"] = "XWd";  end
    if "PMa" in inactive;  m["T-16"] = "PMT";  end
    if "PDMa" in inactive; m["T-17"] = "PDM";  end

    m["E-1"] = "XDTd"
    m["E-2"] = "XWd"

    # Complementarity pairing of the factor block.  F-15/F-16 are the two
    # documented inequalities (F-15 is complementary to RR <= 1, F-16 to
    # Khi >= 0, documentation p. 47); F-17 closes Klo.  The three factor-market
    # clearing conditions F-36 (land), F-39 (natural resources) and F-51 (water)
    # are what price the corresponding factor, so they pair with PF.
    factor_vars = [
        "LDz", "Wres", "We", "UEz", "PF", "Wa", "piUrb", "Wt", "piS", "LSz", "TLs",
        "K", "TR", "Kv", "RR", "Khi", "Klo", "TR", "PK", "kxRat", "XPv", "XPv", "XF", "PF",
        "TLand", "XLB", "XNLB", "PTLandN", "PTLand", "XLB", "PNLBN", "PNLB", "Lands", "PLBN", "PLB", "PF",
        "etaNRS", "XNRSs", "PF",
        "TH2O", "TH2Om", "H2OBnd", "PTH2On", "PTH2O", "H2OBnd", "PH2OBndN", "PH2OBnd",
        "H2Os", "PH2OBndN", "PH2OBnd", "PF", "H2OBndd", "H2OBnd",
        "PFp", "PKp"
    ]
    for (k, v) in enumerate(factor_vars); m["F-$k"] = v; end

    closure_vars = [
        # M-1:M-31, including duplicate closure cases that use the same variable family.
        "GDPMP", "PGDPMP", "RGDPMP", "RGDPpc", "gy", "KLRat",
        "Sg", "RSg", "Sf", "Sf", "PWsav", "Rg", "phi", "Sf",
        "TKe", "R", "Rc", "Re", "Rd", "YFD", "Re", "DeltaRoR",
        "grK", "XFD", "Sf", "PNUM", "EV", "CV", "EVG", "CVG", "SWF"
    ]
    for (k, v) in enumerate(closure_vars); m["M-$k"] = v; end

    # Emissions are stored internally as EM-* to avoid colliding with goods-market
    # equilibrium E-1:E-2.  The printed ENVISAGE labels in src/emissions.jl are E-1:E-8.
    emission_vars = ["Emi", "Emi", "Emi", "EmiTot", "EmiGbl", "τEmiQ", "τEmi", "EmiQY"]
    for (k, v) in enumerate(emission_vars); m["EM-$k"] = v; end

    return m
end

"""
Variable families that ENVISAGE's trade/income blocks only declare and use
under agent sourcing (ArmFlag != 0, trade.jl T-6:T-12/T-15:T-18 and the
corresponding income.jl Y-14/Y-15/Y-18 branches) or MRIO (ifMRIO, income.jl
Y-2/Y-15).  `equation_variable_map` lists a fixed T-1:T-32 label set covering
both the national-sourcing and agent-sourcing document cases, but only one
branch is ever built into the JuMP model for a given closure.  Under the
inactive branch these families are legitimately undeclared (income.jl/trade.jl
guard their declaration on the same ArmFlag/ifMRIO condition), not a mapping
bug, so `path_mapping_report` excludes them from `undeclared_mapped_variable_families`
when the active closure does not need them.
"""
const _ARMFLAG_ONLY_FAMILIES = Set(["XD", "XM", "PD", "PM", "PMa", "PDMa"])
const _MRIO_OR_ARMFLAG_FAMILIES = Set(["XWa"])

function _inactive_closure_families(data::EnvData)
    ArmFlag = Int(get(data.par, "ArmFlag", 0))
    ifMRIO  = Bool(get(data.par, "ifMRIO", false))
    inactive = Set{String}()
    if ArmFlag == 0
        union!(inactive, _ARMFLAG_ONLY_FAMILIES)
        ifMRIO || union!(inactive, _MRIO_OR_ARMFLAG_FAMILIES)
    end
    # ZC is the CDE auxiliary variable of D-5:D-7; demand.jl only declares it in
    # the CDE branch, so under any other demand system it is legitimately absent.
    if uppercase(String(get(data.par, "demand_system", "LES"))) != "CDE"
        push!(inactive, "ZC")
    end
    # The ENVISAGE water-bundle hierarchy F-42:F-53 is keyed on the document's
    # bundle labels; with an aggregation that uses none of them factors.jl
    # declares no bundle variables at all and those equations are not generated.
    if isempty(unique(vcat(_wb1(data.sets), _wb2(data.sets), _wbx(data.sets))))
        union!(inactive, ["H2OBnd", "H2OBndd", "PH2OBnd", "PH2OBndN"])
    end
    return inactive
end

function _declared_variable_bases(jm::JuMP.Model)
    bases = Set{String}()
    for v in JuMP.all_variables(jm)
        nm = JuMP.name(v)
        isempty(nm) && continue
        b = split(nm, '[')[1]
        push!(bases, b)
    end
    return bases
end


function _path_free_variable_count(jm::JuMP.Model)
    n = 0
    for v in JuMP.all_variables(jm)
        fixed = try JuMP.is_fixed(v) catch; false end
        fixed || (n += 1)
    end
    return n
end

function _path_nonbound_constraint_count(jm::JuMP.Model)
    n = JuMP.num_constraints(jm; count_variable_in_set_constraints=false)
    if n == 0
        try
            nlp_n = _ps_nonlinear_constraint_count(jm)
            if nlp_n > 0
                return nlp_n
            end
        catch
            try
                if isdefined(JuMP, :num_nonlinear_constraints)
                    return Int(getfield(JuMP, :num_nonlinear_constraints)(jm))
                end
            catch
            end
        end
    end
    return n
end

function path_mapping_report(em::EnvModel)
    registry = em.equations
    mapping = equation_variable_map(em.data)
    declared = em.jump === nothing ? Set{String}() : _declared_variable_bases(em.jump)
    exogenous_hooks = Set{String}()
    mapped_vars = Set(values(mapping))
    missing_mapping = setdiff(Set(keys(registry)), Set(keys(mapping)))
    extra_mapping = setdiff(Set(keys(mapping)), Set(keys(registry)))
    inactive_families = _inactive_closure_families(em.data)
    undeclared_vars = setdiff(mapped_vars, union(declared, exogenous_hooks, inactive_families))
    # Fixed variables are pinned by their bounds and need no complementarity
    # function, so squareness is judged on the free variables.
    nvar = em.jump === nothing ? 0 : _path_free_variable_count(em.jump)
    ncon = em.jump === nothing ? 0 : _path_nonbound_constraint_count(em.jump)
    return Dict{String,Any}(
        "registry_equations" => length(registry),
        "mapped_equations" => length(mapping),
        "missing_mapping" => sort(collect(missing_mapping)),
        "extra_mapping" => sort(collect(extra_mapping)),
        "undeclared_mapped_variable_families" => sort(collect(undeclared_vars)),
        "variable_count" => nvar,
        "constraint_count_excluding_bounds" => ncon,
        "square_for_path" => nvar == ncon,
        "dynamic_and_climate_hooks" => sort(collect(exogenous_hooks)),
        "mapping" => mapping,
    )
end

function assert_path_ready!(em::EnvModel; require_square::Bool=true)
    rep = path_mapping_report(em)
    if !isempty(rep["missing_mapping"])
        error("PATH mapping is incomplete. Missing equation mappings: $(rep["missing_mapping"])")
    end
    if !isempty(rep["extra_mapping"])
        error("PATH mapping includes equations not in the registry: $(rep["extra_mapping"])")
    end
    if !isempty(rep["undeclared_mapped_variable_families"])
        error("PATH mapping refers to variable families that are not declared in the JuMP model: $(rep["undeclared_mapped_variable_families"])")
    end
    if require_square && !rep["square_for_path"]
        error("PATH requires a square MCP. Current model has $(rep["variable_count"]) free variables and $(rep["constraint_count_excluding_bounds"]) non-bound constraints. Add/remove closure equations or fix exogenous variables until these counts match. Use path_mapping_report(model) for details.")
    end
    em.solution["path_mapping_report"] = rep
    return rep
end
