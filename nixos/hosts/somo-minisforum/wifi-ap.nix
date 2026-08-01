# WiFi AP on the onboard MediaTek MT7921, bridged into br-gnet.
{config, ...}: {
  # hostapd otherwise races networkd at boot, creates br-gnet itself, and
  # deletes the bridge (including its nspawn ports) when hostapd restarts.
  systemd.services.hostapd = {
    after = ["sys-subsystem-net-devices-br\\x2dgnet.device"];
    bindsTo = ["sys-subsystem-net-devices-br\\x2dgnet.device"];
  };

  services.hostapd = {
    enable = true;
    radios.wlp6s0 = {
      band = "5g";
      channel = 149;
      countryCode = "CN";
      # VHT/HE 80 MHz still needs the HT40 secondary-channel definition.
      wifi4.capabilities = ["HT40+"];
      # hostapd does not infer the VHT receive A-MPDU limit from the hardware.
      # Without this field, HE clients use much smaller aggregates for
      # client-to-AP traffic, severely reducing uplink throughput.
      wifi5 = {
        capabilities = ["MAX-A-MPDU-LEN-EXP7"];
        operatingChannelWidth = "80";
      };
      wifi6 = {
        enable = true;
        operatingChannelWidth = "80";
      };
      settings.he_oper_centr_freq_seg0_idx = 155;
      settings.vht_oper_centr_freq_seg0_idx = 155;

      networks.wlp6s0 = {
        ssid = "SOMO Workstation";
        authentication = let
          passwordFile = "${config.services.secrets.filesDir}/nixos/somo-minisforum/wifi-password";
        in {
          mode = "wpa3-sae-transition";
          wpaPasswordFile = passwordFile;
          saePasswordsFile = passwordFile;
        };
        settings.bridge = "br-gnet";
      };
    };
  };
}
