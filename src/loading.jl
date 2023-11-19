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
    load!([env=ENV], path::AbstractString = ""; override::Bool=false)

Load the dotenv file `path`, or should `path` be a directory every
`ENV_FILENAME` that lies within it, into `env`.

Should `override` be set, values already present in `env` will be replaced with
statements from the dotenv file(s).
"""
function load!(env::AbstractDict{String, String}, files::Vector{<:AbstractString}; override::Bool=false)
    unload!(env, files)
    for file in files
        entries = open(_parse, file)
        stack = get!(() -> Pair{String, Vector{Pair{String, Tuple{String, Bool}}}}[], ENV_STACKS, env)
        push!(stack, EnvFile(abspath(file), entries, override))
        load!(env, entries; override)
    end
end

function load!(env::AbstractDict{String, String}, entries::Vector{EnvEntry}; override::Bool=false)
    orig = get!(() -> Dict{String, Union{String, Nothing}}(), ENV_ORIGINALS, env)
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

function load!(env::AbstractDict{String, String}, path::AbstractString = ""; override::Bool=false)
    path = abspath(path)
    if isdir(path)
        envfiles = filter(isfile, map(f -> joinpath(path, f), ENV_FILENAMES))
        if !isempty(envfiles)
            load!(env, if override envfiles else reverse(envfiles) end; override)
        elseif path != dirname(path) # Try a parent directory
            load!(env, dirname(path); override)
        end
    else
        load!(env, [path]; override)
    end
end

load!(path::AbstractString = ""; override::Bool=false) = load!(ENV, path; override)

"""
    unload!(env::AbstractDict{String, String}, path::AbstractString)
    unload!(ENV, path::AbstractString = "")

Unload the dotenv file `path` from `env`, or should `path` be a directory every
`ENV_FILENAMES` that lies within it.

When `env` is omitted, `ENV` is used and a `path` defaults to the current directory.
"""
function unload!(env::AbstractDict{String, String}, files::Vector{<:AbstractString})
    absfiles = map(abspath, files)
    (!haskey(ENV_STACKS, env) || !any(e -> e.path in absfiles, ENV_STACKS[env])) && return env
    stack = deepcopy(ENV_STACKS[env])
    unload!(env)
    ENV_ORIGINALS[env] = Dict{String, Union{String, Nothing}}()
    newstack = ENV_STACKS[env] = Vector{EnvFile}()
    for envfile in stack
        envfile.path in absfiles && continue
        push!(newstack, envfile)
        load!(env, envfile.entries; override=envfile.override)
    end
    env
end

function unload!(env::AbstractDict{String, String}, path::AbstractString)
    path = abspath(path)
    if isdir(path)
        envfiles = filter(isfile, map(f -> joinpath(path, f), ENV_FILENAMES))
        if !isempty(envfiles)
            unload!(env, envfiles)
        elseif path != dirname(path)
            unload!(env, dirname(path))
        end
    else
        unload!(env, [path])
    end
end

unload!(path::AbstractString = "") = unload!(ENV, path)

"""
    unload!(env::AbstractDict{String, String})

Undo all dotenv modifications to `env`.
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
