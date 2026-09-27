# Package set for zerobyte and dependencies
{
  pkgs,
  system,
  lib,
  config,
  bun2nixPkgs,
}:

let
  shoutrrr = import ./shoutrrr.nix {
    inherit pkgs system lib;
  };

  bunRuntime = pkgs.callPackage ./bun-runtime.nix { };

  zerobyte = import ./zerobyte.nix {
    inherit
      pkgs
      system
      lib
      config
      shoutrrr
      bunRuntime
      ;
  };

in
{
  inherit zerobyte shoutrrr;
}
