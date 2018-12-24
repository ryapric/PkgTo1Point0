module PkgTo1Point0

export migrate

dir = readdir(dirname(@__FILE__))
includes = filter(x -> (endswith(x, "jl") && x != "PkgTo1Point0.jl"), dir)
include.(includes)

end # module PkgTo1Point0
