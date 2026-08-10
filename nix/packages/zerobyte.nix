# Zerobyte - Self-hosted backup automation and management
# https://github.com/nicotsx/zerobyte
{
  pkgs,
  system,
  lib,
  config,
  shoutrrr,
}:

let
  isLinux = builtins.elem system [
    "x86_64-linux"
    "aarch64-linux"
  ];

  # Apply patches to upstream source
  patchedSrc = pkgs.applyPatches {
    name = "zerobyte-src-patched";
    src = config.zerobyte-src;
    patches = config.patches;
  };

  # Version from flake config (must match zerobyte-src tag)
  inherit (config) version;

  # Runtime tools the server shells out to. Upstream ships these in its
  # container image (see the Dockerfile "base" stage); on NixOS they come
  # from the wrapper PATH instead.
  runtimeTools = [
    pkgs.restic
    pkgs.rclone
    shoutrrr
    pkgs.openssh
  ]
  ++ lib.optionals isLinux [
    pkgs.fuse3
    pkgs.davfs2
    pkgs.sshfs # sftp volumes
    pkgs.cifs-utils # smb volumes
    pkgs.acl
    pkgs.attr
  ];

in
pkgs.stdenv.mkDerivation {
  pname = "zerobyte";
  inherit version;

  src = patchedSrc;

  nativeBuildInputs = [
    pkgs.bun2nix.hook
    pkgs.makeWrapper
  ];

  # Fetch bun dependencies using the lockfile from this flake
  # bun2nix.hook populates node_modules from these pre-fetched deps (fully offline)
  bunDeps = pkgs.bun2nix.fetchBunDeps {
    bunNix = config.bunNix;
  };

  # Build-time values baked into the client bundle. Upstream passes these as
  # Docker build args; the versions are shown in the UI's "about" panel, so
  # they must reflect what the wrapper actually puts on PATH.
  env = {
    VITE_APP_VERSION = version;
    VITE_RESTIC_VERSION = pkgs.restic.version;
    VITE_RCLONE_VERSION = pkgs.rclone.version;
    VITE_SHOUTRRR_VERSION = shoutrrr.version;
    VITE_GIT_HOOKS = "0"; # don't let lefthook touch git during the build
  };

  buildPhase = ''
    runHook preBuild

    export HOME=$(mktemp -d)

    # Ensure bun doesn't try to install/fetch anything (deps provided by bun2nix.hook)
    # Network is blocked by Nix sandbox, but this makes failures clearer
    export BUN_INSTALL_BIN=$HOME/.bun/bin

    # Build the application (vite build -> .output/)
    bun run build

    # The agent is a separate bundle, built exactly as upstream's Dockerfile does
    bun build apps/agent/src/index.ts --outfile .output/agent/index.mjs --target bun

    runHook postBuild
  '';

  # Mirrors upstream's "production" image layout: the vite build is
  # self-contained, so no node_modules is needed at runtime.
  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/zerobyte/assets/migrations
    mkdir -p $out/bin

    cp -r .output $out/lib/zerobyte/.output
    cp -r app/drizzle/* $out/lib/zerobyte/assets/migrations/
    cp package.json $out/lib/zerobyte/

    # Create wrapper script with runtime dependencies
    # --chdir ensures the server resolves its assets relative to the package dir
    makeWrapper ${pkgs.bun}/bin/bun $out/bin/zerobyte \
      --chdir $out/lib/zerobyte \
      --add-flags ".output/server/index.mjs" \
      --prefix PATH : ${lib.makeBinPath runtimeTools} \
      --set NODE_ENV "production"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Self-hosted backup automation and management";
    homepage = "https://github.com/nicotsx/zerobyte";
    license = licenses.agpl3Plus;
    platforms = platforms.unix;
    mainProgram = "zerobyte";
  };
}
