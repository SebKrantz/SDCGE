# === PATH square-system diagnostics ===
# Purpose:
#   Identify which variable families are most likely preventing PATHSolver from
#   receiving a square MCP/NLP system.  Use after build_model(...; require_square=false).
#
# Typical use:
#   include("src/EnvCGE.jl")
#   using .EnvCGE
#   data = load_default_data()
#   cal  = calibrate(data)
#   diag = path_square_diagnostics(data, cal; outdir="reports/path_square")
#
# The data/calibration method builds a temporary unchecked model internally,
# runs all square diagnostics, and does not rely on variables from any outer scope.
# ================================

function _ps_base_name(nm::AbstractString)
    s = String(nm)
    isempty(s) && return "<anonymous>"
    parts = split(s, '[')
    return isempty(parts) ? "<anonymous>" : first(parts)
end

function _ps_head(v, n::Integer)
    n <= 0 && return eltype(v)[]
    isempty(v) && return eltype(v)[]
    return v[1:min(length(v), n)]
end

function _ps_var_family_counts(m::JuMP.Model)
    rows = Dict{String,Dict{String,Int}}()
    for v in JuMP.all_variables(m)
        b = _ps_base_name(JuMP.name(v))
        row = get!(rows, b, Dict("total"=>0, "fixed"=>0, "free"=>0))
        row["total"] += 1
        fixed = try JuMP.is_fixed(v) catch; false end
        if fixed
            row["fixed"] += 1
        else
            row["free"] += 1
        end
    end
    return rows
end

function _ps_nonlinear_constraint_count(m::JuMP.Model)
    # JuMP versions differ in whether @NLconstraint rows are exposed through
    # list_of_constraint_types/num_constraints.  PATH preflight must count them
    # when the model is still built with @NLconstraint equations.
    try
        if isdefined(JuMP, :num_nonlinear_constraints)
            return Int(getfield(JuMP, :num_nonlinear_constraints)(m))
        end
    catch
    end
    try
        if isdefined(JuMP, :all_nonlinear_constraints)
            return length(getfield(JuMP, :all_nonlinear_constraints)(m))
        end
    catch
    end
    try
        # Older JuMP keeps nonlinear constraints in an NLP model field.
        nlp = getfield(m, :nlp_model)
        return length(getfield(nlp, :constraints))
    catch
    end
    return 0
end

function _ps_constraint_family_counts(m::JuMP.Model)
    rows = Dict{String,Int}()
    total = 0
    for (F,S) in JuMP.list_of_constraint_types(m)
        # Variable-in-set constraints are bounds/fixes, not model equations for the square test.
        if F == JuMP.VariableRef
            continue
        end
        for c in JuMP.all_constraints(m, F, S)
            total += 1
            nm = try JuMP.name(c) catch; "" end
            b = _ps_base_name(nm)
            rows[b] = get(rows, b, 0) + 1
        end
    end
    nl_total = _ps_nonlinear_constraint_count(m)
    # Avoid double-counting if this JuMP version already reports nonlinear rows
    # through list_of_constraint_types.  The failure reported by the user had
    # total == 0, so the fallback is essential there.
    if total == 0 && nl_total > 0
        rows["<nonlinear_equations>"] = nl_total
        total = nl_total
    end
    return rows, total
end

function _ps_declared_variable_bases(m::JuMP.Model)
    return Set(keys(_ps_var_family_counts(m)))
end

function _ps_norm_closure_label(x)
    # Reuse the package closure normalizer when available.  Fallback is deliberately
    # conservative so this file can also be copied into older package versions.
    try
        return _norm_closure_var(x)
    catch
        raw = x isa AbstractDict ? String(get(x, "variable", "")) : String(x)
        u = uppercase(strip(raw))
        aliases = Dict(
            "NUMERAIRE"=>"PNUM", "CAB"=>"Sf", "SAVF"=>"Sf",
            "LS"=>"Ls", "TLS"=>"Ls", "LABSUP"=>"Ls",
            "TKS"=>"TKs", "KSUP"=>"TKs", "CAPSUP"=>"TKs",
            "TLAND"=>"TLand", "LANDSUP"=>"TLand",
            "CTAX"=>"τEmi", "CARBTAX"=>"τEmi", "CPRICE"=>"τEmi", "EMITAX"=>"τEmi",
            "ECAP"=>"EmiCap", "EMICAP"=>"EmiCap"
        )
        return get(aliases, u, strip(raw))
    end
