using Documenter

push!(LOAD_PATH,  "../../src")

using GenieDeployDocker

makedocs(
    sitename = "GenieDeployDocker - Deploy Genie Apps with Docker",
    format = Documenter.HTML(prettyurls = false),
    pages = [
        "Home" => "index.md",
        "GenieDeployDocker API" => [
          "GenieDeployDocker" => "API/geniedeploydocker.md",
        ]
    ],
)

deploydocs(
  repo = "github.com/GenieFramework/GenieDeployDocker.jl.git",
)
