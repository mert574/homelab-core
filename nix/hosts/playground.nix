# Scratch / experiment box: full dev kit (../modules/dev.nix) + ffmpeg. Nuke freely.
# Debian counterpart: see tofu/playground-debian.tf.
{ pkgs, ... }:
{
  imports = [ ../modules/base.nix ../modules/dev.nix ];
  networking.interfaces.eth0.ipv4.addresses = [{ address = "192.168.178.107"; prefixLength = 24; }];

  environment.systemPackages = [ pkgs.ffmpeg ];
}