end

function _ps_requested_closure_variables(data::EnvData)
    rules = get(data.par, "closure_rules", Any[])
    rows = Vector{Dict{String,Any}}()
    for rule in rules
        active = lowercase(strip(String(get(rule, "active", "TRUE")))) in ["true", "1", "yes", "y"]
        status = lowercase(strip(String(get(rule, "status", "fixed"))))
        raw = String(get(rule, "variable", ""))
        norm = _ps_norm_closure_label(rule)
        push!(rows, Dict(
            "raw"=>raw,
            "normalized"=>norm,
            "active"=>active,
            "status"=>status,
            "region"=>String(get(rule, "region", "ALL")),
            "agent"=>String(get(rule, "agent", "ALL")),
            "value"=>get(rule, "value", missing),
        ))
    end
    return rows
end

function _ps_sorted_pairs(d::Dict{String,<:Any}; bykey::Bool=false)
    pairs = collect(d)
    if bykey
        sort!(pairs, by=x->x[1])
    else
        sort!(pairs, by=x->x[2], rev=true)
    end
    return pairs
end



"""
    _ps_build_diagnostic_model(data, calib; kwargs...)

Internal helper used only by this diagnostics file.  It builds the EnvCGE JuMP
model with `require_square=false`, so diagnostics can inspect variables and
equations even when the final PATH system is not square.  This avoids calling
`build_model(...; require_square=true)` and therefore avoids recursive preflight
errors.
"""
function _ps_build_diagnostic_model(data::EnvData, calib::EnvCalibration;
    backend=:jump_path,
    optimizer_attributes::AbstractDict{String,<:Any}=Dict{String,Any}(),
    initialize::Bool=true,
    audit_mapping::Bool=true)

    return _build_model_unchecked(data, calib;
        backend=backend,
        optimizer_attributes=optimizer_attributes,
        initialize=initialize,
        audit_mapping=audit_mapping)
end


