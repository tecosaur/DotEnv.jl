module TestDotEnv

using Test
using DotEnv: parse, _parse, tryparseline, interpolate, load

# There is no "USER" variable on windows.
the_user = haskey(ENV, "USER") ? ENV["USER"] : "WINDOWS"
ENV["USER"] = the_user

@testset "basic" begin
    #basic input
    overfile = joinpath(@__DIR__, ".env.override")
    envfile = joinpath(@__DIR__, ".env")

    #iobuffer, string, overfile
    @test _parse("BASIC=basic") == ["BASIC" => ("basic", true)]
    @test _parse(read(overfile)) == ["USER" => ("replaced value", true), "CUSTOMVAL123" => ("yes", true)]
    @test load(overfile).dict == Dict("USER"=>"replaced value", "CUSTOMVAL123"=>"yes")

    if VERSION >= v"1.7"
        @test_warn "does not exist" load("nonexistentfile.env")
    end

    #length of returned values
    @test length(load(envfile).dict) == 10

    #shouldn't replace ENV vars
    cfg = load(overfile)

    @test ENV["USER"] != cfg["USER"]
    @test ENV["USER"] == the_user

    #appropiately loaded into ENV if CUSTOM_VAL is non existent
    @test ENV["CUSTOMVAL123"] == "yes"

    # Test that EnvOverlay is reading from ENV
    ENV["SOME_RANDOM_KEY"] = "abc"
    cfg = load(overfile)
    @test !haskey(cfg.dict, "SOME_RANDOM_KEY")
    @test cfg["SOME_RANDOM_KEY"] == "abc"
    @test get(cfg, "OTHER_RANDOM_KEY", "zxc") == "zxc"
end

@testset "Override" begin
    #basic input
    overfile = joinpath(@__DIR__, ".env.override")

    # Can force override
    cfg = load(overfile, override=true)
    @test ENV["USER"] == cfg["USER"]
    @test ENV["USER"] == "replaced value"
    
    # Restore previous environment
    ENV["USER"] = the_user
end


@testset "parsing" begin

    #comment
    @test _parse("#HIMOM") isa Vector{Pair{String, Tuple{String, Bool}}}
    @test parse("#HIMOM") isa Dict{String, String}
    @test tryparseline("#HIMOM") === nothing

    #spaces without quotes
    @test count(' ', first(last(tryparseline("TEST=hi  the  re")))) == 4

    #single quotes
    @test tryparseline("TEST=''") == ("TEST" => ("", false))
    @test tryparseline("TEST='something'") == ("TEST" => ("something", false))

    #double quotes
    @test tryparseline("TEST=\"\"") == ("TEST" => ("", true))
    @test tryparseline("TEST=\"something\"") == ("TEST" => ("something", true))

    #inner quotes are mantained
    @test tryparseline("TEST='\"json\"'") == ("TEST" => ("\"json\"", false))
    @test tryparseline("TEST=\"'json'\"") == ("TEST" => ("'json'", true))
    @test tryparseline("TEST='\"'") == ("TEST" => ("\"", false))
    @test tryparseline("TEST=\"'\"") == ("TEST" => ("'", true))

    #line breaks
    @test tryparseline("TEST=\"\\n\"") == ("TEST" => ("\n", true)) # It's empty because of final trim
    @test tryparseline("TEST=\"\\n\\nsomething\"") == ("TEST" => ("\n\nsomething", true))
    @test tryparseline("TEST=\"something\\nsomething\"") == ("TEST" => ("something\nsomething", true))
    @test tryparseline("TEST=\"something\\n\\nsomething\"") == ("TEST" => ("something\n\nsomething", true))
    @test tryparseline("TEST='\\n'") == ("TEST" => ("\\n", false))
    @test tryparseline("TEST=\\n") == ("TEST" => ("\\n", true))

    #empty vars
    @test tryparseline("TEST=") == ("TEST" => ("", true))

    #trim spaces without quotes
    @test tryparseline("TEST=  something  ") == ("TEST" => ("something", true))
    @test tryparseline("TEST=    ") == ("TEST" => ("", true))
end

@testset "Interpolation" begin
    @test interpolate("hello", Dict{String, String}(), ENV) == "hello"
    @test interpolate("hello \$USER", Dict{String, String}(), ENV) == "hello $the_user"
    @test interpolate("hello \$USER", Dict{String, String}("USER" => "fred"), ENV) == "hello fred"
    @test interpolate("hello \${USER}", Dict{String, String}(), ENV) == "hello $the_user"
    @test interpolate("hello \$USER.", Dict{String, String}(), ENV) == "hello $the_user."
    @test interpolate("hello \$USERR", Dict{String, String}(), ENV) == "hello "
    @test interpolate("hello \${USERR:-you}", Dict{String, String}(), ENV) == "hello you"
    @test interpolate("hello \${USERR:-\$USER}", Dict{String, String}(), ENV) == "hello $the_user"
    @test interpolate("hello \${USERR:-\${USERR:-you}}", Dict{String, String}(), ENV) == "hello you"
    @test interpolate("hello \${USERR:-\${USERR:-\$USER}}", Dict{String, String}(), ENV) == "hello $the_user"
end

end
