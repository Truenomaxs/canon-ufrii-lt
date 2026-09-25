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
> LBP6030 (just point `hardware.printers.ensurePrinters.<name>.model`
> at the matching `.ppd` shipped in the driver). This is currently
> **untested** — if you try it on a different UFRII LT model and it
> works (or doesn't), please open an issue so it can be added to the
> compatibility list.

## Layout

- **`package.nix`** — the driver build itself: fetches Canon's tarball,
  extracts the `.deb`, patches ELF binaries with `patchelf`, and wires
  up `libredirect` for the driver's hardcoded absolute-path lookups.
- **`module.nix`** — the one NixOS system-level quirk the driver needs
  to actually work at runtime (the `BindReadOnlyPaths` FHS shim — see
  below). Everything else — declaring printers, setting a default,
  CUPS log level, IPP-over-USB, USB unidirectional handling — is plain
  NixOS/CUPS behavior: `hardware.printers`, `services.printing`,
  `services.ipp-usb`. This module doesn't wrap or duplicate any of
  that.

**Both `package.nix` and `module.nix` are required.** `package.nix`
alone will build and install fine — `nix build` succeeding tells you
nothing about whether printing will actually work. Without
`module.nix`'s bind mount applied, the most common symptom is jobs
that accept into the queue and then fail or hang silently, with
nothing obviously wrong in the build. If you're not using
`nixosModules.default` (e.g. you copied just the package derivation
into your own config), you need to replicate that bind mount yourself
— and it must point at the exact same driver derivation you added to
`services.printing.drivers`, or you'll end up with two different
builds of the driver and a mount that doesn't match what's actually
registered.

## Installation

Add to your `flake.nix`:

    {
      inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

        canon-ufrii-lt.url =
          "github:Truenomaxs/canon-ufrii-lt";
      };

      outputs = { self, nixpkgs, canon-ufrii-lt, ... }: {
        nixosConfigurations.yourhost =
          nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";

            modules = [
              canon-ufrii-lt.nixosModules.default
              ./configuration.nix
            ];
          };
      };
    }

The Canon driver is unfree (see [License](#license)), so your own
`nixpkgs.config` needs to allow it before `services.canon-ufrii-lt`
will evaluate. Either allow it specifically:

    nixpkgs.config.allowUnfreePredicate =
      pkg: builtins.elem (nixpkgs.lib.getName pkg) [ "canon-ufrii-lt" ];

or allow unfree packages generally, if that's already your policy:

    nixpkgs.config.allowUnfree = true;

This module deliberately doesn't set either of these for you — it only
builds itself unfree-safe for its own `nix build` / `nix flake check`,
and leaves your system's unfree policy alone.

## Usage

    services.canon-ufrii-lt.enable = true;  # driver + the required runtime quirk
    services.printing.enable = true;

    hardware.printers = {
      ensurePrinters = [
        {
          name = "Canon_LBP6030";
          deviceUri = "usb://Canon/LBP6030/6040/6018L?serial=0000A1O5T05I";
          model = "CNRCUPSLBP6030ZNS.ppd";
          description = "Canon LBP6030";
          # location = "...";
        }
      ];
      ensureDefaultPrinter = "Canon_LBP6030";
    };

`services.canon-ufrii-lt.enable = true` adds the driver and its one
required runtime quirk (see below). Printers, defaults, log level, and
IPP-over-USB are all configured the normal NixOS way — there's no
separate option surface to learn on top of `hardware.printers` /
`services.printing`.

## Options reference

| Option                              | Type    | Default   | Description                                   |
|--------------------------------------|---------|-----------|-------------------------------------------------|
| `services.canon-ufrii-lt.enable`     | bool    | `false`   | Add the driver and its required runtime quirk   |

Everything else — printer definitions, `default`, `logLevel`,
`ipp-usb` — lives on the standard `hardware.printers` and
`services.printing` / `services.ipp-usb` options; see the NixOS
manual for those.

## Finding your deviceUri and model

    lsusb                     # confirm the printer is detected
    lpinfo -v                 # find the usb:// device URI
    ls <driver-store-path>/share/ppd  # find your model's .ppd filename

## Why the system quirk in module.nix?

One, and only one — everything else is stock NixOS/CUPS behavior.

- **`BindReadOnlyPaths`** — the Canon driver hardcodes lookups to
  `/usr/lib/Canon/CUPS_SFPR` at runtime; this module bind-mounts that
  FHS path read-only from the Nix store so the driver doesn't need
  patching at that layer. Without it, printing fails outright.

*(`PrivateTmp`, `services.ipp-usb`, and the USB unidirectional flag
were all tested and made no difference for the LBP6030 — not part of
this module. If a different UFRII LT model needs one of them, open an
issue.)*

## Troubleshooting

- **Printer shows in `lpstat -p` but jobs never print** — check
  `journalctl -u cups -f` while sending a job; the most common cause is
  the driver failing to resolve its hardcoded absolute path. Confirm
  `BindReadOnlyPaths` is active with
  `systemctl show cups -p BindReadOnlyPaths`.
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