"""
    path_square_diagnostics(em::EnvModel; top::Int=50)

Return a dictionary that identifies likely reasons the model is not square for PATHSolver.
The most important fields are:

  * `square_gap_total_variables`: `num_variables - non_bound_constraints`
  * `square_gap_free_variables`: `non_fixed_variables - non_bound_constraints`
  * `mapped_but_undeclared`: equation mapping targets that are not declared
  * `declared_but_unmapped`: declared variable families that have no equation mapping
  * `active_closure_variables`: closure variables requested in the Excel workbook
  * `fixed_variable_families`: variable families fixed by closure or initialization
"""
function path_square_diagnostics(em::EnvModel; top::Int=50)
    m = em.jump
    m === nothing && error("EnvModel.jump is nothing. Build the JuMP model first.")

    var_counts = _ps_var_family_counts(m)
    con_counts, ncon = _ps_constraint_family_counts(m)
    nvar = sum(row["total"] for row in values(var_counts))
    nfixed = sum(row["fixed"] for row in values(var_counts))
    nfree = sum(row["free"] for row in values(var_counts))

    mapping = equation_variable_map(em.data)
    mapped = Set(values(mapping))
    declared = _ps_declared_variable_bases(m)
    mapped_but_undeclared = sort(collect(setdiff(mapped, declared)))
    declared_but_unmapped = sort(collect(setdiff(declared, mapped)))

    closure_rows = _ps_requested_closure_variables(em.data)
    active_closure = [r for r in closure_rows if r["active"] && r["status"] in ["fixed", "fix", "exogenous"]]
    active_closure_vars = sort(unique(String(r["normalized"]) for r in active_closure))
    closure_not_declared = sort(collect(setdiff(Set(active_closure_vars), declared)))

    fixed_families = Dict(k=>v["fixed"] for (k,v) in var_counts if v["fixed"] > 0)
    free_unmapped = Dict(k=>var_counts[k]["free"] for k in declared_but_unmapped if haskey(var_counts,k) && var_counts[k]["free"] > 0)
    fixed_mapped = Dict(k=>var_counts[k]["fixed"] for k in intersect(collect(mapped), collect(keys(var_counts))) if var_counts[k]["fixed"] > 0)

    suspects = Vector{Dict{String,Any}}()
    for (k,n) in _ps_sorted_pairs(free_unmapped)
        push!(suspects, Dict(
            "variable_family"=>k,
            "free_instances"=>n,
            "reason"=>"declared in JuMP but not used as a complementarity variable in equation_variable_map; add an equation mapping, fix it as closure, or remove the declaration"
        ))
    end
    for (k,n) in _ps_sorted_pairs(fixed_mapped)
        push!(suspects, Dict(
            "variable_family"=>k,
            "fixed_instances"=>n,
            "reason"=>"mapped variable family has fixed instances; if the square test uses total variables, these fixed variables can create a variables-vs-equations gap"
        ))
    end
    for k in mapped_but_undeclared
        push!(suspects, Dict(
            "variable_family"=>k,
            "reason"=>"equation_variable_map points to this family, but no JuMP variable with this base name is declared"
        ))
    end
    for k in closure_not_declared
        push!(suspects, Dict(
            "variable_family"=>k,
            "reason"=>"closure workbook requests this variable, but it is not declared in the model"
        ))
    end

    return Dict{String,Any}(
        "variable_count_total"=>nvar,
        "variable_count_fixed"=>nfixed,
        "variable_count_free"=>nfree,
        "constraint_count_excluding_bounds"=>ncon,
        "square_using_total_variables"=>nvar == ncon,
        "square_using_free_variables"=>nfree == ncon,
        "square_gap_total_variables"=>nvar - ncon,
        "square_gap_free_variables"=>nfree - ncon,
        "mapped_but_undeclared"=>mapped_but_undeclared,
        "declared_but_unmapped"=>declared_but_unmapped,
        "closure_not_declared"=>closure_not_declared,
        "active_closure_variables"=>active_closure_vars,
        "fixed_variable_families"=>Dict(k=>v for (k,v) in _ps_sorted_pairs(fixed_families)),
        "free_unmapped_variable_families"=>Dict(k=>v for (k,v) in _ps_sorted_pairs(free_unmapped)),
        "constraint_families_top"=>Dict(k=>v for (k,v) in _ps_head(_ps_sorted_pairs(con_counts), top)),
        "variable_families_top"=>Dict(k=>v for (k,v) in _ps_head(_ps_sorted_pairs(Dict(k=>v["total"] for (k,v) in var_counts)), top)),
        "suspects"=>suspects,
        "path_mapping_report"=>path_mapping_report(em),
    )
end

"""
    path_square_diagnostics(data::EnvData, calib::EnvCalibration; outdir=nothing, top=50, kwargs...)

Build a temporary model internally and run the full PATH square diagnostics.
Use this as the primary entry point when you want the diagnostics file itself to
perform the build before the application calls `build_model`.

Returns the diagnostic dictionary.  The temporary `EnvModel` used for counting is
stored under `diag["diagnostic_model"]` for advanced inspection.
"""
function path_square_diagnostics(data::EnvData, calib::EnvCalibration;
    backend=:jump_path,
    optimizer_attributes::AbstractDict{String,<:Any}=Dict{String,Any}(),
    initialize::Bool=true,
    audit_mapping::Bool=true,
    outdir=nothing,
    top::Int=50)

    em = _ps_build_diagnostic_model(data, calib;
        backend=backend,
        optimizer_attributes=optimizer_attributes,
        initialize=initialize,
        audit_mapping=audit_mapping)
    diag = outdir === nothing ? path_square_diagnostics(em; top=top) : write_path_square_report(em; outdir=outdir, top=top)
    diag["diagnostic_model"] = em
    return diag
