{ fetchzip, stdenv, lib, libraryIndex, pkgsBuildHost, pkgs, arduinoPackages }:

with builtins;
let
  inherit (pkgs.callPackage ./lib.nix {}) convertHash latestVersion;
    
  libraries = mapAttrs (name: versions: let
    res = listToAttrs (map ({version, url, checksum, ...}: {
      name = version;
      value = stdenv.mkDerivation {
        pname = name;
        inherit version;

        installPhase = ''
          runHook preInstall

          mkdir -p "$out/libraries/$pname"
          cp -R * "$out/libraries/$pname/"

          runHook postInstall
        '';
        nativeBuildInputs = [ pkgs.unzip ];
        src = fetchurl ({
          url = url;
        } // (convertHash checksum));
      };
    }) versions);
  in res // { latest = latestVersion res; }) (groupBy ({ name, ... }: name) libraryIndex.libraries);
in
  libraries
