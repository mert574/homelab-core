# secrets

The repo is public, so the rule is simple: **only age-encrypted files live here.**
Plaintext secret files and the age private key are gitignored and must never be
committed (on a public repo a plaintext commit leaks instantly, and git history
is forever).

- `homelab.env.example` - template, committed, no real values
- `homelab.env` - your filled-in plaintext, **gitignored**, delete after encrypting
- `homelab.enc.env` - the sops-encrypted version, **committed**
- the age **private** key - never here; on the box at
  `/root/.config/sops/age/keys.txt` and in your own backup only

## Why this is safe on a public repo

age encrypts with X25519 + ChaCha20-Poly1305, so the ciphertext being
world-readable is fine. Security rests entirely on the age private key staying
private. nothing inbound is open either (Cloudflare tunnels are outbound only),
so a public topology is recon-only, not an attack surface.

## Git token for private repos

This repo is public, but the pipeline pulls private ones (app source, private
manifests). `GIT_HTTP_TOKEN` in the env covers that: provisioning clones use it,
and Argo CD takes it as repo credentials to sync private repos. Keep it a
read-only fine-grained PAT scoped to just those repos, with an expiry, and rotate
it. The box needs it to function, so a compromised box exposes it. Small scope
keeps that blast radius small.

## Guardrail

Add a pre-commit secret scan (e.g. gitleaks) so a plaintext value can never slip
into a commit. On a public repo that check is the safety net.
