{
  lib,
  python3,
  fetchPypi,
}:
python3.pkgs.buildPythonPackage rec {
  pname = "honcho-ai";
  version = "2.5.1";
  format = "wheel";

  src = fetchPypi {
    pname = "honcho_ai";
    inherit version format;
    dist = "py3";
    python = "py3";
    abi = "none";
    platform = "any";
    hash = "sha256-7zVMCGsF2RG4+dsUzFUkiP/TMuV5R+4DeLuzZX9RzX4=";
  };

  dependencies = with python3.pkgs; [httpx pydantic];
  pythonImportsCheck = ["honcho"];

  meta = {
    description = "Official Python SDK for Honcho memory infrastructure";
    homepage = "https://github.com/plastic-labs/honcho";
    license = lib.licenses.asl20;
  };
}
