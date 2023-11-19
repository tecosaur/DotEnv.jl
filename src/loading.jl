function loadexpand!(dotenv::Dict{String, String}, entry::EnvEntry, fallback::AbstractDict{String, String}=ENV)
    dotenv[entry.key] = if !entry.interpolate || !occursin('$', entry.value)
        entry.value
    else
        interpolate(entry.value, dotenv, fallback)
    end
    dotenv
end

"""
    config(src::IO; env::AbstractDict{String, String} = ENV)
    config(path::AbstractString = ".env"; env::AbstractDict{String, String} = ENV)

Read the dotenv file `src`/`path` and return an `EnvOverlay` of its values,
expanding interpolated values with `env`.

Should the file `path` exist, an empty `EnvOverlay` is silently returned.
"""
function config(entries::Vector{EnvEntry}; env::AbstractDict{String, String} = ENV, override::Bool = false)
    dotenv = Dict{String, String}()
    for entry in entries
        if override || !haskey(env, entry.key)
            loadexpand!(dotenv, entry, env)
        end
    end
    EnvOverlay(env, dotenv)
end

config(src::IO; env::AbstractDict{String, String} = ENV, override::Bool = false) =
    config(_parse(src); env, override)

function config(path::AbstractString = ".env"; env::AbstractDict{String, String} = ENV, override::Bool = false)
    isfile(path) || return EnvOverlay(env, Dict{String, String}())
    config(open(_parse, path); env, override)
end

"""
    load!([env=ENV], path::AbstractString = ".env"; override::Bool=false)

Read the `.env` file `path`, parse its content, and store the result to `env`.
Should `override` be set, values already present in `env` will be replaced with
statements from `path`.
"""
function load!(env::AbstractDict{String, String}, path::AbstractString = ".env"; override::Bool=false)
    isfile(path) || return EnvOverlay(env, Dict{String, String}())
    unload!(env, path)
    entries = open(_parse, path)
    orig = get!(() -> Dict{String, Union{String, Nothing}}(), ENV_ORIGINALS, env)
    stack = get!(() -> Pair{String, Vector{Pair{String, Tuple{String, Bool}}}}[], ENV_STACKS, env)
    push!(stack, EnvFile(abspath(path), entries, override))
    cfg = config(entries; env, override)
    for (key, val) in cfg.overlay
        if !haskey(env, key)
            orig[key] = nothing
            env[key] = val
        elseif override
            get!(orig, key, env[key])
            env[key] = val
        end
    end
end

load!(path::AbstractString = ".env"; override::Bool=false) = load!(ENV, path; override)

"""
    unload!(env::AbstractDict{String, String}, path::AbstractString)
    unload!(ENV, path::AbstractString = ".env")

Unload the dotenv file `path` from `env`. When `env` is omitted, `ENV` is used
and a default `path` of `.env` is used.
"""
function unload!(env::AbstractDict{String, String}, path::AbstractString)
    uabspath = abspath(path)
    (!haskey(ENV_STACKS, env) || !any(e -> e.path == uabspath, ENV_STACKS[env])) && return env
    stack = deepcopy(ENV_STACKS[env])
    unload!(env)
    orig = ENV_ORIGINALS[env] = Dict{String, Union{String, Nothing}}()
    newstack = ENV_STACKS[env] = Vector{EnvFile}()
    for envfile in stack
        envfile.path == uabspath && continue
        push!(newstack, envfile)
        cfg = config(envfile.entries; env, override=envfile.override)
        for (key, val) in cfg.overlay
            if !haskey(env, key)
                orig[key] = nothing
                env[key] = val
            elseif envfile.override
                get!(orig, key, env[key])
                env[key] = val
            end
        end
    end
    env
end

unload!(path::AbstractString = ".env") = unload!(ENV, path)

"""
    unload!(env::AbstractDict{String, String})

Unload all dotenv modifications to `env`.
"""
function unload!(env::AbstractDict{String, String})
    orig = get!(() -> Dict{String, Union{String, Nothing}}(), ENV_ORIGINALS, env)
    for (key, val) in orig
        if val isa String
            env[key] = val
        else # isa Nothing
            delete!(env, key)
        end
    end
    delete!(ENV_ORIGINALS, env)
    delete!(ENV_STACKS, env)
    env
end
