# === Function usage ===
# Model assembly and PATH solve driver.
# Usage:
#   data = load_default_data()
#   cal = calibrate(data)
#   diag = preflight_path_square(data, cal; outdir="reports/path_square")
#   model = build_model(data, cal; initialize=true, audit_mapping=true)
#   sol = solve!(model; require_square=true)
#
# `require_square=true` now runs PATH square diagnostics before returning the
# model, so PATHSolver is never called with a non-square system.
# ======================

function _build_model_unchecked(data::EnvData, calib::EnvCalibration; backend=:jump_path,
    optimizer_attributes::AbstractDict{String,<:Any}=Dict{String,Any}(),
    initialize::Bool=true,
    audit_mapping::Bool=true)

    backend == :jump_path || error("Only backend=:jump_path is currently supported for the PATHSolver build.")
    jm = Model(PATHSolver.Optimizer)
    for (k,v) in optimizer_attributes
        set_optimizer_attribute(jm, k, v)
    end
    set_silent(jm)


    production_block!(jm,data,calib)
    supply_block!(jm,data,calib)
    income_block!(jm,data,calib)
    demand_block!(jm,data,calib)
    trade_block!(jm,data,calib)
    markets_block!(jm,data,calib)
    factors_block!(jm,data,calib)
    closure_block!(jm,data,calib)
    emissions_block!(jm,data,calib)

    init_report = initialize ? apply_initial_values!(jm, data, calib) : Dict{String,Any}("applied"=>0,"explicit"=>0,"fallback"=>0)
    closure_report = apply_excel_closures!(jm, data)
    # ENVISAGE's standard closure fixes more variables than the workbook's
    # `closures` sheet lists; the defaults are applied afterwards so a workbook
    # rule always wins over the default.
    default_closure_report = apply_default_closures!(jm, data)

    res=Dict{String,Function}()
    production_residuals!(res); supply_residuals!(res); income_residuals!(res); demand_residuals!(res)
    trade_residuals!(res); markets_residuals!(res); factors_residuals!(res); closure_residuals!(res)
    emissions_residuals!(res); dynamics_residuals!(res)

    em = EnvModel(data,calib,jm,equation_registry(),res,Dict{String,Any}("initial_values"=>init_report, "excel_closures"=>closure_report,
                                       "default_closures"=>default_closure_report))
    if audit_mapping
        em.solution["path_mapping_report"] = path_mapping_report(em)
        # Mapping completeness is checked here.  Square status is handled by
        # assert_path_square_preflight! so diagnostic reports can be produced.
        assert_path_ready!(em; require_square=false)
    end
    return em
end

function build_model(data::EnvData, calib::EnvCalibration; backend=:jump_path,
    optimizer_attributes::AbstractDict{String,<:Any}=Dict{String,Any}(),
    initialize::Bool=true,
    audit_mapping::Bool=true,
    require_square::Bool=false,
    path_square_report_dir=nothing,
    path_square_top::Int=50)

    em = _build_model_unchecked(data, calib;
        backend=backend,
        optimizer_attributes=optimizer_attributes,
        initialize=initialize,
        audit_mapping=audit_mapping)

    if require_square
        # This is the required pre-PATH gate: count equations/variables and
        # identify closure/mapping problems before the caller can solve.
        assert_path_square_preflight!(em; outdir=path_square_report_dir, top=path_square_top)
        assert_path_ready!(em; require_square=true)
    end
    return em
end

function solve!(em::EnvModel; require_square::Bool=true, path_square_report_dir=nothing, path_square_top::Int=50)
    if require_square
        assert_path_square_preflight!(em; outdir=path_square_report_dir, top=path_square_top)
    end
    assert_path_ready!(em; require_square=require_square)
    optimize!(em.jump)
    em.solution["status"] = string(termination_status(em.jump))
    em.solution["primal_status"] = string(primal_status(em.jump))
    em.solution["equation_count"] = length(em.equations)
    em.solution["variable_count"] = JuMP.num_variables(em.jump)
    em.solution["constraint_count"] = JuMP.num_constraints(em.jump; count_variable_in_set_constraints=false)
    return em.solution
end
