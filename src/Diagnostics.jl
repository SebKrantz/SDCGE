# Diagnostics for LINKAGE/JuMP MCP models.
#
# An earlier version tried to discover the variable matched to each equation by
# parsing the printed constraint text after the unicode complementarity symbol,
# and a subsequent version tried to walk MathOptInterface's own VectorAffine/
# VectorQuadratic/VectorNonlinear function representations (output_index-tagged
# terms).  Both failed to extract anything for this JuMP 1.30 / PATHSolver 1.7
# stack because `JuMP.constraint_object(c)` for an `F ⟂ x` constraint already
# returns the *JuMP-level* function: a plain `Vector` of length 2k of JuMP
# scalar expressions (`AffExpr`, `QuadExpr`, or `NonlinearExpr`), indexed
# positionally — component `row` is the residual `F` and component `k+row` is
# the complementary variable `x` (verified empirically: k=1 for every
# complementarity constraint in this model, i.e. each is a plain scalar
# `F[idx] ⟂ x[idx]`). MOI's `output_index`-tagged term scheme, which the
# earlier version assumed, does not apply to this positional representation.
# This version walks the JuMP expression tree directly (`GenericAffExpr.terms`,
# `GenericQuadExpr.aff`/`.terms`, `GenericNonlinearExpr.args`) to recover the
# variable(s) referenced by each side.
#
# Main entry points:
#   diagnose_model(m; outdir="results/diagnostics")
#   print_equation_diagnostics(m)

using DataFrames
const MOI = JuMP.MOI

# -----------------------------------------------------------------------------
# Small utilities
# -----------------------------------------------------------------------------

function _diag_name(x)
    try
        n = JuMP.name(x)
        return isempty(n) ? string(x) : n
    catch
        return string(x)
    end
end

_diag_family_name(s::AbstractString) = replace(String(s), r"\[.*\]" => "")
_diag_norm_text(s::AbstractString) = replace(String(s), r"\s+" => "")

function _diag_csv_escape(x)
    s = x === missing ? "" : string(x)
    if occursin(',', s) || occursin('"', s) || occursin('\n', s) || occursin('\r', s)
        return "\"" * replace(s, "\"" => "\"\"") * "\""
    end
    return s
end

function _diag_write_csv(path::AbstractString, df::DataFrame)
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, join(_diag_csv_escape.(names(df)), ","))
        for row in eachrow(df)
            println(io, join((_diag_csv_escape(row[c]) for c in names(df)), ","))
        end
    end
    return path
end

function _diag_var_lookup(m)
    d = Dict{String,String}()
    for v in JuMP.all_variables(m)
        d[string(JuMP.index(v))] = _diag_name(v)
    end
    return d
end

# -----------------------------------------------------------------------------
# JuMP-expression variable extraction
#
# `JuMP.constraint_object(c).func` for a Complements constraint is a plain
# `Vector` of JuMP scalar expressions (not an MOI VectorAffineFunction/etc with
# output_index-tagged terms), so recovering the variable(s) referenced by a
# component just means walking that expression's own JuMP fields.
# -----------------------------------------------------------------------------

function _diag_scalar_vars!(acc::Vector{JuMP.VariableRef}, x)
    if x isa JuMP.VariableRef
        push!(acc, x)
    elseif x isa JuMP.GenericAffExpr
        for v in keys(x.terms)
            push!(acc, v)
        end
    elseif x isa JuMP.GenericQuadExpr
        _diag_scalar_vars!(acc, x.aff)
        for p in keys(x.terms)
            push!(acc, p.a)
            push!(acc, p.b)
        end
    elseif x isa JuMP.GenericNonlinearExpr
        for a in x.args
            _diag_scalar_vars!(acc, a)
        end
    end
    return acc
end

"""Every JuMP variable referenced by a scalar JuMP expression (AffExpr, QuadExpr, or NonlinearExpr)."""
_diag_scalar_vars(x) = unique(_diag_scalar_vars!(JuMP.VariableRef[], x))

"""Evaluate a scalar JuMP expression using each variable's JuMP start value (0.0 if unset)."""
function _diag_eval_at_start(x)
    try
        return JuMP.value(v -> (sv = JuMP.start_value(v); sv === nothing ? 0.0 : Float64(sv)), x)
    catch
        return NaN
    end
