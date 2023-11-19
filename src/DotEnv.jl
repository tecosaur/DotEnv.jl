module DotEnv

struct EnvOverlay{B <: AbstractDict{String, String}} <: AbstractDict{String, String}
    base::B
    overlay::Dict{String, String}
end

function Base.getindex(eo::EnvOverlay, key::AbstractString)
    if haskey(eo.overlay, key)
        eo.overlay[key]
    elseif haskey(eo.base, key)
        eo.base[key]
    else
        throw(KeyError(key))
    end
end
Base.get(eo::EnvOverlay, key::AbstractString, default) = get(eo.overlay, key, get(eo.base, key, default))
Base.in(eo::EnvOverlay, key::AbstractString) = key in eo.overlay || key in eo.base
Base.isempty(eo::EnvOverlay) = isempty(eo.overlay)
Base.length(eo::EnvOverlay) = length(eo.overlay)
Base.iterate(eo::EnvOverlay) = iterate(eo.overlay)
Base.iterate(eo::EnvOverlay, i) = iterate(eo.overlay, i)

struct EnvEntry
    key::String
    value::String
    interpolate::Bool
end

struct EnvFile
    path::String
    entries::Vector{EnvEntry}
    override::Bool
end

const ENV_STACKS = IdDict{AbstractDict{String, String}, Vector{EnvFile}}()
const ENV_ORIGINALS = IdDict{AbstractDict{String, String}, Dict{String, Union{String, Nothing}}}()

"""
    _parse(source::Union{IO, AbstractString, AbstractVector{UInt8}})

Parse the `.env` content `source` into a vector of `Pair{String, Tuple{String, Bool}}` key-value-interpolate pairs.
"""
function _parse(src::IO)
    results = EnvEntry[]
    for line in eachline(src)
        keyval = tryparseline(line)
        !isnothing(keyval) && push!(results, keyval)
    end
    results
end

_parse(src::AbstractString) = _parse(IOBuffer(src))
_parse(src::AbstractVector{UInt8}) = _parse(IOBuffer(src))

"""
    parse(source::Union{IO, AbstractString, AbstractVector{UInt8}})

Parse the `.env` content `source` into a `Dict{String, String}`.
"""
parse(src::Union{<:IO, <:AbstractString, <:AbstractVector{UInt8}}) =
    Dict{String, String}(Iterators.map(e -> e.key => e.value, _parse(src)))

"""
    tryparseline(line::AbstractString)

Try to parse `line` according to the format introduced by
https://github.com/bkeepers/dotenv.

Returns a `Pair{String, String}` if parsing was successful, `nothing` otherwise.
"""
function tryparseline(line::AbstractString)
    sline = lstrip(line)
    all(isspace, sline) || startswith(sline, '#') && return # empty_line
    startswith(sline, "export") || startswith(sline, "export\t") &&
        return tryparseline(@view sline[ncodeunits("export")+1:end])
    keyend = keyend = findfirst(c -> isspace(c) || c in ('=', ':'), sline)
    isnothing(keyend) && return # no_assignment
    valoffset = something(findfirst(c -> !isspace(c) && c ∉ ('=', ':'), @view sline[keyend:end]), 2)
    valstart = keyend + valoffset - 1
    value = tryreadvalue(@view sline[valstart:end])
    isnothing(value) && return # malformed_value
    key = String(@view sline[1:keyend-1])
    EnvEntry(key, first(value), last(value))
end

"""
    tryreadvalue(valstring::AbstractString)

Try to extract the possibly quoted value from `valstring`, which may be
succeeded by a #-comment. Returns a tuple of the value and a `Bool` indicating
whether or not the value should be interpolated.
"""
function tryreadvalue(valstring::AbstractString)
    isempty(valstring) && return ("", true)
    valend = if first(valstring) in ('\'', '"')
        quotechr = first(valstring)
        point = nextind(valstring, firstindex(valstring))
        maxpoint = lastindex(valstring)
        escaped = false
        while point <= maxpoint
            if escaped
                escaped = false
            elseif valstring[point] == '\\'
                escaped = true
            elseif valstring[point] == quotechr
                break
            end
            point = nextind(valstring, point)
        end
        valstring[point] != quotechr && return # untermintated_value_quote
        point
    else
        commentstart = findfirst('#', valstring)
        if !isnothing(commentstart)
            commentstart - 1
        else
            lastindex(valstring)
        end
    end
    postvalue = findfirst(!isspace, @view valstring[nextind(valstring, valend):end])
    !isnothing(postvalue) && valstring[valend + postvalue] != '#' && return # trailing_garbage
    if first(valstring) == '"'
        String(replace((@view valstring[2:valend-1]), "\\n" => '\n', "\\r" => '\r')), true
    elseif first(valstring) == '\''
        String(@view valstring[2:valend-1]), false
    else
        String(rstrip(@view valstring[1:valend])), true
    end
end

function loadexpand!(dotenv::Dict{String, String}, entry::EnvEntry, fallback::AbstractDict{String, String}=ENV)
    dotenv[entry.key] = if !entry.interpolate || !occursin('$', entry.value)
        entry.value
    else
        interpolate(entry.value, dotenv, fallback)
    end
    dotenv
end

"""
    interpolate(value::String, dotenv::Dict{String, String}, fallback::AbstractDict{String, String})

Expand interpolations in `value`, returning the final result. Interpolated
values can be in the form `\$name`, `\${name}`, or `\${name:-default}` (with
nesting allowed within `default`). Values are looked up in `dotenv` then
`fallback`, with the empty string used if not present in either.
"""
function interpolate(value::String, dotenv::Dict{String, String}, fallback::AbstractDict{String, String})
    getenv(key) = get(dotenv, key, get(fallback, key, ""))
    isword(c) = 'a' <= c <= 'z' || 'A' <= c <= 'Z' || '0' <= c <= '9' || c == '_'
    interpval = IOBuffer()
    point = prevind(value, firstindex(value))
    maxpoint = lastindex(value)
    escaped = false
    while point < maxpoint
        point = nextind(value, point)
        if escaped
            escaped = false
            continue
        elseif value[point] == '\\'
            escaped = true
            continue
        elseif value[point] != '$' || point == maxpoint
            write(interpval, value[point])
            continue
        end
        point += ncodeunits('$')
        if value[point] == '{' # ${EXPR}
            escaped = false
            depth = 1
            start = point
            while point < maxpoint && depth > 0
                point = nextind(value, point)
                if escaped
                    escaped = false
                elseif value[point] == '\\'
                    escaped = true
                elseif value[point] == '{'
                    depth += 1
                elseif value[point] == '}'
                    depth -= 1
                end
            end
            depth > 0 && continue
            expr = @view value[start+1:point-1]
            if occursin(":-", expr) # ${NAME:-DEFAULT}
                key, default = split(expr, ":-", limit=2)
                if haskey(dotenv, key) || haskey(fallback, key)
                    write(interpval, getenv(key))
                else
                    write(interpval, interpolate(String(default), dotenv, fallback))
                end
            else # ${NAME}
                write(interpval, getenv(expr))
            end
        else # $NAME
            keylen = something(findfirst(!isword, @view value[point:end]), maxpoint - point + 2) - 1
            key = value[point:point+keylen-1]
            write(interpval, getenv(key))
            point = point + keylen - 1
        end
    end
    String(take!(interpval))
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

end
