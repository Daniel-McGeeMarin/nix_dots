{ ... }:

# Wi-Fi on the Gram's Intel AX211 (iwlwifi). NetworkManager stays the brain --
# nmcli, the shells' Wi-Fi items and the rofi Wi-Fi tab (SUPER+N) all talk
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
#
# 4. NetworkManager alone decides what to join. With the iwd backend NM by
#    default leaves auto-connect to iwd, which keeps its own list of known
#    networks and its own ranking and ignores NM's profiles' autoconnect and
#    priority. With two deciders, iwd hopped to the open Avalon_WiFi whenever
#    the home signal dipped while NM was activating a profile, NM's attempt
#    failed ("net.connman.iwd.Failed"), and NM saved a fresh "<SSID> 1",
#    "<SSID> 2" copy each time. Found 2026-10-01: three home profiles, one
#    with an empty password and one with a 4-character one.
{
  boot.extraModprobeConfig = ''
    options cfg80211 ieee80211_regdom=US
  '';
  hardware.wirelessRegulatoryDatabase = true;

  networking.networkmanager.wifi = {
    backend = "iwd";
    powersave = false;
  };

  # Point 4: NM owns auto-connect, honouring each profile's autoconnect and
  # autoconnect-priority.
  networking.networkmanager.settings.device."wifi.iwd.autoconnect" = false;

  networking.wireless.iwd.settings = {
    # Point 3 for real: NM's wifi.powersave above only reaches the card on
    # the wpa_supplicant backend. With iwd it is iwd's own quirk. Power save
    # left on showed up as 16 "disassociated due to inactivity" (reason 4)
    # drops between 2026-09-25 and 10-01.
    DriverQuirks.PowerSaveDisable = "*";
    # NM does IP/DHCP and DNS; iwd only associates.
    General.EnableNetworkConfiguration = false;
    Settings.AutoConnect = true;
  };
}
