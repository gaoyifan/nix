{pkgs}:
pkgs.inetutils.overrideAttrs (old: {
  pname = "inetutils-minimal";
  outputs = [
    "out"
    "man"
  ];
  configureFlags =
    old.configureFlags
    ++ [
      "--disable-clients"
      "--disable-servers"
      "--enable-telnet"
    ]
    ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
      "--enable-ping"
    ];
  postInstall = null;
})