end

function _diag_constraint_object(c)
    try
        return JuMP.constraint_object(c)
    catch
        return nothing
    end
end

_diag_is_complements_set(S) = (S <: MOI.Complements) || occursin("Complements", string(S))

function _diag_complement_var_names_from_text(text::AbstractString)
    occursin('⟂', text) || return String[]
    rhs = strip(split(String(text), '⟂')[end])
    rhs = replace(rhs, r"\s+" => "")
    rhs = replace(rhs, r";$" => "")
    return isempty(rhs) ? String[] : [rhs]
end

# -----------------------------------------------------------------------------
# Public diagnostics
# -----------------------------------------------------------------------------

"""Return all JuMP variables with stable MOI ids and printable names."""
function diagnostic_variables(m)
    vars = JuMP.all_variables(m)
    return DataFrame(
        variable_index = [string(JuMP.index(v)) for v in vars],
        variable = [_diag_name(v) for v in vars],
        family = [_diag_family_name(_diag_name(v)) for v in vars],
    )
end

"""Collect model constraints.  Complementarity constraints are marked explicitly."""
function diagnostic_constraints(m)
    rows = NamedTuple[]
    for (F, S) in JuMP.list_of_constraint_types(m)
        for c in JuMP.all_constraints(m, F, S)
            cname = _diag_name(c)
            cstr = string(c)
            is_comp = _diag_is_complements_set(S) || occursin('⟂', cstr)
            push!(rows, (
                constraint = cname,
                family = _diag_family_name(cname),
                f_type = string(F),
                set_type = string(S),
                is_complementarity = is_comp,
                text = cstr,
            ))
        end
    end
    return DataFrame(rows)
end

"""
Return equation-to-variable MCP matches, one row per (constraint, complement
variable) pair.

For each `MOI.Complements` constraint, `JuMP.constraint_object(c).func` is a
`Vector` of length `2k` of JuMP scalar expressions, positionally laid out as
`[F_1,...,F_k, x_1,...,x_k]`: component `k+row` is the variable complementary
to residual component `row` (k=1 for every constraint in this model — each is
a plain scalar `F[idx] ⟂ x[idx]`). The complement variable is recovered by
walking that expression's own JuMP fields (`_diag_scalar_vars`), and the
residual is evaluated at the model's current JuMP start values
(`_diag_eval_at_start`) and reported in `residual_at_start`.

Falls back to text-based `⟂` parsing only for a constraint that is not itself
an `MOI.Complements` set but whose printed form still contains `⟂` (a defence
against a future JuMP/PATH representation change; not exercised by the
current stack, where every `⟂` constraint is `MOI.Complements`-typed).
"""
function diagnostic_equation_matches(m)
    lookup = _diag_var_lookup(m)
    rows = NamedTuple[]

    for (F, S) in JuMP.list_of_constraint_types(m)
        is_comp_type = _diag_is_complements_set(S)
        for c in JuMP.all_constraints(m, F, S)
            cname = _diag_name(c)
            ctext = string(c)

            if is_comp_type
                obj = _diag_constraint_object(c)
                if obj === nothing || !hasproperty(obj, :func)
                    continue
                end
                func = obj.func
                k = length(func) ÷ 2
                for row in 1:k
                    residual_expr = func[row]
                    var_expr = func[k+row]
                    vars = _diag_scalar_vars(var_expr)
                    residual_val = _diag_eval_at_start(residual_expr)
                    if length(vars) == 1
                        v = vars[1]
                        vid = string(JuMP.index(v))
                        vname = get(lookup, vid, _diag_name(v))
                        push!(rows, (
                            constraint = cname,
                            constraint_family = _diag_family_name(cname),
                            complement_variable_index = vid,
                            complement_variable = vname,
                            complement_family = _diag_family_name(vname),
                            residual_variable_count = length(vars),
                            residual_at_start = residual_val,
                            extraction_method = "func[$(k+row)] of $(length(func))",
                            text = ctext,
                        ))
                    else
                        # Anomalous: complement side is not a bare single variable.
                        # Emit one row per variable found (0 rows if none) so
                        # diagnostic_variables_without_equations still flags it.
                        for v in vars
                            vid = string(JuMP.index(v))
                            vname = get(lookup, vid, _diag_name(v))
                            push!(rows, (
                                constraint = cname,
                                constraint_family = _diag_family_name(cname),
                                complement_variable_index = vid,
                                complement_variable = vname,
                                complement_family = _diag_family_name(vname),
                                residual_variable_count = length(vars),
                                residual_at_start = residual_val,
                                extraction_method = "ANOMALY: $(length(vars)) vars in func[$(k+row)]",
                                text = ctext,
                            ))
                        end
                    end
                end
            elseif occursin('⟂', ctext)
                # Defensive fallback for a non-Complements-typed but ⟂-printed
                # constraint; not exercised by the current JuMP/PATH stack.
                for vname in _diag_complement_var_names_from_text(ctext)
                    push!(rows, (
                        constraint = cname,
                        constraint_family = _diag_family_name(cname),
                        complement_variable_index = "",
                        complement_variable = vname,
                        complement_family = _diag_family_name(vname),
                        residual_variable_count = 0,
                        residual_at_start = NaN,
                        extraction_method = "text",
                        text = ctext,
                    ))
                end
            end
        end
    end

    return DataFrame(rows)
