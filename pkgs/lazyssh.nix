# Custom lazyssh package using gaoyifan/lazyssh fork
{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule {
  pname = "lazyssh";
  version = "0.3.0-gaoyifan";

  src = fetchFromGitHub {
    owner = "gaoyifan";
    repo = "lazyssh";
    rev = "f6258bf0d01c5d92a2c3363d97279dffe58fbf09";
    hash = "sha256-wZRcIOWvX2k44zLjZ5wwrrAWQoMJu+aVGgqGoRVYQJ8=";
  };

  vendorHash = "sha256-OMlpqe7FJDqgppxt4t8lJ1KnXICOh6MXVXoKkYJ74Ks=";

  ldflags = [
    "-s"
    "-w"
  ];

  meta = with lib; {
    homepage = "https://github.com/gaoyifan/lazyssh";
    description = "A jump-host SSH server that starts machines on-demand";
    license = licenses.mit;
    mainProgram = "lazyssh";
  };
}
