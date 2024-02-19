# Code for parsing a .env file

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
            value[point] in ('{', '}', '$') || write(interpval, '\\')
            write(interpval, value[point])
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
