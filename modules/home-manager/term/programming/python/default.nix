{ config, lib, pkgs, inputs, osConfig, ... }:
{
  options = {
    programming.python = {
      enable = lib.mkEnableOption "Enable programming";
    };
  };
  config = lib.mkIf config.programming.python.enable {
    home.packages = with pkgs; [
      (pkgs.python3.withPackages (python-pkgs: with python-pkgs; [
        matplotlib
        scipy
        numpy
        sympy
        pandas
      ]))
    ];
  };
}
