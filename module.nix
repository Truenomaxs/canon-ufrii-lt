{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.canon-ufrii-lt;

  driver = pkgs.callPackage ./package.nix { };

  cupsPostStart = lib.mapAttrsToList (
    name: _: "${pkgs.cups}/bin/lpadmin -p ${lib.escapeShellArg name} -o usb-unidir-default=false"
  ) cfg.printers;

in
{
  options.services.canon-ufrii-lt = {
    enable = lib.mkEnableOption "Canon UFRII LT CUPS driver";

    printers = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }: {
            options = {
              description = lib.mkOption {
                type = lib.types.str;
                default = name;
                description = "Human-readable printer description.";
              };

              location = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = "Physical location of the printer.";
              };

              deviceUri = lib.mkOption {
                type = lib.types.str;
                description = "CUPS device URI.";
                example = "usb://Canon/LBP6030/6040/6018L?serial=0000A1O5T05I";
              };

              model = lib.mkOption {
                type = lib.types.str;
                description = "PPD filename provided by the Canon driver.";
                example = "CNRCUPSLBP6030ZNS.ppd";
              };

              default = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Whether this printer should be the default printer.";
              };
            };
          }
        )
      );

      default = { };

      description = ''
        Canon UFRII LT printers to configure.

        The attribute name becomes the CUPS printer queue name.
      '';
    };

    logLevel = lib.mkOption {
      type = lib.types.str;
      default = "debug2";
      description = "CUPS log level.";
    };

    ippUsb = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable IPP-over-USB.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          builtins.length (builtins.filter (printer: printer.default) (builtins.attrValues cfg.printers))
          <= 1;

        message = "services.canon-ufrii-lt.printers: at most one printer may be marked as default.";
      }
    ];

    services.printing = {
      enable = true;
      logLevel = cfg.logLevel;

      drivers = [
        driver
      ];
    };

    hardware.printers = {
      ensurePrinters = lib.mapAttrsToList (name: printer: {
        inherit name;

        inherit (printer)
          description
          location
          deviceUri
          model
          ;
      }) cfg.printers;

      ensureDefaultPrinter =
        let
          defaults = lib.filterAttrs (_: printer: printer.default) cfg.printers;
        in
        if defaults == { } then null else builtins.head (builtins.attrNames defaults);
    };

    services.ipp-usb.enable = cfg.ippUsb;

    systemd.services.cups = {
      serviceConfig = {
        # Required by the Canon driver in the working configuration.
        PrivateTmp = lib.mkForce false;

        # Canon expects this old FHS path.
        BindReadOnlyPaths = [
          "${driver}/lib/Canon/CUPS_SFPR:/usr/lib/Canon/CUPS_SFPR"
        ];

        # Keep the working lpadmin workaround.
        ExecStartPost = lib.mkAfter cupsPostStart;
      };
    };
  };
}
