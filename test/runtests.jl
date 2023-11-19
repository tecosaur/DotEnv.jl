module TestDotEnv

using Test
using DotEnv: parse, tryparseline, load

# There is no "USER" variable on windows.
initial_value = haskey(ENV, "USER") ? ENV["USER"] : "WINDOWS"
ENV["USER"] = initial_value

@testset "basic" begin
    #basic input
    overfile = joinpath(@__DIR__, ".env.override")
    envfile = joinpath(@__DIR__, ".env")

    #iobuffer, string, overfile
    @test parse("BASIC=basic") == ["BASIC" => "basic"]
    @test parse(read(overfile)) == ["USER"=>"replaced value", "CUSTOMVAL123"=>"yes"]
    @test load(overfile).dict == Dict("USER"=>"replaced value", "CUSTOMVAL123"=>"yes")

    if VERSION >= v"1.7"
        @test_warn "does not exist" load("nonexistentfile.env")
    end

    #length of returned values
    @test length(load(envfile).dict) == 10

    #shouldn't replace ENV vars
    cfg = load(overfile)

    @test ENV["USER"] != cfg["USER"]
    @test ENV["USER"] == initial_value

    #appropiately loaded into ENV if CUSTOM_VAL is non existent
    @test ENV["CUSTOMVAL123"] == "yes"

    # Test that EnvDict is reading from ENV
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
    ENV["USER"] = initial_value
end


@testset "parsing" begin

    #comment
    @test parse("#HIMOM") isa Vector{Pair{String, String}}
    @test tryparseline("#HIMOM") === nothing

    #spaces without quotes
    @test count(' ', last(tryparseline("TEST=hi  the  re"))) == 4

    #single quotes
    @test tryparseline("TEST=''") == ("TEST" => "")
    @test tryparseline("TEST='something'") == ("TEST" => "something")

    #double quotes
    @test tryparseline("TEST=\"\"") == ("TEST" => "")
    @test tryparseline("TEST=\"something\"") == ("TEST" => "something")

    #inner quotes are mantained
    @test tryparseline("TEST='\"json\"'") == ("TEST" => "\"json\"")
    @test tryparseline("TEST=\"'json'\"") == ("TEST" => "'json'")
    @test tryparseline("TEST='\"'") == ("TEST" => "\"")
    @test tryparseline("TEST=\"'\"") == ("TEST" => "'")

    #line breaks
    @test tryparseline("TEST=\"\\n\"") == ("TEST" => "\n") # It's empty because of final trim
    @test tryparseline("TEST=\"\\n\\nsomething\"") == ("TEST" => "\n\nsomething")
    @test tryparseline("TEST=\"something\\nsomething\"") == ("TEST" => "something\nsomething")
    @test tryparseline("TEST=\"something\\n\\nsomething\"") == ("TEST" => "something\n\nsomething")
    @test tryparseline("TEST='\\n'") == ("TEST" => "\\n")
    @test tryparseline("TEST=\\n") == ("TEST" => "\\n")

    #empty vars
    @test tryparseline("TEST=") == ("TEST" => "")

    #trim spaces without quotes
    @test tryparseline("TEST=  something  ") == ("TEST" => "something")
    @test tryparseline("TEST=    ") == ("TEST" => "")
end

end # module