end

function _ps_first_line(x)
    lines = split(String(x), '\n'; keepempty=false)
    return isempty(lines) ? "" : first(lines)
end

function _ps_write_csv(path::AbstractString, header::Vector{String}, rows::AbstractVector)
    open(path, "w") do io
        println(io, join(header, ","))
        for row in rows
            println(io, join([replace(string(x), '"'=>"'") for x in row], ","))
        end
    end
end

"""
    write_path_square_report(em::EnvModel; outdir="reports/path_square")

Write CSV and Markdown reports for PATH square-system diagnostics.
Returns the same dictionary as `path_square_diagnostics` with file paths added.
"""
function write_path_square_report(em::EnvModel; outdir::AbstractString="reports/path_square", top::Int=50)
    mkpath(outdir)
    diag = path_square_diagnostics(em; top=top)

    suspects = get(diag, "suspects", Any[])
    _ps_write_csv(joinpath(outdir, "path_square_suspects.csv"),
        ["variable_family", "free_instances", "fixed_instances", "reason"],
        [[get(s,"variable_family",""), get(s,"free_instances",""), get(s,"fixed_instances",""), get(s,"reason","")] for s in suspects])

    vc = _ps_var_family_counts(em.jump)
    _ps_write_csv(joinpath(outdir, "path_square_variable_families.csv"),
        ["variable_family", "total", "fixed", "free", "mapped", "active_closure"],
        [[k, v["total"], v["fixed"], v["free"], k in Set(values(equation_variable_map(em.data))), k in Set(diag["active_closure_variables"])]
         for (k,v) in sort(collect(vc), by=x->x[1])])

    cc, _ = _ps_constraint_family_counts(em.jump)
    _ps_write_csv(joinpath(outdir, "path_square_constraint_families.csv"),
        ["constraint_family", "count"],
        [[k,v] for (k,v) in sort(collect(cc), by=x->x[1])])

    open(joinpath(outdir, "path_square_summary.md"), "w") do io
        println(io, "# PATH square-system diagnostic report")
        println(io)
        println(io, "Generated by `write_path_square_report`.")
        println(io)
        println(io, "## Counts")
        println(io, "- Total variables: $(diag["variable_count_total"])")
        println(io, "- Fixed variables: $(diag["variable_count_fixed"])")
        println(io, "- Free variables: $(diag["variable_count_free"])")
        println(io, "- Non-bound constraints: $(diag["constraint_count_excluding_bounds"])")
        println(io, "- Gap using total variables: $(diag["square_gap_total_variables"])")
        println(io, "- Gap using free variables: $(diag["square_gap_free_variables"])")
        println(io)
        println(io, "## Definite mapping problems")
        println(io, "- Mapped but undeclared: $(diag["mapped_but_undeclared"])")
        println(io, "- Closure variables not declared: $(diag["closure_not_declared"])")
        println(io)
        println(io, "## Likely suspect variable families")
        if isempty(suspects)
            println(io, "No obvious suspect families were detected.")
        else
            for s in _ps_head(suspects, top)
                println(io, "- `$(get(s,"variable_family",""))`: $(get(s,"reason",""))")
            end
        end
        println(io)
        println(io, "See the CSV files in this directory for full variable and constraint family counts.")
    end

    diag["report_files"] = Dict(
        "summary"=>joinpath(outdir, "path_square_summary.md"),
        "suspects"=>joinpath(outdir, "path_square_suspects.csv"),
        "variables"=>joinpath(outdir, "path_square_variable_families.csv"),
        "constraints"=>joinpath(outdir, "path_square_constraint_families.csv"),
    )
    return diag
end


