module DotEnv

struct EnvDict
    dict::Dict{String, String}
end

Base.getindex(ed::EnvDict, key) = get(ed.dict, key, ENV[key])
Base.get(ed::EnvDict, key, default) = get(ed.dict, key, get(ENV, key, default))
Base.isempty(ed::EnvDict) = isempty(ed.dict)

"""
    parse(source::Union{IO, AbstractString, AbstractVector{UInt8}})

Parse the `.env` content `source` into a vector of `Pair{String, String}` key-value pairs.
"""
function parse(src::IO)
    results = Pair{String, String}[]
    for line in eachline(src)
        keyval = tryparseline(line)
        !isnothing(keyval) && push!(results, keyval)
    end
    results
end

parse(src::AbstractString) = parse(IOBuffer(src))
parse(src::AbstractVector{UInt8}) = parse(IOBuffer(src))

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
    key => String(value)
end

"""
    tryreadvalue(valstring::AbstractString)

Try to extract the possibly quoted value from `valstring`, which may be
succeeded by a #-comment.
"""
function tryreadvalue(valstring::AbstractString)
    isempty(valstring) && return ""
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
        replace((@view valstring[2:valend-1]), "\\n" => '\n', "\\r" => '\r')
    elseif first(valstring) == '\''
        @view valstring[2:valend-1]
    else
        rstrip(@view valstring[1:valend])
    end
end

"""
    config(path::AbstractString, override::Bool=false)

Read the `.env` file `path`, parse its content, and store the result to `ENV`.
Should override be set, values already present in `ENV` will be replaced with
statements from `path`.
"""
function config(path::AbstractString, override::Bool=false)
    if (isfile(path))

        parsed = Dict(open(parse, path))
        for (k, v) in parsed
            if(!haskey(ENV, k) || override)
                ENV[k] = v
            end
        end

        return EnvDict(parsed)
    else
        return EnvDict(Dict{String, String}())
    end
end

config(; path=".env", override = false) = config(path, override)

const load = config

end
