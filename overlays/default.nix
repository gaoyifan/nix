# Custom packages overlay
# Makes packages from ./pkgs available as pkgs.lazyssh, etc.
_final: prev: import ../pkgs prev