"""
    assert_path_square_preflight!(em::EnvModel; outdir=nothing, top=50)

Run the square-system diagnostics and throw a detailed error before the model is
handed to PATHSolver.  This routine deliberately uses only the `em` argument and
local variables, so it does not access `m`, `model`, `data`, or closure variables
from an outer scope.
"""
function assert_path_square_preflight!(em::EnvModel; outdir=nothing, top::Int=50)
    diag = outdir === nothing ? path_square_diagnostics(em; top=top) : write_path_square_report(em; outdir=outdir, top=top)
    em.solution["path_square_diagnostics"] = diag

    total_square = Bool(get(diag, "square_using_total_variables", false))
    mapping_bad = !isempty(get(diag, "mapped_but_undeclared", Any[])) || !isempty(get(diag, "closure_not_declared", Any[]))

    if mapping_bad || !total_square
        report_msg = outdir === nothing ? "Set `path_square_report_dir=...` to write detailed CSV reports." : "Diagnostic reports written to: $(outdir)"
        suspects = get(diag, "suspects", Any[])
        preview = isempty(suspects) ? "none" : join([string(get(s, "variable_family", "")) for s in _ps_head(suspects, 12)], ", ")
        error("PATH preflight failed: model is not square or has invalid closure/mapping variables. " *
              "Variables=$(diag["variable_count_total"]), non-bound equations=$(diag["constraint_count_excluding_bounds"]), " *
              "gap=$(diag["square_gap_total_variables"]). " *
              "Mapped-but-undeclared=$(diag["mapped_but_undeclared"]). " *
              "Closure-not-declared=$(diag["closure_not_declared"]). " *
              "Suspect families=$(preview). " * report_msg)
    end
    return diag
end

"""
    preflight_path_square(data, calib; kwargs...)

Build a temporary, unchecked EnvCGE JuMP model, run the PATH square diagnostics,
and return the diagnostic dictionary.  Use this before calling `build_model` in
scripts that should fail early when the closure system is not square.

Keyword arguments mirror `build_model` where relevant.  The temporary build uses
`require_square=false` so diagnostics can inspect the generated variables and
equations instead of failing inside PATH readiness checks.
"""
function preflight_path_square(data::EnvData, calib::EnvCalibration;
    backend=:jump_path,
    optimizer_attributes::AbstractDict{String,<:Any}=Dict{String,Any}(),
    initialize::Bool=true,
    audit_mapping::Bool=true,
    outdir=nothing,
    top::Int=50)

    em = _ps_build_diagnostic_model(data, calib;
        backend=backend,
        optimizer_attributes=optimizer_attributes,
        initialize=initialize,
        audit_mapping=audit_mapping)
    return assert_path_square_preflight!(em; outdir=outdir, top=top)
end

# -----------------------------------------------------------------------------
# Block-by-block square diagnostics
# -----------------------------------------------------------------------------

function _ps_snapshot(m::JuMP.Model)
    vc = _ps_var_family_counts(m)
    cc, ncon = _ps_constraint_family_counts(m)
    nvar = sum(row["total"] for row in values(vc); init=0)
    nfixed = sum(row["fixed"] for row in values(vc); init=0)
    nfree = sum(row["free"] for row in values(vc); init=0)
    return Dict{String,Any}(
        "variable_count_total"=>nvar,
        "variable_count_fixed"=>nfixed,
        "variable_count_free"=>nfree,
        "constraint_count_excluding_bounds"=>ncon,
        "square_gap_total_variables"=>nvar - ncon,
        "square_gap_free_variables"=>nfree - ncon,
        "variable_families"=>vc,
        "constraint_families"=>cc,
    )
end

function _ps_family_delta(after::Dict, before::Dict; key::String="total")
    out = Dict{String,Int}()
    allkeys = union(Set(keys(after)), Set(keys(before)))
    for k in allkeys
        av = haskey(after, k) ? Int(get(after[k], key, 0)) : 0
        bv = haskey(before, k) ? Int(get(before[k], key, 0)) : 0
        d = av - bv
        d != 0 && (out[string(k)] = d)
    end
    return out