end

"""Find variables with no MCP complementarity equation."""
function diagnostic_variables_without_equations(m)
    vars = diagnostic_variables(m)
    matches = diagnostic_equation_matches(m)
    if nrow(matches) == 0
        return vars
    end

    matched_ids = Set(String.(matches.complement_variable_index[matches.complement_variable_index .!= ""]))
    matched_names = Set(String.(matches.complement_variable[matches.complement_variable_index .== ""]))

    keep = [!(row.variable_index in matched_ids) && !(row.variable in matched_names) for row in eachrow(vars)]
    return vars[keep, :]
end

"""Find variables matched by multiple MCP equations."""
function diagnostic_variables_with_multiple_equations(m)
    matches = diagnostic_equation_matches(m)
    nrow(matches) == 0 && return DataFrame(
        complement_variable=String[], complement_variable_index=String[], equation_count=Int[],
        constraints=String[], constraint_families=String[])

    key = [isempty(r.complement_variable_index) ? r.complement_variable : r.complement_variable_index for r in eachrow(matches)]
    tmp = copy(matches)
    tmp[!, :match_key] = key
    g = combine(groupby(tmp, :match_key),
        :complement_variable => first => :complement_variable,
        :complement_variable_index => first => :complement_variable_index,
        nrow => :equation_count,
        :constraint => (x -> join(x, "; ")) => :constraints,
        :constraint_family => (x -> join(unique(x), "; ")) => :constraint_families,
    )
    return sort(g[g.equation_count .> 1, :], :equation_count, rev=true)
end

"""Flag likely duplicate, tautological, or placeholder equations."""
function diagnostic_redundant_equations(m)
    matches = diagnostic_equation_matches(m)
    rows = NamedTuple[]
    seen_residual = Dict{String,Vector{String}}()

    for row in eachrow(matches)
        lhs = occursin('⟂', row.text) ? split(row.text, '⟂')[1] : row.text
        norm_lhs = _diag_norm_text(lhs)
        push!(get!(seen_residual, norm_lhs, String[]), row.constraint)

        reasons = String[]
        if occursin(r"\b([A-Za-z_]\w*(?:\[[^\]]+\])?)-\1\b", norm_lhs)
            push!(reasons, "tautology: variable minus itself")
        end
        if norm_lhs in ("0", "(0)") || occursin(r"(^|[=+\-*/(])0($|[)+\-*/])", norm_lhs)
            push!(reasons, "zero/placeholder residual candidate")
        end
        if !isempty(reasons)
            push!(rows, (
                constraint = row.constraint,
                complement_variable = row.complement_variable,
                reason = join(reasons, "; "),
                text = row.text,
            ))
        end
    end

    for (norm, cnames) in seen_residual
        if length(cnames) > 1
            push!(rows, (
                constraint = join(cnames, "; "),
                complement_variable = "",
                reason = "duplicate residual text",
                text = norm,
            ))
        end
    end
    return DataFrame(rows)
