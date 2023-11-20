@compile_workload begin
    parse("FOO=bar")
    parse(codeunits("FOO=bar"))
    parse(IOBuffer("FOO=bar"))
    parse("FOO=\$HOME")
    config(IOBuffer("FOO=bar\nBAZ=\$FOO"))
    load!(joinpath(dirname(@__DIR__), "test", ".env"))
    unload!(joinpath(dirname(@__DIR__), "test", ".env"))
end
