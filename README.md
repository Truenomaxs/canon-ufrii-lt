# canon-ufrii-lt

NixOS module for Canon UFRII LT CUPS printers (e.g. LBP6030 family),
patched to run outside FHS via patchelf + libredirect — no sandbox
escape, no vendored proprietary binary in this repo (fetched from
Canon's own servers at build time).


## Tested on

- NixOS 26.11 (Zokor), Canon LBP6030 over USB
- nixpkgs: `nixos-unstable`

## Installation

Add to your `flake.nix`:

    {
      inputs.canon-ufrii-lt.url = "github:Truenomaxs/canon-ufrii-lt";

      outputs = { self, nixpkgs, canon-ufrii-lt, ... }: {
        nixosConfigurations.yourhost = nixpkgs.lib.nixosSystem {
          modules = [
            canon-ufrii-lt.nixosModules.default
            ./configuration.nix
          ];
        };
      };
    }

## Usage

    services.canon-ufrii-lt = {
      enable = true;
      printers.Canon_LBP6030 = {
        deviceUri = "usb://Canon/LBP6030/6040/6018L?serial=0000A1O5T05I";
        model = "CNRCUPSLBP6030ZNS.ppd";
        default = true;
      };
    };

> **Note:** `default` must be set explicitly on the printer you want as
> default — the module does not infer it even if you only define one
> printer.

## Options reference

| Option                              | Type    | Default   | Description                          |
|--------------------------------------|---------|-----------|---------------------------------------|
| `services.canon-ufrii-lt.enable`     | bool    | `false`   | Enable the service                    |
| `printers.<name>.deviceUri`          | string  | —         | CUPS device URI                       |
| `printers.<name>.model`              | string  | —         | PPD filename from the driver          |
| `printers.<name>.description`        | string  | attr name | Human-readable printer description    |
| `printers.<name>.location`           | string  | `""`      | Physical location                     |
| `printers.<name>.default`            | bool    | `false`   | Set as the default CUPS printer       |
| `logLevel`                           | string  | `"debug2"`| CUPS log level                        |
| `ippUsb`                             | bool    | `true`    | Enable IPP-over-USB                   |

## Finding your deviceUri and model

    lsusb                     # confirm the printer is detected
    lpinfo -v                 # find the usb:// device URI
    ls <driver-store-path>/share/ppd  # find your model's .ppd filename

## Why PrivateTmp = false / BindReadOnlyPaths?

The Canon driver hardcodes lookups to /usr/lib/Canon/CUPS_SFPR at
runtime; this module bind-mounts that FHS path read-only from the
Nix store so the driver doesn't need patching at that layer.

## Troubleshooting

- **Printer shows in `lpstat -p` but jobs never print** — check
  `journalctl -u cups -f` while sending a job; most failures are the
  driver failing to resolve a hardcoded absolute path. Confirm
  `BindReadOnlyPaths` is active with `systemctl show cups -p BindReadOnlyPaths`.
- **`rastertosfp` errors in the CUPS log** — this is the driver's
  filter binary; verify it exists and is executable at
  `<driver-store-path>/lib/cups/filter/rastertosfp`.
- **Build fails fetching the driver tarball** — Canon occasionally
  moves/versions these URLs; open an issue if `nix build` reports a
  hash mismatch or 404.

## Contributing

Issues and PRs welcome — especially reports confirming other UFRII LT
models work (or don't) with this module, since it's currently only
verified against the LBP6030.


## Author

**Marvin Angulo** · [@Truenomaxs](https://github.com/Truenomaxs)

## License

This module and packaging code are licensed under the MIT License.
See [LICENSE](./LICENSE).

The Canon UFRII LT driver itself is proprietary and unfree. It is
fetched directly from Canon's servers at build time and is not
redistributed in this repository.

