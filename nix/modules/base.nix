{ config, pkgs, lib, modulesPath, ... }:

let
  # OSC52 pbcopy: pipe stdin into your local clipboard over SSH (headless
  # replacement for wl-clipboard). tmux: needs `set-clipboard on`.
  pbcopy = pkgs.writeShellScriptBin "pbcopy" ''
    printf '\033]52;c;%s\a' "$(base64 | tr -d '\n')"
  '';
in
{
  imports = [
    # LXC-appropriate defaults for a Proxmox container.
    "${modulesPath}/virtualisation/proxmox-lxc.nix"
  ];

  # claude-code and google-chrome are unfree.
  nixpkgs.config.allowUnfree = true;

  # flakes, so `nixos-rebuild --flake` works without the extra flag.
  #
  # The LAN Garage cache is an extra substituter: CI builds and signs each host
  # closure and pushes it there (see DEPLOY.md), so a re-apply pulls it prebuilt
  # instead of rebuilding on every box. fallback + a short connect-timeout mean a
  # missing or unreachable cache (first boot, before Garage is up) just falls back
  # to cache.nixos.org and local builds, so it never blocks a rebuild.
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    substituters = lib.mkAfter [ "http://nix-cache.garage.lan:3902" ];
    trusted-public-keys = lib.mkAfter [
      # TODO: the cache public key from `nix-store --generate-binary-cache-key`
      "nix-cache:REPLACE-base64-public-key"
    ];
    fallback = true;
    connect-timeout = 5;
  };

  # Every host resolves the LAN names from the one central file (the same file is
  # injected into the non-NixOS machines by scripts/inject-hosts.sh), so
  # nix-cache.garage.lan and the rest work without a DNS server. The ai box is on
  # the isolated bridge so those LAN IPs aren't routable there; the cache's
  # fallback + connect-timeout above mean it just builds locally on ai.
  networking.extraHosts = builtins.readFile ../../network/lan-hosts;

  time.timeZone = "Europe/Berlin";

  # SSH is how you get in. Keys only, no passwords.
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  users.users.mert = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      # TODO: your public key (same one used for the other guests)
      "ssh-ed25519 AAAA...REPLACE you@laptop"
    ];
  };
  security.sudo.wheelNeedsPassword = false;
  programs.zsh.enable = true;

  # Base CLI kit every NixOS box here gets. Host modules add their own on top.
  environment.systemPackages = with pkgs; [
    curl
    wget
    git
    neovim
    ripgrep
    jq
    tealdeer # binary is already `tldr`, no symlink needed
    gh
    unzip
    zip
    screen
    tmux
    pbcopy
    gcc
    gnumake
    binutils
  ];

  system.stateVersion = "26.05";
}