end

function _ps_simple_delta(after::Dict, before::Dict)
    out = Dict{String,Int}()
    allkeys = union(Set(keys(after)), Set(keys(before)))
    for k in allkeys
        d = Int(get(after, k, 0)) - Int(get(before, k, 0))
        d != 0 && (out[string(k)] = d)
    end
    return out
end

function _ps_block_step!(trace::Vector{Dict{String,Any}}, m::JuMP.Model, block_name::AbstractString, f::Function;
    stop_on_error::Bool=false, top::Int=25)
    before = _ps_snapshot(m)
    status = "ok"
    err = ""
    try
        f()
    catch e
        status = "error"
        err = sprint(showerror, e, catch_backtrace())
        stop_on_error && rethrow(e)
    end
    after = _ps_snapshot(m)
    var_delta = after["variable_count_total"] - before["variable_count_total"]
    eq_delta = after["constraint_count_excluding_bounds"] - before["constraint_count_excluding_bounds"]
    free_delta = after["variable_count_free"] - before["variable_count_free"]
    fixed_delta = after["variable_count_fixed"] - before["variable_count_fixed"]
    push!(trace, Dict{String,Any}(
        "block"=>String(block_name),
        "status"=>status,
        "error"=>err,
        "delta_variables"=>var_delta,
        "delta_free_variables"=>free_delta,
        "delta_fixed_variables"=>fixed_delta,
        "delta_equations"=>eq_delta,
        "delta_gap_total"=>var_delta - eq_delta,
        "delta_gap_free"=>free_delta - eq_delta,
        "cumulative_variables"=>after["variable_count_total"],
        "cumulative_free_variables"=>after["variable_count_free"],
        "cumulative_fixed_variables"=>after["variable_count_fixed"],
        "cumulative_equations"=>after["constraint_count_excluding_bounds"],
        "cumulative_gap_total"=>after["square_gap_total_variables"],
        "cumulative_gap_free"=>after["square_gap_free_variables"],
        "variable_family_delta"=>Dict(k=>v for (k,v) in _ps_head(_ps_sorted_pairs(_ps_family_delta(after["variable_families"], before["variable_families"]; key="total")), top)),
        "free_variable_family_delta"=>Dict(k=>v for (k,v) in _ps_head(_ps_sorted_pairs(_ps_family_delta(after["variable_families"], before["variable_families"]; key="free")), top)),
        "fixed_variable_family_delta"=>Dict(k=>v for (k,v) in _ps_head(_ps_sorted_pairs(_ps_family_delta(after["variable_families"], before["variable_families"]; key="fixed")), top)),
        "constraint_family_delta"=>Dict(k=>v for (k,v) in _ps_head(_ps_sorted_pairs(_ps_simple_delta(after["constraint_families"], before["constraint_families"])), top)),
    ))
    return last(trace)
end

function _ps_new_jump_model(optimizer_attributes::AbstractDict{String,<:Any})
    jm = Model(PATHSolver.Optimizer)
    for (k,v) in optimizer_attributes
        set_optimizer_attribute(jm, k, v)
    end
    set_silent(jm)
    return jm
end

