# Admin / break-glass shell. On-demand jump box with the full kit (../modules/dev.nix).
{ ... }:
{
  imports = [ ../modules/base.nix ../modules/dev.nix ];

  networking.hostName = "admin";
}
