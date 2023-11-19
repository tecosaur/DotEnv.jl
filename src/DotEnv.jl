module DotEnv

include("types.jl")

const ENV_STACKS = IdDict{AbstractDict{String, String}, Vector{EnvFile}}()
const ENV_ORIGINALS = IdDict{AbstractDict{String, String}, Dict{String, Union{String, Nothing}}}()

include("parser.jl")
include("loading.jl")

end
