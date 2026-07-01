# Admin / break-glass shell. On-demand jump box with the full kit (../modules/dev.nix).
{ ... }:
{
  imports = [ ../modules/base.nix ../modules/dev.nix ];
  networking.interfaces.eth0.ipv4.addresses = [{ address = "192.168.178.105"; prefixLength = 24; }];
}
