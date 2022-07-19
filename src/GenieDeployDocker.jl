module GenieDeployDocker

import Genie
import GenieDeploy

DOCKER(; sudo::Bool = Sys.islinux()) = (sudo ? `sudo docker` : `docker`)

"""
    dockerfile(path::String = "."; user::String = "genie", env::String = "dev",
              filename::String = "Dockerfile", port::Int = 8000, dockerport::Int = 80, force::Bool = false)

Generates a `Dockerfile` optimised for containerizing Genie apps.

# Arguments
- `path::String`: where to generate the file
- `filename::String`: the name of the file (default `Dockerfile`)
- `user::String`: the name of the system user under which the Genie app is run
- `env::String`: the environment in which the Genie app will run
- `host::String`: the local IP of the Genie app inside the container
- `port::Int`: the port of the Genie app inside the container
- `dockerport::Int`: the port to use on the host (used by the `EXPOSE` directive)
- `force::Bool`: if the file already exists, when `force` is `true`, it will be overwritten
"""
function dockerfile(path::String = "."; filename::String = "Dockerfile", user::String = "genie", env::String = "dev",
                    host = "0.0.0.0", port::Int = 8000, dockerport::Int = 80, force::Bool = false, platform::String = "linux/amd64",
                    websockets_port::Int = port, websockets_dockerport::Int = dockerport, earlybind::Bool = true)
  filename = normpath(joinpath(path, filename))
  isfile(filename) && force && rm(filename)
  isfile(filename) && error("File $(filename) already exists. Use the `force = true` option to overwrite the existing file.")

  open(filename, "w") do io
    write(io, Generator.dockerfile(user = user, env = env, filename = filename, host = host,
                                        port = port, dockerport = dockerport, platform = platform,
                                        websockets_port = websockets_port, websockets_dockerport = websockets_dockerport))
  end

  "Docker file successfully written at $(abspath(filename))" |> println
end


"""
    build(path::String = "."; appname = "genie")

Builds the Docker image based on the `Dockerfile`
"""
function build(path::String = "."; appname::String = "genie", nocache::Bool = true, sudo::Bool = Sys.islinux())
  if nocache
    `$(DOCKER(sudo = sudo)) build --no-cache -t "$appname" $path`
  else
    `$(DOCKER(sudo = sudo)) build -t "$appname" $path`
  end |> GenieDeploy.run

  "Docker container successfully built" |> println
end


"""
    run(; containername::String = "genieapp", hostport::Int = 80, containerport::Int = 8000, appdir::String = "/home/genie/app",
        mountapp::Bool = false, image::String = "genie", command::String = "bin/server", rm::Bool = true, it::Bool = true)

Runs the Docker container named `containername`, binding `hostport` and `containerport`.

# Arguments
- `containername::String`: the name of the container of the Genie app
- `hostport::Int`: port to be used on the host for accessing the app
- `containerport::Int`: the port on which the app is running inside the container
- `appdir::String`: the folder where the app is stored within the container
- `mountapp::String`: if true the app from the host will be mounted so that changes on the host will be reflected when accessing the app in the container (to be used for dev)
- `image::String`: the name of the Docker image
- `command::String`: what command to run when starting the app
- `rm::Bool`: removes the container upon exit
- `it::Bool`: runs interactively
"""
function run(; containername::String = "genieapp", hostport::Int = 80, containerport::Int = 8000, appdir::String = "/home/genie/app",
                mountapp::Bool = false, image::String = "genie", command::String = "", rm::Bool = true, it::Bool = true,
                websockets_hostport::Int = hostport, websockets_containerport::Int = containerport, sudo::Bool = Sys.islinux())
  options = []

  it && push!(options, "-it")
  rm && push!(options, "--rm")

  push!(options, "-p")
  push!(options, "$hostport:$containerport")

  if websockets_hostport != hostport || websockets_containerport != containerport
    push!(options, "-p")
    push!(options, "$websockets_hostport:$websockets_containerport")
  end

  push!(options, "--name")
  push!(options, "$containername")

  if mountapp
    push!(options, "-v")
    push!(options,  "$(pwd()):$appdir")
  end

  push!(options, image)

  isempty(command) || push!(options, command)

  docker_command = replace(string(DOCKER(sudo = sudo)), "`" => "")
  "Starting docker container with `$docker_command run $(join(options, " "))`" |> println

  `$(DOCKER(sudo = sudo)) run $options` |> GenieDeploy.run
end

module Generator

"""
    dockerfile(; user::String = "genie", supervisor::Bool = false, nginx::Bool = false, env::String = "dev",
                      filename::String = "Dockerfile", port::Int = 8000, dockerport::Int = 80, host::String = "0.0.0.0",
                      websockets_port::Int = port, websockets_dockerport::Int = dockerport)

Generates dockerfile for the Genie app.
"""
function dockerfile(; user::String = "genie", supervisor::Bool = false, nginx::Bool = false, env::String = "dev",
                      filename::String = "Dockerfile", port::Int = Genie.config.server_port, dockerport::Int = 80,
                      host::String = "0.0.0.0", websockets_port::Int = port, platform::String = "",
                      websockets_dockerport::Int = dockerport, earlybind::Bool = true)
  appdir = "/home/$user/app"

  string(
  """
  # pull latest julia image
  FROM $(isempty(platform) ? "" : "--platform=$platform") julia:latest

  # create dedicated user
  RUN useradd --create-home --shell /bin/bash $user

  # set up the app
  RUN mkdir $appdir
  COPY . $appdir
  WORKDIR $appdir

  # configure permissions
  RUN chown $user:$user -R *

  RUN chmod +x bin/repl
  RUN chmod +x bin/server
  RUN chmod +x bin/runtask

  # switch user
  USER $user

  # instantiate Julia packages
  RUN julia -e "using Pkg; Pkg.activate(\\".\\"); Pkg.instantiate(); Pkg.precompile(); "

  # ports
  EXPOSE $port
  EXPOSE $dockerport
  """,

  (websockets_port != port ?
  """

  # websockets ports
  EXPOSE $websockets_port
  EXPOSE $websockets_dockerport
  """ : ""),

  """

  # set up app environment
  ENV JULIA_DEPOT_PATH "/home/$user/.julia"
  ENV GENIE_ENV "$env"
  ENV GENIE_HOST "$host"
  ENV PORT "$port"
  ENV WSPORT "$websockets_port"
  ENV EARLYBIND "$earlybind"
  """,

  """

  # run app
  CMD ["bin/server"]

  # or maybe include a Julia file
  # CMD julia -e 'using Pkg; Pkg.activate("."); include("IrisClustering.jl"); '
  """)
end

end # end module Generator


end
