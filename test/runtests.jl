module TestDotEnv

using Test
using DotEnv: DotEnv, EnvEntry, parse, _parse, tryparseline, interpolate, config, load!, unload!

# There is no "USER" variable on windows.
the_user = haskey(ENV, "USER") ? ENV["USER"] : "WINDOWS"
ENV["USER"] = the_user

cd(@__DIR__)

@testset "Parsing" begin
    #comment
    @test _parse("#comment") == EnvEntry[]
    @test parse("#comment") == Dict{String, String}()
    @test tryparseline("#comment") === nothing
    @test tryparseline("TEST=1 # comment") == EnvEntry("TEST", "1", true)

    #spaces without quotes
    @test count(' ', tryparseline("TEST=hi  the  re").value) == 4

    #single quotes
    @test tryparseline("TEST=''") == EnvEntry("TEST", "", false)
    @test tryparseline("TEST='something'") == EnvEntry("TEST", "something", false)

    #double quotes
    @test tryparseline("TEST=\"\"") == EnvEntry("TEST", "", true)
    @test tryparseline("TEST=\"something\"") == EnvEntry("TEST", "something", true)

    #inner quotes are mantained
    @test tryparseline("TEST='\"json\"'") == EnvEntry("TEST", "\"json\"", false)
    @test tryparseline("TEST=\"'json'\"") == EnvEntry("TEST", "'json'", true)
    @test tryparseline("TEST='\"'") == EnvEntry("TEST", "\"", false)
    @test tryparseline("TEST=\"'\"") == EnvEntry("TEST", "'", true)

    #line breaks
    @test tryparseline("TEST=\"\\n\"") == EnvEntry("TEST", "\n", true) # It's empty because of final trim
    @test tryparseline("TEST=\"\\n\\nsomething\"") == EnvEntry("TEST", "\n\nsomething", true)
    @test tryparseline("TEST=\"something\\nsomething\"") == EnvEntry("TEST", "something\nsomething", true)
    @test tryparseline("TEST=\"something\\n\\nsomething\"") == EnvEntry("TEST", "something\n\nsomething", true)
    @test tryparseline("TEST='\\n'") == EnvEntry("TEST", "\\n", false)
    @test tryparseline("TEST=\\n") == EnvEntry("TEST", "\\n", true)

    #empty vars
    @test tryparseline("TEST=") == EnvEntry("TEST", "", true)

    #trim spaces without quotes
    @test tryparseline("TEST=  something  ") == EnvEntry("TEST", "something", true)
    @test tryparseline("TEST=    ") == EnvEntry("TEST", "", true)
end

@testset "Interpolation" begin
    @test interpolate("hello", Dict{String, String}(), ENV) == "hello"
    @test interpolate("hi\$there", Dict{String, String}(), ENV) == "hi"
    @test interpolate("hi\\\$there", Dict{String, String}(), ENV) == "hi\$there"
    @test interpolate("hi\\0there", Dict{String, String}(), ENV) == "hi\\0there"
    @test interpolate("hello \$USER", Dict{String, String}(), ENV) == "hello $the_user"
    @test interpolate("hello \$USER", Dict{String, String}("USER" => "fred"), ENV) == "hello fred"
    @test interpolate("hello \${USER:-alice}", Dict{String, String}("USER" => "fred"), ENV) == "hello fred"
    @test interpolate("hello \${USER}", Dict{String, String}(), ENV) == "hello $the_user"
    @test interpolate("hello \$USER.", Dict{String, String}(), ENV) == "hello $the_user."
    @test interpolate("hello \$USERR", Dict{String, String}(), ENV) == "hello "
    @test interpolate("hello \${USERR:-you}", Dict{String, String}(), ENV) == "hello you"
    @test interpolate("hello \${USERR:-you\\\\}", Dict{String, String}(), ENV) == "hello you\\\\"
    @test interpolate("hello \${USERR:-you\\}\\\$\\{}", Dict{String, String}(), ENV) == "hello you}\${"
    @test interpolate("hello \${USERR:-\$USER}", Dict{String, String}(), ENV) == "hello $the_user"
    @test interpolate("hello \${USERR:-\${USERR:-you}}", Dict{String, String}(), ENV) == "hello you"
    @test interpolate("hello \${USERR:-\${USERR:-\$USER}}", Dict{String, String}(), ENV) == "hello $the_user"
end

