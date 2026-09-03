# === Function usage ===
# Mixed-complementarity presentation for PATHSolver.
# Domains and variable families below follow ENVISAGE v10.01 notation only.
# ======================

function _mcp_domain_for_variable(var::String)
    v = split(var, '[')[1]
    rules = OrderedDict(
        "XP"=>"r × a", "PXv"=>"r × a × v", "XPX"=>"r × a × v", "XGHG"=>"r × a × v", "UC"=>"r × a × v",
        "ND1"=>"r × a", "VA"=>"r × a × v", "PXP"=>"r × a × v", "VA1"=>"r × a × v", "VA2"=>"r × a × v",
        "LAB1"=>"r × a", "LAB2"=>"r × a", "KEF"=>"r × a × v", "ND2"=>"r × a", "XF"=>"r × fp × a", "PFp"=>"r × fp × a",
        "PVA"=>"r × a × v", "PVA1"=>"r × a × v", "PVA2"=>"r × a × v", "KF"=>"r × a × v", "XNRG"=>"r × a × v",
        "PKEF"=>"r × a × v", "KSW"=>"r × a × v", "PKF"=>"r × a × v", "KS"=>"r × a × v", "XWAT"=>"r × a",
        "PKSW"=>"r × a × v", "K"=>"r × a × v", "PKS"=>"r × a × v", "PLAB1"=>"r × a", "PLAB2"=>"r × a",
        "XA"=>"r × i × aa", "PA"=>"r × i", "PND1"=>"r × a", "PND2"=>"r × a", "PWAT"=>"r × a",
        "XAely"=>"r × a × v", "XNELY"=>"r × a × v", "PNRG"=>"r × a × v", "XAcoa"=>"r × a × v", "XOLG"=>"r × a × v",
        "PNELY"=>"r × a × v", "XAoil"=>"r × a × v", "XAgas"=>"r × a × v", "POLG"=>"r × a × v", 
        "X"=>"r × a × i", "P"=>"r × a × i", "PX"=>"r × a", "PP"=>"r × a × i", "XS"=>"r × i", "PS"=>"r × i",
        "XPOW"=>"r × ely", "PPOW"=>"r × ely", "XPB"=>"r × pb × ely", "PPOWN"=>"r × ely", "PPB"=>"r × pb × ely", "PPBN"=>"r × pb × ely",
        "DeprY"=>"r", "YF"=>"r × fp", "YQTF"=>"r", "TrustY"=>"scalar", "YQHT"=>"r", "Remit"=>"s × l × r",
        "ODAOut"=>"r", "ODAGbl"=>"scalar", "ODAIn"=>"r", "YH"=>"r", "YD"=>"r", "YGOV"=>"r × gy", "YFD"=>"r × fd", "Sh"=>"r", "Sg"=>"r", "Sf"=>"r", "PWsav"=>"scalar", "Ks"=>"r",
        "XC"=>"r × k × h", "PC"=>"r × k × h", "μc"=>"r × k × h", "shr"=>"r × k × h", "u"=>"r × h",
        "XCn"=>"r × k × h", "XCnrg"=>"r × k × h", "PCn"=>"r × k × h", "PCnrg"=>"r × k × h", "XAh"=>"r × i × h", "PAh"=>"r × i × h",
        "XCely"=>"r × k × h", "XCnely"=>"r × k × h", "PCely"=>"r × k × h", "PCnely"=>"r × k × h", "XCcoa"=>"r × k × h", "XColg"=>"r × k × h", "PCcoa"=>"r × k × h", "PColg"=>"r × k × h", "XCoil"=>"r × k × h", "XCgas"=>"r × k × h", "PCoil"=>"r × k × h", "PCgas"=>"r × k × h", "PAc"=>"r × i × h", "XFD"=>"r × fdc", "PFD"=>"r × fd",
        "XAT"=>"r × i", "XDTd"=>"r × i", "XDTs"=>"r × i", "XMT"=>"r × i", "PAT"=>"r × i", "PDT"=>"r × i", "PMT"=>"r × i", "XD"=>"r × i × aa", "XM"=>"r × i × aa", "PD"=>"r × i × aa", "PM"=>"r × i × aa", "PDM"=>"s × i × r", "XWd"=>"s × i × r", "XWa"=>"s × i × r × aa", "PMa"=>"r × i × aa", "XET"=>"r × i", "PET"=>"r × i", "XWs"=>"r × i × d", "PE"=>"r × i × d", "PWE"=>"r × i × d", "PWM"=>"r × i × d", "PWMG"=>"r × i × d", "XWMG"=>"r × i × d", "XMG"=>"m × r × i × d", "XTMG"=>"m", "PTMG"=>"m", "XTT"=>"r × m",
        "F"=>"r × fp", "PF"=>"r × fp", "WF"=>"r × l", "WFDIST"=>"r × l × a", "UE"=>"r × l", "LS"=>"r × l", "Migr"=>"r × l", "KOld"=>"r × a", "KNew"=>"r × a", "ROld"=>"r × a", "RNew"=>"r", "ROR"=>"r", "TLand"=>"r", "PT"=>"r", "TLag"=>"r", "XL"=>"r × lb", "PL"=>"r × lb", "XNR"=>"r × a", "PNR"=>"r × a", "WAT"=>"r", "XWATB"=>"r × wbnd", "PWATB"=>"r × wbnd",
        "GDPMP"=>"r", "GDPFC"=>"r", "GDPVA"=>"r", "RGDPMP"=>"r", "RGDPFC"=>"r", "PGDPMP"=>"r", "PGDPFC"=>"r", "RFD"=>"r × fd", "EV"=>"r", "CV"=>"r", "EVGbl"=>"scalar", "CVGbl"=>"scalar", "Welf"=>"r", "WelfGbl"=>"scalar", "Walras"=>"r", "NumPrice"=>"scalar",
        "Emi"=>"r × em × is × aa", "EmiTot"=>"r × em", "EmiOth"=>"r × em", "EmiGbl"=>"em", "EmiOthGbl"=>"em"
    )
    return get(rules, v, "document variable; see declaring equation file")
end

function mcp_pair_registry(data::EnvData)
    eqs = equation_registry()
    map = equation_variable_map(data)
    rows = OrderedDict{String,NamedTuple}()
    for (eq,label) in eqs
        var = get(map, eq, "<unmapped>")
        rows[eq] = (equation=eq, description=label, complementarity_variable=var,
                    domain=_mcp_domain_for_variable(var),
                    mcp="F_$(replace(eq, '-' => '_'))(index) ⟂ $(var)(index)")
    end
    return rows
end

function mcp_formulation_report(em::EnvModel)
    pairs = mcp_pair_registry(em.data)
    path = path_mapping_report(em)
    return Dict{String,Any}(
        "mcp_pairs" => pairs,
        "path_mapping_report" => path,
        "mcp_syntax" => "@constraint(model, [residual_expression, variable_reference] in MOI.Complements(2))",
        "note" => "Domains follow ENVISAGE Table 3.1 and the printed equation blocks."
    )
end

function assert_mcp_pairs_ready!(em::EnvModel; require_square::Bool=true)
    return assert_path_ready!(em; require_square=require_square)
end
