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

const ENV_STACKS = IdDict{AbstractDict{String, String}, Vector{Pair{String, Vector{Pair{String, Tuple{String, Bool}}}}}}()
const ENV_ORIGINALS = IdDict{AbstractDict{String, String}, Dict{String, String}}()

"""
    _parse(source::Union{IO, AbstractString, AbstractVector{UInt8}})

Parse the `.env` content `source` into a vector of `Pair{String, Tuple{String, Bool}}` key-value-interpolate pairs.
"""
function _parse(src::IO)
    results = Pair{String, Tuple{String, Bool}}[]
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
    Dict{String, String}(Iterators.map(kqv -> first(kqv) => first(last(kqv)), _parse(src)))

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
    key => value
end

"""
    tryreadvalue(valstring::AbstractString)

Try to extract the possibly quoted value from `valstring`, which may be
succeeded by a #-comment.
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

function loadexpand!(dotenv::Dict{String, String}, (key, (val, interp))::Pair{String, Tuple{String, Bool}}, fallback::AbstractDict{String, String}=ENV)
    dotenv[key] = if !interp || !occursin('$', val)
        val
    else
        interpolate(val, dotenv, fallback)
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
function config(entries::Vector{Pair{String, Tuple{String, Bool}}}; env::AbstractDict{String, String} = ENV)
    dotenv = Dict{String, String}()
    for entry in entries
        loadexpand!(dotenv, entry, env)
    end
    EnvOverlay(env, dotenv)
end

config(src::IO; env::AbstractDict{String, String} = ENV) =
    config(_parse(src); env)

function config(path::AbstractString = ".env"; env::AbstractDict{String, String} = ENV)
    !isfile(path) && return EnvOverlay(env, Dict{String, String}())
    config(open(_parse, src); env)
end

"""
    load(path::AbstractString; override::Bool=false, env = ENV)

Read the `.env` file `path`, parse its content, and store the result to `env`.
Should `override` be set, values already present in `env` will be replaced with
statements from `path`.
"""
function load(path::AbstractString = ".env"; override::Bool=false, env::AbstractDict{String, String} = ENV)
    if !isfile(path)
        @warn "Dotenv file '$path' does not exist"
        return EnvDict(Dict{String, String}())
    end
    cfg = config(path, env)
    for (key, val) in cfg.dict
        if !haskey(env, key) || override
            env[key] = val
        end
    end
end

end
