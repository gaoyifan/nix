# SSH public keys shared by all hosts.
# Imported as a plain attrset (not a NixOS module):
#   inherit (import ./ssh-keys.nix) sshKeys;
let
  userKeys = {
    yifan-macbook = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC+l3c7ONl5V8R7AdB8J+UOTR22P6k3pTOpiPfAJc/lDX5q9kCrGJIi3qIp83Xm8VYIhP+UBYOUsG+aF5iBj6URCNeI1HkHdi62JVvHo47BO1EagRz0Mqsx2JJZlMnWPnPahVxtd1Xn67CFcoPLuMoLu0gLyiMH0rGLq3jIS/qEyWUizSxgdzBvV31EKfYmTmIhLukt8RsVUv9NB0bSREmufpd+qGy17vu4Fb/NGqBIB8iGDtKe0PSMfe0p2DQig8lgEG4hnlaG6d9B3VeJgdM1oZU6/z8Fq285oQrzMHWJBEOmAQLirCtWM2id5/FdCzjXrkG4vBGGy1iwdAg96fph yifan@macbook";
  };
in {
  inherit userKeys;
  sshKeys = builtins.attrValues userKeys;
}
