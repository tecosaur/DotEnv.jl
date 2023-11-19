module DotEnv

import Base: getindex, get, isempty

struct EnvDict
    dict::Dict{String, String}
end

getindex(ed::EnvDict, key) = get(ed.dict, key, ENV[key])
get(ed::EnvDict, key, default) = get(ed.dict, key, get(ENV, key, default))
isempty(ed::EnvDict) = isempty(ed.dict)

"""
    parse(source::Union{<:AbstractString, <:AbstractVector{UInt8}, IOBuffer})

Parse the `.env` content `source` into a key-value `Dict{String, String}`.
"""
function parse(src::Union{<:AbstractString, <:AbstractVector{UInt8}, IOBuffer})
    res = Dict{String,String}()
    src = IOBuffer(src)
    for line in eachline(src)
        m = match(r"^\s*([\w.-]+)\s*=\s*(.*)?\s*$", line)
        if m !== nothing
            key = m.captures[1]
            value = string(m.captures[2])

            if (length(value) > 0 && value[1] === '"' && value[end] === '"')
                value = replace(value, r"\\n"m => "\n")
            end

            value = replace(value, r"(^['\u0022]|['\u0022]$)" => "")

            value = strip(value)

            push!(res, Pair(key, value))
        end
    end
    res
end


"""
    config(path::AbstractString, override::Bool=false)

Read the `.env` file `path`, parse its content, and store the result to `ENV`.
Should override be set, values already present in `ENV` will be replaced with
statements from `path`.
"""
function config(path::AbstractString, override::Bool=false)
    if (isfile(path))
        parsed = parse(read(path, String))

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
