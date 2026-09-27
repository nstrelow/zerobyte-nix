# Newer bun than the one nixpkgs currently ships (see flake.nix comment),
# used only as the *runtime* interpreter for the built server bundle.
#
# v0.43.0's vite/rolldown build emits labeled-if statements
# (`a: if (...) { ... }`) that nixpkgs' bun 1.3.x cannot parse at load
# time (SyntaxError: Unexpected keyword 'if'). Upstream's own Dockerfile
# moved to oven/bun:1.4.2-alpine for the same reason. bun2nix.hook still
# uses nixpkgs' bun to fetch/build deps, which is unaffected — only the
# process that executes .output/server/index.mjs needs the newer engine.
{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  unzip,
  openssl,
}:

let
  version = "1.4.2";

  sources = {
    x86_64-linux = fetchurl {
      url = "https://github.com/oven-sh/bun/releases/download/bun-v${version}/bun-linux-x64.zip";
      hash = "sha256-NjaPrvdSeHXV/6UuU81IAhdB8qg+tiCKjdZAaNQiqRM=";
    };
    aarch64-linux = fetchurl {
      url = "https://github.com/oven-sh/bun/releases/download/bun-v${version}/bun-linux-aarch64.zip";
      hash = "sha256-VDKLvC2cjgyfiSxUTWbFeoO4QTnjSQnl7oF1jxrI/ac=";
    };
    x86_64-darwin = fetchurl {
      url = "https://github.com/oven-sh/bun/releases/download/bun-v${version}/bun-darwin-x64-baseline.zip";
      hash = "sha256-utW71s8U0JgNEV9ZVMn/kE32GdXplNLaH/zNPzFjALA=";
    };
    aarch64-darwin = fetchurl {
      url = "https://github.com/oven-sh/bun/releases/download/bun-v${version}/bun-darwin-aarch64.zip";
      hash = "sha256-kJh6OhbX21VtiGrD1VHnttPt8KHPQ6yu1iLoZ2vh0S8=";
    };
  };
in
stdenvNoCC.mkDerivation {
  pname = "bun-runtime";
  inherit version;

  src =
    sources.${stdenvNoCC.hostPlatform.system}
      or (throw "bun-runtime: unsupported system ${stdenvNoCC.hostPlatform.system}");

  sourceRoot =
    {
      aarch64-darwin = "bun-darwin-aarch64";
      x86_64-darwin = "bun-darwin-x64-baseline";
    }
    .${stdenvNoCC.hostPlatform.system} or null;

  strictDeps = true;
  nativeBuildInputs = [ unzip ] ++ lib.optionals stdenvNoCC.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = [ openssl ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm 755 ./bun $out/bin/bun
    ln -s $out/bin/bun $out/bin/bunx
    runHook postInstall
  '';

  meta = {
    description = "bun runtime pinned ahead of nixpkgs, for running zerobyte's server bundle";
    mainProgram = "bun";
    platforms = builtins.attrNames sources;
  };
}
