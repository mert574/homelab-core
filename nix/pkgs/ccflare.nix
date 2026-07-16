# ccflare packaged as a Nix derivation, so the box runs an immutable /nix/store
# tree instead of doing `git clone` + `bun install` + `bun run build:clients` in a
# systemd oneshot at runtime (which turned a service restart into a multi-hour
# rebuild). Built once (in CI), pushed to the Garage cache, substituted on apply.
#
# ccflare is a Bun workspace monorepo with no release artifact. The server runs
# straight from TypeScript (`bun run apps/server/src/server.ts`), so there is no
# server compile step; only the dashboard + tui are built. node_modules is needed
# at runtime, and its workspace symlinks point back into the tree, so deps and the
# built tree are vendored together in ONE fixed-output derivation (`tree`) rather
# than split. A thin non-FOD wrapper adds bin/ccflare -- the wrapper references
# bun's store path, which an FOD may not contain, so it must live outside `tree`.
#
# FIXED-OUTPUT: `bun install` needs the network, so `tree` is an FOD. When the ref
# or bun.lock changes, set its `outputHash` to lib.fakeHash, build, copy the "got:"
# hash back. Reproducibility is load-bearing (CI must reproduce this exact hash or
# the build fails); verified stable across independent builds at this ref.
{ lib
, stdenvNoCC
, fetchFromGitHub
, bun
, cacert
, makeWrapper
}:

let
  version = "0-unstable-2025-07-01";
  rev = "95c4c6a12d11598386333972e04cf1567c5a1298";

  src = fetchFromGitHub {
    owner = "snipeship";
    repo = "ccflare";
    inherit rev;
    hash = "sha256-SlBCR5A79IhFlchm415G4mir2UenfGoQf26rLWVuQ4E=";
  };

  # FOD: source + vendored bun deps + built dashboard/tui. Contains NO /nix/store
  # references (FOD rule) -- wrapping happens in the outer derivation.
  tree = stdenvNoCC.mkDerivation {
    pname = "ccflare-tree";
    inherit version src;
    nativeBuildInputs = [ bun ];
    dontConfigure = true;
    # bun blocks dependency postinstall scripts by default, so the desktop app's
    # electrobun runtime is never fetched. Build ONLY the dashboard, not the full
    # `build:clients`: `build:tui` runs `bun build --compile`, which bakes the nix
    # bun runtime (and thus glibc) into a standalone binary -- a /nix/store
    # reference an FOD may not contain. The server serves the dashboard and never
    # uses the compiled tui, so dropping it keeps the tree store-reference-free.
    buildPhase = ''
      runHook preBuild
      export HOME="$TMPDIR"
      export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
      bun install --frozen-lockfile --no-progress
      bun run build:dashboard
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -R ./. "$out/"
      runHook postInstall
    '';
    dontFixup = true;
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-MRST1+TsIk2irbyusd2RKdgGGzuCYo3797c8//TLTKk=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "ccflare";
  inherit version;

  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];

  # `bun run start` == `bun run apps/server/src/server.ts`, run from the tree root
  # (where package.json is). State (DB/config) lives outside the store via the
  # ccflare_DB_PATH / ccflare_CONFIG_PATH env the service sets.
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    # `bun run start` re-invokes `bun` by name for the package.json script, so bun
    # must be on PATH, not just the exec target.
    makeWrapper ${bun}/bin/bun "$out/bin/ccflare" \
      --add-flags "run start" \
      --prefix PATH : ${bun}/bin \
      --chdir ${tree}
    runHook postInstall
  '';

  passthru = { inherit tree; };

  meta = {
    description = "Multi-account load-balancing proxy for Anthropic/OpenAI (Bun)";
    homepage = "https://github.com/snipeship/ccflare";
    mainProgram = "ccflare";
  };
}
