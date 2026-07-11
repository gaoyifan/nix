{
  pkgs,
  username,
  ...
}: let
  stateDir = "/Users/${username}/Library/Caches/whisper-server";
in {
  launchd.daemons.whisper-server = {
    path = [pkgs.ffmpeg];
    script = ''
      ${pkgs.coreutils}/bin/install -d -m 0750 ${stateDir} ${stateDir}/tmp
      cd ${stateDir}
      exec ${pkgs.whisper-cpp}/bin/whisper-server \
        -m ${pkgs.whisper-large-v3-turbo} \
        -l zh -t 12 -bs 1 -bo 1 -nf \
        --host 0.0.0.0 --port 8178 --convert \
        --tmp-dir ${stateDir}/tmp
    '';
    serviceConfig = {
      KeepAlive = true;
      UserName = username;
      StandardOutPath = "/dev/null";
      StandardErrorPath = "/dev/null";
      ThrottleInterval = 5;
    };
  };
}
