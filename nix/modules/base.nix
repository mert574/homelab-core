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