"""
    path_square_block_diagnostics(data, calib; outdir=nothing, initialize=true,
                                  apply_closures=true, stop_on_error=false, top=25)

Build the EnvCGE JuMP model block by block and report how many variables and
non-bound equations each block adds.  This is the safest pre-build diagnostic
when PATHSolver requires a square system, because it identifies the exact block
where the cumulative variable/equation gap changes.

The diagnostic uses only variables that are in local scope and passed as
arguments.  It does not call `build_model`, so it cannot recurse into the normal
PATH preflight gate.
"""
function path_square_block_diagnostics(data::EnvData, calib::EnvCalibration;
    optimizer_attributes::AbstractDict{String,<:Any}=Dict{String,Any}(),
    initialize::Bool=true,
    apply_closures::Bool=true,
    audit_mapping::Bool=true,
    outdir=nothing,
    stop_on_error::Bool=false,
    top::Int=25)

    jm = _ps_new_jump_model(optimizer_attributes)
    trace = Vector{Dict{String,Any}}()

    _ps_block_step!(trace, jm, "production_block!", () -> production_block!(jm,data,calib); stop_on_error=stop_on_error, top=top)
    _ps_block_step!(trace, jm, "supply_block!",     () -> supply_block!(jm,data,calib);     stop_on_error=stop_on_error, top=top)
    _ps_block_step!(trace, jm, "income_block!",     () -> income_block!(jm,data,calib);     stop_on_error=stop_on_error, top=top)
    _ps_block_step!(trace, jm, "demand_block!",     () -> demand_block!(jm,data,calib);     stop_on_error=stop_on_error, top=top)
    _ps_block_step!(trace, jm, "trade_block!",      () -> trade_block!(jm,data,calib);      stop_on_error=stop_on_error, top=top)
    _ps_block_step!(trace, jm, "markets_block!",    () -> markets_block!(jm,data,calib);    stop_on_error=stop_on_error, top=top)
    _ps_block_step!(trace, jm, "factors_block!",    () -> factors_block!(jm,data,calib);    stop_on_error=stop_on_error, top=top)
    _ps_block_step!(trace, jm, "closure_block!",    () -> closure_block!(jm,data,calib);    stop_on_error=stop_on_error, top=top)
    _ps_block_step!(trace, jm, "emissions_block!",  () -> emissions_block!(jm,data,calib);  stop_on_error=stop_on_error, top=top)

    init_report = Dict{String,Any}()
    if initialize
        _ps_block_step!(trace, jm, "apply_initial_values!", () -> begin
            init_report = apply_initial_values!(jm, data, calib)
            nothing
        end; stop_on_error=stop_on_error, top=top)
    end

    closure_report = Dict{String,Any}()
    if apply_closures
        _ps_block_step!(trace, jm, "apply_excel_closures!", () -> begin
            closure_report = apply_excel_closures!(jm, data)
            nothing
        end; stop_on_error=stop_on_error, top=top)
    end

    res = Dict{String,Function}()
    production_residuals!(res); supply_residuals!(res); income_residuals!(res); demand_residuals!(res)
    trade_residuals!(res); markets_residuals!(res); factors_residuals!(res); closure_residuals!(res)
    emissions_residuals!(res); dynamics_residuals!(res)
    em = EnvModel(data, calib, jm, equation_registry(), res,
                  Dict{String,Any}("initial_values"=>init_report, "excel_closures"=>closure_report))

    final_diag = path_square_diagnostics(em; top=top)
    mapping_report = audit_mapping ? path_mapping_report(em) : Dict{String,Any}()

    out = Dict{String,Any}(
        "block_trace"=>trace,
        "final"=>final_diag,
        "path_mapping_report"=>mapping_report,
        "square_using_total_variables"=>final_diag["square_using_total_variables"],
        "square_using_free_variables"=>final_diag["square_using_free_variables"],
        "square_gap_total_variables"=>final_diag["square_gap_total_variables"],
        "square_gap_free_variables"=>final_diag["square_gap_free_variables"],
        "variable_count_total"=>final_diag["variable_count_total"],
        "variable_count_free"=>final_diag["variable_count_free"],
        "variable_count_fixed"=>final_diag["variable_count_fixed"],
        "constraint_count_excluding_bounds"=>final_diag["constraint_count_excluding_bounds"],
        "diagnostic_model"=>em,
    )

    if outdir !== nothing
        write_path_square_block_report(out; outdir=outdir, top=top)
    end
    return out
end

