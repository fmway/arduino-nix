{ inputs, superInputs ? inputs, ... }:
{ inputs, pkgs, config, lib, ... }: let
  cfg = config.arduino-cli;
  arduino-index = inputs.arduino-index or superInputs.arduino-index;
  result = import ./wrap-arduino-cli.nix {
    inherit lib pkgs;
    packageIndex = generatedPackageIndex;
    libraryIndex = generatedLibraryIndex;
  } { inherit (cfg) libraries packages; };
  toValue = x:
    if lib.isAttrs x then
      x
    else builtins.fromJSON (lib.fileContents x);
  generatedPackageIndex = lib.foldl' (acc: x: let
    value = toValue x;
  in acc // value // {
      packages = (acc.packages or []) ++ (value.packages or []);
    }) {} cfg.packageIndex;
  generatedLibraryIndex = lib.foldl' (acc: x: let
    value = toValue x;
  in acc // value // {
      libraries = (acc.libraries or []) ++ (value.libraries or []);
    }) {} cfg.libraryIndex;
  indexType = with lib.types;
    listOf (oneOf [ (attrsOf anything) pathInStore ]);
in {
  options.arduino-cli = {
    enable = lib.mkEnableOption "enable arduino-cli";
    realPath = lib.mkEnableOption "use realpath instead of symlink (packages and libraries)";
    packages = lib.mkOption {
      description = "list of packages / platforms";
      type = let
        t = with lib.types; listOf (package // {
          check = pkg:
            package.check pkg &&
            (pkg.passthru or {}) ? architecture &&
            (pkg.passthru or {}) ? scope
          ;
        });
      in t // {
        merge = loc: defs:
          lib.attrValues (
            lib.foldl' (acc: curr:
              acc // { "${curr.scope}:${curr.architecture}" = curr; }
            ) {} (t.merge loc defs)
          );
      };
      default = [];
    };
    libraries = lib.mkOption {
      description = "list of libraries";
      type = let
        t = with lib.types; listOf package;
      in t // {
        merge = loc: defs:
          lib.attrValues (
            lib.foldl' (acc: curr:
              acc // { "${curr.pname}" = curr; }
            ) {} (t.merge loc defs)
          );
      };
      default = [];
    };
    userPath = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
    };
    dataPath = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
    };
    packageIndex = lib.mkOption {
      type = indexType;
      default = [];
    };
    libraryIndex = lib.mkOption {
      type = indexType;
      default = [];
    };
  };

  config = lib.mkIf cfg.enable {
    arduino-cli = {
      packageIndex = ["${arduino-index}/index/package_index.json"];
      libraryIndex = ["${arduino-index}/index/library_index.json"];
    };
    overlays = [
      (self: super: {
        arduinoPackages = self.lib.recursiveUpdate (super.arduinoPackages or {}) (self.callPackage ./packages.nix {
          packageIndex = generatedPackageIndex;
        });
        arduinoLibraries = self.lib.recursiveUpdate (super.arduinoLibraries or {}) (self.callPackage ./libraries.nix {
          libraryIndex = generatedLibraryIndex;
        });
      })
      (self: super: {
        arduino-cli = super.arduino-cli // { wrapPackages = super.callPackage ./wrap-arduino-cli.nix { inherit (self) lib; }; };
        arduino = super.arduino // { lib = self.arduinoLibraries; pkgs = self.arduinoPackages; };
      })
    ];
    arduino-cli = { inherit (result.passthru) dataPath userPath; };
    tasks."arduino-cli:copy" = lib.mkIf cfg.realPath {
      before = [ "devenv:enterShell" ];
      exec = /* sh */ ''
        arduino_dir="${config.devenv.root}/.arduino-cli"
        [ -d "$arduino_dir" ] || mkdir -p "$arduino_dir"
        [ -e "$arduino_dir/.gitignore" ] || printf '*\n.*\n' > "$arduino_dir/.gitignore"
        hash=""
        [ ! -e "$arduino_dir/hash" ] || hash="$(cat "$arduino_dir/hash")"
        if [ -z "$hash" ] || [ "$hash" != "${inputs.self.narHash}" ]; then
          echo "${inputs.self.narHash}" > "$arduino_dir/hash"
          [ ! -d "$arduino_dir/data" ] || rm -rf "$arduino_dir/data"
          [ ! -d "$arduino_dir/user" ] || rm -rf "$arduino_dir/user"
          mkdir -p "$arduino_dir/data"
          mkdir -p "$arduino_dir/user"
          ${lib.pipe cfg.dataPath.paths [
            (map (x:
              (if lib.filesystem.pathIsDirectory "${x}" then
                /* sh */ ''cp -rf ${x}/* "$arduino_dir/data/"''
              else /* sh */ "cp -f ${x} \"$arduino_dir/data/\"") + "\n" + /* sh */ ''
                chmod -R +rw $arduino_dir/data
              ''
            ))
            (lib.concatStringsSep "\n")
          ]}
          ${lib.pipe cfg.userPath.paths [
            (map (x:
              (if lib.filesystem.pathIsDirectory "${x}" then
                /* sh */ ''cp -rf ${x}/* "$arduino_dir/user/"''
              else /* sh */ "cp -f ${x} \"$arduino_dir/user/\"") + "\n" + /* sh */ ''
                chmod -R +rw $arduino_dir/user/
              ''
            ))
            (lib.concatStringsSep "\n")
          ]}
          #
        fi
      '';
    };
    env = {
      ARDUINO_UPDATER_ENABLE_NOTIFICATION = "${builtins.toString cfg.realPath}";
      ARDUINO_DIRECTORIES_DATA = lib.mkMerge [
        (lib.mkIf cfg.realPath "${config.devenv.root}/.arduino-cli/data")
        (lib.mkIf (!cfg.realPath) "${cfg.dataPath}")
      ];
      ARDUINO_DIRECTORIES_USER = lib.mkMerge [
        (lib.mkIf cfg.realPath "${config.devenv.root}/.arduino-cli/user")
        (lib.mkIf (!cfg.realPath) "${cfg.userPath}")
      ];
    };
    packages = [
      pkgs.arduino-cli
    ];
  };
}
