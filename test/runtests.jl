module TestDotEnv

using DotEnv

@static if VERSION < v"0.7.0-DEV.2005"
    using Base.Test
else
    using Test
end

println("Testing DotEnv")

const dir = dirname(@__FILE__)


@testset "basic" begin
    #basic input
    str = "BASIC=basic"
    file = joinpath(dir, ".env.override")
    file2 = joinpath(dir, ".env")

    #iobuffer, string, file
    @test DotEnv.parse(str) == Dict("BASIC"=>"basic")
    @test DotEnv.parse(read(file)) == Dict("CUSTOMVAL123"=>"yes","USER"=>"replaced value")
    @test DotEnv.config(file).dict == Dict("CUSTOMVAL123"=>"yes","USER"=>"replaced value")

    #should trigger a warning too, but I cant test that
    @test isempty(DotEnv.config("inexistentfile.env"))

    #length of returned values
    @test length(DotEnv.config(file2).dict) === 10

    #shouldn't replace ENV vars
    previous_value = ENV["USER"]
    cfg = DotEnv.config(file)

    @test ENV["USER"] != cfg["USER"]
    @test ENV["USER"] == previous_value

    #appropiately loaded into ENV if CUSTOM_VAL is non existent
    @test ENV["CUSTOMVAL123"] == "yes"

    # Can force override
    cfg = DotEnv.config(file, true)
    @test ENV["USER"] == cfg["USER"]
    @test ENV["USER"] == "replaced value"
    
    # Restore previous environment
    ENV["USER"] = previous_value

    # Test that EnvDict is reading from ENV
    ENV["SOME_RANDOM_KEY"] = "abc"
    cfg = DotEnv.config(file)
    @test !haskey(cfg.dict, "SOME_RANDOM_KEY")
    @test cfg["SOME_RANDOM_KEY"] == "abc"
    @test get(cfg, "OTHER_RANDOM_KEY", "zxc") == "zxc"

    #test alias
    @test DotEnv.load(file).dict == DotEnv.config(file).dict
end


@testset "parsing" begin

    #comment
    @test DotEnv.parse("#HIMOM") == Dict()

    #spaces without quotes
    @test begin
        p = DotEnv.parse("TEST=hi  the  re")
        count(c -> c == ' ', collect(p["TEST"])) == 4
    end

    #single quotes
    @test DotEnv.parse("TEST=''")["TEST"] == ""
    @test DotEnv.parse("TEST='something'")["TEST"] == "something"

    #double quotes
    @test DotEnv.parse("TEST=\"\"")["TEST"] == ""
    @test DotEnv.parse("TEST=\"something\"")["TEST"] == "something"

    #inner quotes are mantained
    @test DotEnv.parse("TEST=\"\"json\"\"")["TEST"] == "\"json\""
    @test DotEnv.parse("TEST=\"'json'\"")["TEST"] == "'json'"
    @test DotEnv.parse("TEST=\"\"\"")["TEST"] == "\""
    @test DotEnv.parse("TEST=\"'\"")["TEST"] == "'"

    #line breaks
    @test DotEnv.parse("TEST=\"\\n\"")["TEST"] == "" #It's null because of final trim
    @test DotEnv.parse("TEST=\"\\n\\n\\nsomething\"")["TEST"] == "something"
    @test DotEnv.parse("TEST=\"something\\nsomething\"")["TEST"] == "something\nsomething"
    @test DotEnv.parse("TEST=\"something\\n\\nsomething\"")["TEST"] == "something\n\nsomething"
    @test DotEnv.parse("TEST='\\n'")["TEST"] == "\\n"
    @test DotEnv.parse("TEST=\\n")["TEST"] == "\\n"

    #empty vars
    @test DotEnv.parse("TEST=")["TEST"] == ""

    #trim spaces with and without quotes
    @test DotEnv.parse("TEST='  something  '")["TEST"] == "something"
    @test DotEnv.parse("TEST=\"  something  \"")["TEST"] == "something"
    @test DotEnv.parse("TEST=  something  ")["TEST"] == "something"
    @test DotEnv.parse("TEST=    ")["TEST"] == ""
end

end # module
