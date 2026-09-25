{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.canon-ufrii-lt;
  driver = pkgs.callPackage ./package.nix { };
in
{
  options.services.canon-ufrii-lt = {
    enable = lib.mkEnableOption "Canon UFRII LT driver with required runtime quirk";
  };

  config = lib.mkIf cfg.enable {
    services.printing.drivers = [ driver ];

    systemd.services.cups.serviceConfig.BindReadOnlyPaths = lib.mkAfter [
      "${driver}/lib/Canon/CUPS_SFPR:/usr/lib/Canon/CUPS_SFPR"
    ];
  };
}
