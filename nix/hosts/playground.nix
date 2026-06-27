# Scratch / experiment box: full dev kit (../modules/dev.nix) + ffmpeg. Nuke freely.
# Debian twin for non-Nix needs: see tofu/playground-debian.tf.
{ pkgs, ... }:
{
  imports = [ ../modules/base.nix ../modules/dev.nix ];

  networking.hostName = "playground";

  environment.systemPackages = [ pkgs.ffmpeg ];
}
