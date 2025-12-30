# Custom lazyssh package using gaoyifan/lazyssh fork
{pkgs}:
pkgs.lazyssh.overrideAttrs (oldAttrs: {
  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "lazyssh";
    rev = "f6258bf0d01c5d92a2c3363d97279dffe58fbf09";
    hash = "sha256-wZRcIOWvX2k44zLjZ5wwrrAWQoMJu+aVGgqGoRVYQJ8=";
  };

  # vendorHash may need updating if dependencies differ
  vendorHash = "sha256-OMlpqe7FJDqgppxt4t8lJ1KnXICOh6MXVXoKkYJ74Ks=";

  meta = oldAttrs.meta // {
    homepage = "https://github.com/gaoyifan/lazyssh";
  };
})

