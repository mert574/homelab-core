#!/usr/bin/env bash
# Install the playground toolset on the Debian playground LXC. Debian LXC has no
# cloud-init runcmd, so this runs once from the bootstrap pipeline (pct exec or
# ssh as root). It installs the same kit as the NixOS playground plus ffmpeg, all
# at their current versions.
#
#   ssh root@192.168.178.108 'bash -s' < scripts/playground-debian-setup.sh

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt_base() {
  apt-get update
  apt-get install -y \
    build-essential gcc git curl wget unzip zip ca-certificates gnupg \
    apt-transport-https neovim ripgrep jq screen tmux ffmpeg \
    python3 python3-pip python3-venv libyaml-dev tealdeer
  # tealdeer's command is `tldr`; symlink if the package named it otherwise
  command -v tldr >/dev/null 2>&1 || ln -sf "$(command -v tealdeer)" /usr/local/bin/tldr
}

install_gh() {
  install -d -m 755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
  chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list
  apt-get update
  apt-get install -y gh
}

install_go() {
  local ver
  ver="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -1)"
  curl -fsSL "https://go.dev/dl/${ver}.linux-amd64.tar.gz" -o /tmp/go.tgz
  rm -rf /usr/local/go
  tar -C /usr/local -xzf /tmp/go.tgz
  # shellcheck disable=SC2016  # literal $PATH on purpose; expands at login time
  echo 'export PATH=$PATH:/usr/local/go/bin' > /etc/profile.d/go.sh
}

install_node() {
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
  npm install -g serve @bitwarden/cli @anthropic-ai/claude-code
}

install_awscli() {
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -q -o /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install --update
}

install_k8s_kit() {
  local kver
  kver="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  curl -fsSL "https://dl.k8s.io/release/${kver}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl
  chmod +x /usr/local/bin/kubectl

  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

  curl -fsSL https://github.com/derailed/k9s/releases/latest/download/k9s_linux_amd64.deb -o /tmp/k9s.deb
  apt-get install -y /tmp/k9s.deb

  curl -fsSL https://github.com/cilium/cilium-cli/releases/latest/download/cilium-linux-amd64.tar.gz -o /tmp/cilium.tgz
  tar -C /usr/local/bin -xzf /tmp/cilium.tgz cilium
}

install_sops() {
  local url
  url="$(curl -fsSL https://api.github.com/repos/getsops/sops/releases/latest \
    | grep -oE 'https://[^"]*amd64\.deb' | head -1)"
  curl -fsSL "$url" -o /tmp/sops.deb
  apt-get install -y /tmp/sops.deb
}

main() {
  apt_base
  install_gh
  install_go
  install_node
  install_awscli
  install_k8s_kit
  install_sops
  echo "playground-debian toolset installed."
}

main "$@"
