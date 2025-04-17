{ fetchzip, stdenv, lib, packageIndex, pkgsBuildHost, pkgs, arduinoPackages }:

with builtins;
let
  inherit (pkgsBuildHost.xorg) lndir;
  inherit (pkgs.callPackage ./lib.nix {}) latestVersion selectSystem convertHash;

  # Tools are installed in $platform_name/tools/$name/$version
  tools = listToAttrs (map ({ name, tools, ... }: {
    inherit name;
    value = let platformName = name; in mapAttrs (_: versions: let
      res = listToAttrs (map ({name, version, systems, ...}: {
        name = version;
        value = let
          system = selectSystem stdenv.hostPlatform.system systems;
        in
          if system == null then
            throw "Unsupported platform ${stdenv.hostPlatform.system}"
          else
            stdenv.mkDerivation {
              pname = "${platformName}-${name}";
              inherit version;

              dirName = "packages/${platformName}/tools/${name}/${version}";
              installPhase = ''
                mkdir -p "$out/$dirName"
                cp -R * "$out/$dirName/"
              '';
              nativeBuildInputs = [ pkgs.unzip ];
              src = fetchurl ({
                url = system.url;
              } // (convertHash system.checksum));
            };
      }) versions);
    in res // { latest = latestVersion res; }) (groupBy ({ name, ... }: name) tools);
  }) packageIndex.packages);
    
  # Platform are installed in $platform_name/hardware/$architecture/$version
  platforms = listToAttrs (map ({ name, platforms, scope ? name, ... }: {
    inherit name;
    value = mapAttrs (architecture: versions: let
      res = listToAttrs (map ({version, url, checksum, toolsDependencies ? [], ...}: {
        name = version;
        value = stdenv.mkDerivation {
          pname = "${name}-${architecture}";
          inherit version;
          dirName = "packages/${name}/hardware/${architecture}/${version}";

          toolsDependencies = map ({packager, name, version}: arduinoPackages.tools.${packager}.${name}.${version}) toolsDependencies;
          passAsFile = [ "toolsDependencies" ];
          passthru = {
            inherit scope architecture;
          };
          installPhase = ''
            runHook preInstall

            mkdir -p "$out/$dirName"
            cp -R * "$out/$dirName/"

            for i in $(cat $toolsDependenciesPath); do
              ${lndir}/bin/lndir -silent $i $out
            done

            runHook postInstall
          '';
          nativeBuildInputs = [ pkgs.unzip ];
          src = fetchurl ({
            url = url;
          } // (convertHash checksum));
        };
      }) versions);
    in res // { latest = latestVersion res; }) (groupBy ({ architecture, ... }: architecture) platforms);
  }) packageIndex.packages);
in
{
  inherit tools platforms;
}
