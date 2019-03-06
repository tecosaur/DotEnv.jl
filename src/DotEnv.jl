module DotEnv

"""
`DotEnv.parse` accepts a String or an IOBuffer (Any value that
 can be converted into String), and it will return a Dict with
 the parsed keys and values.
"""
function parse( src )
    res = Dict{String,String}()
    for line in split(String(src), '\n')
        m = match(r"^\s*([\w.-]+)\s*=\s*(.*)?\s*$", line)
        if m != nothing
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
function config( path=".env" )
    if (isfile(path))
        parsed = parse(String(read(path)))

        for (k, v) in parsed
            if( !haskey( ENV, k ) )
                ENV[k] = v
            end
        end

        return parsed
    else
        return nothing
    end
end

config( ;path=".env" ) = config(path)

load(opts...) = config(opts...)

end