end

"""
Summarise model diagnostics and optionally write CSV files under `outdir`.

Files:
- variables.csv
- constraints.csv
- equation_matches.csv
- variables_without_equations.csv
- variables_with_multiple_equations.csv
- likely_redundant_equations.csv
- diagnostic_summary.csv
"""
function diagnose_model(m; outdir::AbstractString=joinpath("results", "diagnostics"), write_csv::Bool=true, verbose::Bool=true)
    vars = diagnostic_variables(m)
    cons = diagnostic_constraints(m)
    matches = diagnostic_equation_matches(m)
    missing = diagnostic_variables_without_equations(m)
    multiple = diagnostic_variables_with_multiple_equations(m)
    redundant = diagnostic_redundant_equations(m)

    summary = DataFrame(metric = String[], value = Int[])
    push!(summary, ("variables", nrow(vars)))
    push!(summary, ("constraints_total", nrow(cons)))
    push!(summary, ("complementarity_constraints", count(cons.is_complementarity)))
    push!(summary, ("equation_variable_matches", nrow(matches)))
    push!(summary, ("variables_without_equations", nrow(missing)))
    push!(summary, ("variables_with_multiple_equations", nrow(multiple)))
    push!(summary, ("likely_redundant_equations", nrow(redundant)))

    if write_csv
        mkpath(outdir)
        _diag_write_csv(joinpath(outdir, "variables.csv"), vars)
        _diag_write_csv(joinpath(outdir, "constraints.csv"), cons)
        _diag_write_csv(joinpath(outdir, "equation_matches.csv"), matches)
        _diag_write_csv(joinpath(outdir, "variables_without_equations.csv"), missing)
        _diag_write_csv(joinpath(outdir, "variables_with_multiple_equations.csv"), multiple)
        _diag_write_csv(joinpath(outdir, "likely_redundant_equations.csv"), redundant)
        _diag_write_csv(joinpath(outdir, "diagnostic_summary.csv"), summary)
    end

    if verbose
        print_equation_diagnostics(m; max_rows=20)
        write_csv && println("Diagnostic CSV files written to: ", outdir)
    end

    return Dict(
        :summary => summary,
        :variables => vars,
        :constraints => cons,
        :equation_matches => matches,
        :variables_without_equations => missing,
        :variables_with_multiple_equations => multiple,
        :likely_redundant_equations => redundant,
    )
end

function print_equation_diagnostics(m; max_rows::Int=20)
    vars = diagnostic_variables(m)
    cons = diagnostic_constraints(m)
    matches = diagnostic_equation_matches(m)
    missing = diagnostic_variables_without_equations(m)
    multiple = diagnostic_variables_with_multiple_equations(m)
    redundant = diagnostic_redundant_equations(m)

    println("\n================ EQUATION DIAGNOSTICS ================")
    println("Variables:                         ", nrow(vars))
    println("Constraints total:                 ", nrow(cons))
    println("Complementarity constraints:        ", count(cons.is_complementarity))
    println("Equation-variable matches:          ", nrow(matches))
    println("Variables without equations:        ", nrow(missing))
    println("Variables with multiple equations:  ", nrow(multiple))
    println("Likely redundant/placeholders:      ", nrow(redundant))

    if nrow(matches) == 0 && count(cons.is_complementarity) > 0
        println("\nWARNING: Complementarity constraints exist, but no matched variables were extracted.")
        println("Inspect constraints.csv and equation_matches.csv; this may indicate a JuMP/MOI representation not covered by Diagnostics.jl.")
    end

    if nrow(missing) > 0
        println("\nFirst variables without equations:")
        show(first(missing, min(max_rows, nrow(missing))); allcols=true, truncate=100)
        println()
    end
    if nrow(multiple) > 0
        println("\nFirst variables matched by multiple equations:")
        show(first(multiple, min(max_rows, nrow(multiple))); allcols=true, truncate=100)
        println()
    end
    if nrow(redundant) > 0
        println("\nFirst likely redundant/placeholders:")
        show(first(redundant, min(max_rows, nrow(redundant))); allcols=true, truncate=100)
        println()
    end
    println("======================================================\n")
    return nothing
end
