# WiFi AP on the onboard MediaTek MT7921, bridged into br-gnet.
{config, ...}: {
  services.hostapd = {
    enable = true;
    radios.wlp6s0 = {
      band = "5g";
      channel = 149;
      countryCode = "CN";
      wifi4.capabilities = ["HT40+" "SHORT-GI-20" "SHORT-GI-40"];
      wifi5.operatingChannelWidth = "80";
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
