{
  darwinProfile,
  inputs,
  ...
}: {
  imports = [inputs.auto-pause-cemu.darwinModules.default];

  # Cemu and the paired DualSense controller are on the Mac Studio. Import the
  # module for every Darwin evaluation, but only start the agent on this host.
  services.auto-pause-cemu.enable = darwinProfile == "yifansmacstudio";
}
