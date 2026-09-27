{ ... }:

# Wi-Fi on the Gram's Intel AX211 (iwlwifi). NetworkManager stays the brain --
# nmcli, nm-applet, the shells' network widgets and the rofi Wi-Fi tab all talk
# to it -- but three things underneath it change:
#
# 1. A country code. With none set the card runs in the "00" world domain,
#    where 6 GHz is off-limits for starting a connection. Routers that
#    advertise one SSID on 2.4/5/6 GHz then pull wpa_supplicant onto the 6 GHz
#    radio, auth fails (CONN_FAILED at 6455 MHz), and it loops across bands for
#    minutes. That was the "wifi is terrible" in the journal.
#
# 2. iwd instead of wpa_supplicant as the Wi-Fi backend. It is Intel's own
#    daemon: faster connects, better WPA3/SAE and roaming between a router's
#    bands. NM keeps its saved profiles and hands them to iwd.
#
# 3. No Wi-Fi power saving: iwlwifi drops and stalls with it on.
{
  boot.extraModprobeConfig = ''
    options cfg80211 ieee80211_regdom=US
  '';
  hardware.wirelessRegulatoryDatabase = true;

  networking.networkmanager.wifi = {
    backend = "iwd";
    powersave = false;
  };

  networking.wireless.iwd.settings = {
    # NM does IP/DHCP and DNS; iwd only associates.
    General.EnableNetworkConfiguration = false;
    Settings.AutoConnect = true;
  };
}
