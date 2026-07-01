# AI sandbox. Isolated on the host (bootstrap/host-network/): internet yes, LAN no.
# Untrusted; the AI can do whatever inside it.
{ pkgs, unstable, lib, ... }:
{
  imports = [ ../modules/base.nix ];
  networking.interfaces.eth0.ipv4.addresses = [{ address = "10.10.10.10"; prefixLength = 24; }];
  networking.defaultGateway = "10.10.10.1";

  # LAN-isolated, so Pi-hole is unreachable; use public DNS.
  networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];

  environment.systemPackages =
    # browser + runtimes from stable
    (with pkgs; [
      chromium # headless browser for the agent to drive
      nodejs_22
      python3
      ffmpeg
    ])
    # AI CLIs move fast, so pull them from unstable for fresher versions
    ++ (with unstable; [
      claude-code
      opencode
      codex
    ]);

  # Point puppeteer/playwright at the nix chromium (their own download won't run on NixOS).
  environment.variables = {
    CHROME_BIN = "${pkgs.chromium}/bin/chromium";
    PUPPETEER_EXECUTABLE_PATH = "${pkgs.chromium}/bin/chromium";
    PUPPETEER_SKIP_DOWNLOAD = "1";
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH = "${pkgs.chromium}/bin/chromium";
  };
}
