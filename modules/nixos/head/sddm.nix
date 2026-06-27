{ config, inputs, pkgs, ... }:
{
  environment.systemPackages = with pkgs; lib.mkIf config.services.displayManager.sddm.enable [
    (pkgs.sddm-sugar-dark.override {
      themeConfig = {
        Background = "${inputs.gruvbox-wallpapers}/wallpapers/mix/xavier-cuenca-w4-3.jpg";
        FontWeight = "DemiBold";
        MainColor = "#ebdbb2";
        AccentColor = "#d65d0e";
        Locale = "ja_JP.UTF-8";
        HourFormat = "aphh時mm分";
        DateFormat = "yyyy年MM月dd日, dddd";
        HeaderText = "へようこそ!";
        TranslatePlaceholderUsername = "ユーザー";
        TranslatePlaceholderPassword = "パスワード";
        TranslateShowPassword = "見る";
        TranslateLogin = "ログイン";
      };
    })
  ];
  services.displayManager.sddm = {
    wayland.enable = true;
    theme = "sugar-dark";
    extraPackages = [ pkgs.sddm-sugar-dark pkgs.noto-fonts-cjk-sans pkgs.libsForQt5.qt5.qtgraphicaleffects ];
  };
}
