module DotEnv

include("types.jl")

const ENV_FILENAMES = # From <https://github.com/bkeepers/dotenv>, highest priority last
    [".env",       ".env.production",       ".env.test",       ".env.deployment",
     ".env.local", ".env.production.local", ".env.test.local", ".env.deployment.local"]

const ENV_STACKS = IdDict{AbstractDict{String, String}, Vector{EnvFile}}()
const ENV_ORIGINALS = IdDict{AbstractDict{String, String}, Dict{String, Union{String, Nothing}}}()

include("parser.jl")
include("loading.jl")

end