"""
    write_path_square_block_report(diag; outdir="reports/path_square_blocks", top=25)

Write CSV/Markdown reports for `path_square_block_diagnostics`.
"""
function write_path_square_block_report(diag::Dict{String,Any}; outdir::AbstractString="reports/path_square_blocks", top::Int=25)
    mkpath(outdir)
    trace = get(diag, "block_trace", Any[])

    _ps_write_csv(joinpath(outdir, "block_square_trace.csv"),
        ["block", "status", "delta_variables", "delta_free_variables", "delta_fixed_variables", "delta_equations", "delta_gap_total", "delta_gap_free", "cumulative_variables", "cumulative_free_variables", "cumulative_fixed_variables", "cumulative_equations", "cumulative_gap_total", "cumulative_gap_free", "error"],
        [[get(r,"block",""), get(r,"status",""), get(r,"delta_variables",0), get(r,"delta_free_variables",0), get(r,"delta_fixed_variables",0), get(r,"delta_equations",0), get(r,"delta_gap_total",0), get(r,"delta_gap_free",0), get(r,"cumulative_variables",0), get(r,"cumulative_free_variables",0), get(r,"cumulative_fixed_variables",0), get(r,"cumulative_equations",0), get(r,"cumulative_gap_total",0), get(r,"cumulative_gap_free",0), replace(_ps_first_line(get(r,"error","")), ','=>';')]
         for r in trace])

    family_rows = Vector{Vector}()
    for r in trace
        block = get(r, "block", "")
        for (fam, n) in get(r, "variable_family_delta", Dict())
            push!(family_rows, [block, "variable", fam, n])
        end
        for (fam, n) in get(r, "free_variable_family_delta", Dict())
            push!(family_rows, [block, "free_variable", fam, n])
        end
        for (fam, n) in get(r, "fixed_variable_family_delta", Dict())
            push!(family_rows, [block, "fixed_variable", fam, n])
        end
        for (fam, n) in get(r, "constraint_family_delta", Dict())
            push!(family_rows, [block, "equation", fam, n])
        end
    end
    _ps_write_csv(joinpath(outdir, "block_family_deltas.csv"),
        ["block", "kind", "family", "delta_count"], family_rows)

    open(joinpath(outdir, "block_square_summary.md"), "w") do io
        println(io, "# Block-by-block PATH square diagnostic report")
        println(io)
        println(io, "## Final counts")
        println(io, "- Total variables: $(diag["variable_count_total"])")
        println(io, "- Free variables: $(diag["variable_count_free"])")
        println(io, "- Fixed variables: $(diag["variable_count_fixed"])")
        println(io, "- Non-bound equations: $(diag["constraint_count_excluding_bounds"])")
        println(io, "- Gap using total variables: $(diag["square_gap_total_variables"])")
        println(io, "- Gap using free variables: $(diag["square_gap_free_variables"])")
        println(io, "- Square using total variables: $(diag["square_using_total_variables"])")
        println(io)
        println(io, "## Block trace")
        println(io, "| Block | Δ variables | Δ equations | Δ gap | Cumulative variables | Cumulative equations | Cumulative gap | Status |")
        println(io, "|---|---:|---:|---:|---:|---:|---:|---|")
        for r in trace
            println(io, "| `$(get(r,"block",""))` | $(get(r,"delta_variables",0)) | $(get(r,"delta_equations",0)) | $(get(r,"delta_gap_total",0)) | $(get(r,"cumulative_variables",0)) | $(get(r,"cumulative_equations",0)) | $(get(r,"cumulative_gap_total",0)) | $(get(r,"status","")) |")
        end
        println(io)
        println(io, "The block where `Δ gap` moves away from zero is the first place to inspect. A positive `Δ gap` means the block added more variables than equations; a negative `Δ gap` means it added more equations than variables.")
    end

    diag["report_files"] = Dict(
        "summary"=>joinpath(outdir, "block_square_summary.md"),
        "trace"=>joinpath(outdir, "block_square_trace.csv"),
        "family_deltas"=>joinpath(outdir, "block_family_deltas.csv"),
    )
    return diag
end
