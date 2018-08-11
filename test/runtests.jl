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
    @test DotEnv.config(file) == Dict("CUSTOMVAL123"=>"yes","USER"=>"replaced value")

    #should trigger a warning too, but I cant test that
    @test DotEnv.config("inexistentfile.env") == nothing

    #length of returned values
    @test length(DotEnv.config(file2)) === 10

    #shouldn't replace ENV vars
    previous_value = ENV["USER"]
    cfg = DotEnv.config(file)

    @test ENV["USER"] != cfg["USER"]
    @test ENV["USER"] == previous_value

    #appropiately laoded into ENV if CUSTOM_VAL is non existent
    @test ENV["CUSTOMVAL123"] == "yes"

    #test alias
    @test DotEnv.load(file) == DotEnv.config(file)
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


