# Shared dev + cloud/k8s toolset. Imported by the hosts that should have the full
# kit (admin, playground). Host-specific or fast-moving tools (ffmpeg, the AI CLIs
# from unstable) stay in the host files, not here.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    libyaml

    # languages and runtimes (no nvm; node is pinned)
    go
    nodejs_22
    python3

    # node tools that used to be `npm i -g`
    nodePackages.serve
    bitwarden-cli # provides `bw`
    claude-code

    # cloud + kubernetes kit
    awscli2
    kubectl
    kubernetes-helm
    k9s
    cilium-cli
    sops
  ];
}
