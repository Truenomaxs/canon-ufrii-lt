# canon-ufrii-lt

NixOS module for Canon UFRII LT CUPS printers (e.g. LBP6030 family),
patched to run outside FHS via patchelf + libredirect — no sandbox
escape, no vendored proprietary binary in this repo (fetched from
Canon's own servers at build time).


## Tested on

- NixOS 26.11 (Zokor), Canon LBP6030 over USB
- nixpkgs: `nixos-unstable`

> This module wraps Canon's generic UFRII LT driver package, so it may
> work as-is for other printers in the UFRII LT family beyond the
> LBP6030 (just point `printers.<name>.model` at the matching `.ppd`
> shipped in the driver). This is currently **untested** — if you try
> it on a different UFRII LT model and it works (or doesn't), please
> open an issue so it can be added to the compatibility list.

## Layout

- **`package.nix`** — the driver build itself: fetches Canon's tarball,
  extracts the `.deb`, patches ELF binaries with `patchelf`, and wires
  up `libredirect` for the driver's hardcoded absolute-path lookups.
- **`module.nix`** — the NixOS system-level quirks the driver needs to
  actually work at runtime (`PrivateTmp = false`, the `BindReadOnlyPaths`
  FHS shim, the `lpadmin` USB fixup — see below).

**Both are required.** `package.nix` alone will build and install fine —
`nix build` succeeding tells you nothing about whether printing will
actually work. Without `module.nix`'s runtime quirks applied, the most
common symptom is jobs that accept into the queue and then fail or hang
silently, with nothing obviously wrong in the build. If you're not using
`nixosModules.default` (e.g. you copied just the package derivation into
your own config), you need to replicate the settings in `module.nix`
yourself.

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

## Why the system quirks in module.nix?

- **`PrivateTmp = false` / `BindReadOnlyPaths`** — the Canon driver
  hardcodes lookups to `/usr/lib/Canon/CUPS_SFPR` at runtime; this
  module bind-mounts that FHS path read-only from the Nix store so the
  driver doesn't need patching at that layer.
- **`usb-unidir-default=false`** — the module runs
  `lpadmin -p <name> -o usb-unidir-default=false` after CUPS starts.
  If USB is left unidirectional (`true`, CUPS' default for some USB
  quirks tables), the driver's bidirectional status/handshake traffic
  gets cut off and the print job dies with a **SIGPIPE (13)** partway
  through, or simply stalls with no clear error — behavior that looks
  a lot like the "missing `module.nix`" symptom above, since both
  present as jobs that queue but never finish. If you see either, check
  this setting first (`lpoptions -p <name> -l | grep -i unidir`).
- **`logLevel = "debug2"`** — kept verbose by default rather than
  CUPS' normal level. This isn't a required workaround like the two
  above, just a safe default: since this module is still being
  validated on hardware beyond the LBP6030, verbose logs make it much
  easier to diagnose a failure on an untested printer without asking
  someone to change a setting and reproduce the issue. Lower it once
  your setup is confirmed working if you'd rather not fill
  `/var/log/cups/error_log` as quickly.
- **`ippUsb = true`** — also a safe default rather than a confirmed
  requirement. It's unclear whether IPP-over-USB is actually needed
  for this driver to function, but it's enabled by default since it's
  low-risk and may help with detection/status reporting on printers
  this module hasn't been tested against yet. If you're troubleshooting
  and want to rule it out, try `ippUsb = false` and see if behavior
  changes.

## Troubleshooting

- **Printer shows in `lpstat -p` but jobs never print** — check
  `journalctl -u cups -f` while sending a job; most failures are either
  the driver failing to resolve a hardcoded absolute path (missing
  `BindReadOnlyPaths`) or USB left unidirectional (see above — SIGPIPE
  13 or a silent stall). Confirm `BindReadOnlyPaths` is active with
  `systemctl show cups -p BindReadOnlyPaths`, and confirm
  `usb-unidir-default=false` with `lpoptions -p <name> -l`.
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
