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
Base.haskey(eo::EnvOverlay, key::AbstractString) = haskey(eo.overlay, key) || haskey(eo.base, key)
Base.in(eo::EnvOverlay, keyval::Pair{<:AbstractString, <:AbstractString}) = keyval in eo.overlay || keyval in eo.base
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
