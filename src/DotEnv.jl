module DotEnv

import Base: getindex, get, isempty

struct EnvDict
    dict::Dict{String, String}
end

getindex(ed::EnvDict, key) = get(ed.dict, key, ENV[key])
get(ed::EnvDict, key, default) = get(ed.dict, key, get(ENV, key, default))
isempty(ed::EnvDict) = isempty(ed.dict)

"""
`DotEnv.parse` accepts a String or an IOBuffer (Any value that
 can be converted into String), and it will return a Dict with
 the parsed keys and values.
"""
function parse( src )
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

            push!(res, Pair(key, value) )
        end
    end
    res
end


"""
`config` reads your .env file, parse the content, stores it to `ENV`,
and finally return a Dict with the content.
"""
function config( path=".env", override = false)
    if (isfile(path))
        parsed = parse(read(path, String))

        for (k, v) in parsed
            if( !haskey( ENV, k ) || override )
                ENV[k] = v
            end
        end

        return EnvDict(parsed)
    else
        return EnvDict(Dict{String, String}())
    end
end

config( ;path=".env", override = true ) = config(path, override)

load(opts...) = config(opts...)

end
