using Documenter
using IstatApi

DocMeta.setdocmeta!(IstatApi, :DocTestSetup, :(using IstatApi); recursive = true)

makedocs(
    modules = [IstatApi],
    sitename = "IstatApi.jl",
    authors = "Andrea Recine",
    doctest = true,
    warnonly = false,
    format = Documenter.HTML(
        canonical = "https://andrerecio.github.io/IstatApi.jl",
        prettyurls = get(ENV, "CI", "false") == "true",
    ),
    pages = [
        "Home" => "index.md",
        "Getting started" => "getting_started.md",
        "SDMX keys" => "keys.md",
        "Rate limits and cache" => "rate_limits.md",
        "API reference" => "api.md",
    ],
)

deploydocs(repo = "github.com/andrerecio/IstatApi.jl", devbranch = "main")
