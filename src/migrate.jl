using Pkg

"""
    migrate(pkgdir::AbstractString = "."; suppress::Bool = false)

Edit files in package directory `pkgdir` to conform to `Pkg` 1.0+ requirements.
This includes:

- Replacing `REQUIRE` files with appropriate `Project/Manifest.toml` files.

- Adding `name` and `uuid` fields to `Project.toml`

# Examples

```jldoctest
using PkgTo1Point0

migrate("/path/to/PkgDir")

# output

    "Successfully migrated package structure at PkgDir to use Pkg v1.0+"
```
"""
function migrate(pkgdir::AbstractString = "."; suppress::Bool = false)
    VERSION >= v"1.0.0" || error("You should be updating Julia packages to v1.0+, *using* v1.0+, you hypocrite")

    oldpwd = pwd()

    cd(pkgdir)
    replaceREQUIRE("./REQUIRE")
    givename("./Project.toml", name = replace(dirname(pkgdir), ".jl" => ""), uuid = "123")

    cd(oldpwd)
    suppress || printstyled("\tSuccessfully migrated package structure at $pkgdir to use Pkg v1.0+\n",
                            bold = true, color = :green)
end

function replaceREQUIRE(file::String = "./REQUIRE")
    f_0 = split.(readlines(file))
    # Don't fight the nested Arrays from `split()`
    deps = String[]
    for i in f_0
        push!(deps, i[1])
    end
    
    # Remove strict julia dependency that appears in `REQUIRE`
    deps = filter(x -> !occursin(r"^julia", x), deps)

    # Add each dependency, which generates the .toml files
    Pkg.add(deps)

    # Remove REQUIRE
    rm(file)
end

function givename(file::String = "./Project.toml"; name::String, uuid::String)
    projfile = readlines(file)

    # Check for existing data in Project.toml
    hasname = any(occursin.("name = ", projfile)) | any(occursin.("uuid = ", projfile))
    if hasname return nothing end

    depsblock = projfile
    headerblock = ["name = \"$name\"", "uuid = \"$uuid\"", ""]
    contents = [headerblock; depsblock]

    open(file, "w") do f
        for i in contents
            write(f, i * "\n")
        end
    end
end
