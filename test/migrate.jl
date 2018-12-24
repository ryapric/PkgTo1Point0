"""
Tests based on the DataFrames package files as of 2018-12-23, which do not use
`Pkg` as of that date.
"""

using Test
using Pkg
using PkgTo1Point0

rm("./newpkg", force = true, recursive = true)
cp("./oldpkg", "./newpkg", force = true)
Pkg.activate("./newpkg")

@testset "replaceREQUIRE" begin
    PkgTo1Point0.replaceREQUIRE("./newpkg/REQUIRE")

    @test isfile("./newpkg/Project.toml")
    @test isfile("./newpkg/Manifest.toml")
    
    # Can't pass anything other than a String as pkgdir
    @test_throws MethodError migrate(1)
    @test_throws MethodError migrate(["abc", "123"]) 
end

@testset "givename" begin
    name = "DataFrames"
    uuid = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
    PkgTo1Point0.givename("./newpkg/Project.toml", name = name, uuid = uuid)
    
    projfile = readlines("./newpkg/Project.toml")
    @test projfile[1] == "name = \"$name\""
    @test projfile[2] == "uuid = \"$uuid\""

    # Won't touch existing Project.toml files if they have correct data
    existing_projfile = "./newpkg/Project-existing.toml"
    PkgTo1Point0.givename(existing_projfile, name = "x", uuid = "x")
    @test readlines("./newpkg/Project-existing.toml")[1] == "name = \"TotallyNotDataFrames\""
end

Pkg.activate(".")
rm("./newpkg", force = true, recursive = true)