@testset "Basic" begin
    #iobuffer, string, .env.local
    @test _parse("BASIC=basic") == [EnvEntry("BASIC", "basic", true)]
    @test _parse(read(".env.local")) == [EnvEntry("USER", "replaced value", true), EnvEntry("CUSTOMVAL123", "yes", true)]
    @test config(".env.local").overlay == Dict("CUSTOMVAL123"=>"yes")
    @test config(".env.local", override=true).overlay == Dict("USER"=>"replaced value", "CUSTOMVAL123"=>"yes")

    @test config("nonexistentfile.env") isa Any # No error

    #length of returned values
    @test length(config(".env", override=true).overlay) == 10

    #shouldn't replace ENV vars
    cfg = config(".env.local")
    @test ENV["USER"] == cfg["USER"] == the_user

    # Now with override
    cfg = config(".env.local", override=true)

    @test ENV["USER"] != cfg["USER"]
    @test ENV["USER"] == the_user

    #appropiately loaded into cfg if CUSTOM_VAL is non existent
    @test cfg["CUSTOMVAL123"] == "yes"

    # Test that EnvOverlay is reading from ENV
    ENV["SOME_RANDOM_KEY"] = "abc"
    cfg = config(".env.local")
    @test !haskey(cfg.overlay, "SOME_RANDOM_KEY")
    @test cfg["SOME_RANDOM_KEY"] == "abc"
    @test haskey(cfg, "SOME_RANDOM_KEY")
    @test ("SOME_RANDOM_KEY" => "abc") in cfg
    @test get(cfg, "OTHER_RANDOM_KEY", "zxc") == "zxc"
    @test !isempty(cfg)
    @test_throws KeyError cfg["NON_EXISTENT_KEY"]
end

@testset "Load and unload" begin
    virginenv = Dict{String, String}(ENV)
    envvals = config(".env", env=Dict{String, String}())
    overridevals = config(".env.local", env=Dict{String, String}())
    myenv = Dict{String, String}()
    load!(myenv, ".env")
    @test length(DotEnv.ENV_STACKS[myenv]) == 1
    for key in keys(envvals)
        @test myenv[key] == envvals[key]
    end
    load!(myenv, ".env.local")
    @test length(DotEnv.ENV_STACKS[myenv]) == 2
    for key in keys(overridevals)
        if haskey(envvals, key)
            @test myenv[key] == envvals[key]
        else
            @test myenv[key] == overridevals[key]
        end
    end
    load!(myenv, ".env.local", override=true)
    @test length(DotEnv.ENV_STACKS[myenv]) == 2
    for key in keys(overridevals)
        if haskey(overridevals, key)
            @test myenv[key] == overridevals[key]
        else
            @test myenv[key] == envvals[key]
        end
    end
    unload!(myenv, ".env")
    @test length(DotEnv.ENV_STACKS[myenv]) == 1
    for key in keys(envvals)
        if haskey(overridevals, key)
            @test myenv[key] == overridevals[key]
        else
            @test !haskey(ENV, key)
        end
    end
    unload!(myenv, ".env.local")
    @test isempty(myenv)
    # Now with `ENV`
    load!(".env")
    for key in keys(envvals)
        if haskey(virginenv, key)
            @test ENV[key] == virginenv[key]
        else
            @test ENV[key] == envvals[key]
        end
    end
    load!(".env.local")
    for key in keys(overridevals)
        if haskey(virginenv, key)
            @test ENV[key] == virginenv[key]
        elseif haskey(envvals, key)
            @test ENV[key] == envvals[key]
        else
            @test ENV[key] == overridevals[key]
        end
    end
    load!(".env.local", override=true)
    for key in keys(overridevals)
        if haskey(overridevals, key)
            @test ENV[key] == overridevals[key]
        elseif haskey(virginenv, key)
            @test ENV[key] == virginenv[key]
        else
            @test ENV[key] == envvals[key]
        end
    end
    unload!(".env")
    for key in keys(envvals)
        if haskey(overridevals, key)
            @test ENV[key] == overridevals[key]
        elseif haskey(virginenv, key)
            @test ENV[key] == virginenv[key]
        else
            @test !haskey(ENV, key)
        end
    end
    unload!(".env.local")
    for key in keys(overridevals)
        if !haskey(virginenv, key)
            @test !haskey(ENV, key)
        end
    end
    @test length(ENV) == length(virginenv)
    @test Dict{String, String}(ENV) == virginenv
end

@testset "Multiple env files" begin
    myenv1 = Dict{String, String}()
    myenv2 = Dict{String, String}()
    load!(myenv1)
    load!(myenv2, ".env.local")
    load!(myenv2, ".env")
    @test myenv1 == myenv2
    myenv3 = Dict{String, String}()
    load!(myenv3, override=true)
    @test myenv1 == myenv3
    unload!(myenv1)
    @test isempty(myenv1)
    unload!(myenv2, ".env")
    unload!(myenv2, ".env.local")
    @test isempty(myenv2)
end

end
