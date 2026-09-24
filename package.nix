{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  makeWrapper,
  libredirect,
  patchelf,
  file,
  cups,
  zlib,
  jbigkit,
  libjpeg,
  libgcrypt,
  libxml2_13,
  glib,
  gtk3,
  gdk-pixbuf,
  pango,
  cairo,
  atk,
}:

let
  pname = "canon-ufrii-lt";
  version = "5.10-1.00";

  runtimeLibs = [
    cups
    zlib
    jbigkit
    libjpeg
    libgcrypt
    libxml2_13
    glib
    gtk3
    gdk-pixbuf
    pango
    cairo
    atk
  ];
in
stdenv.mkDerivation {
  inherit pname version;

  src = fetchurl {
    url = "https://gdlp01.c-wss.com/gds/1/0100005951/11/linux-UFRIILT-drv-v510-us.tar.gz";
    hash = "sha256-UJHS19xY4rLw4nwm6mKg3O1pyU2LVf0P1Oj2iriVtMA=";
  };

  nativeBuildInputs = [
    dpkg
    patchelf
    makeWrapper
    file
  ];

  buildInputs = runtimeLibs;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  # We patch ELF files by hand below rather than letting nixpkgs' own
  # fixup pass do it, because some of these binaries dlopen() plugins
  # by absolute path at runtime — automatic rpath stripping wouldn't
  # touch that anyway, and NIX_REDIRECTS (below) is the actual fix for
  # it, not rpath handling.
  dontPatchELF = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    # Extract Canon's official driver tarball first.
    mkdir -p source
    tar -xzf "$src" -C source

    # The tarball contains the same Debian package that was previously
    # used directly. Use the exact amd64 package path verified in the
    # Canon archive.
    deb="source/linux-UFRIILT-drv-v510-us/x64/Debian/cnrdrvcups-ufr2lt-us_5.10-1.00_amd64.deb"

    if [ ! -f "$deb" ]; then
      echo "ERROR: expected Canon UFRII LT amd64 package was not found: $deb" >&2
      echo "Contents of downloaded Canon tarball:" >&2
      find source -type f -print >&2
      exit 1
    fi

    echo "Using Canon package: $deb"

    # Extract the .deb exactly as shipped, into a scratch directory we
    # keep around only long enough to (a) copy real payload into $out
    # and (b) record every absolute path it expected to exist, so we
    # can redirect lookups against those exact paths later.
    mkdir -p extracted
    dpkg-deb --fsys-tarfile "$deb" |
      tar -xf - -C extracted --no-same-owner --no-same-permissions

    mkdir -p "$out"

    # Debian packages usually usr-merge symlink bin -> usr/bin etc,
    # but which of the two is the "real" directory in the tar stream
    # isn't stable for this .deb across rebuilds (confirmed
    # empirically). Handle both forms unconditionally and merge
    # anything found under either into one canonical nixpkgs layout.
    for d in bin sbin lib lib64 share etc; do
      for prefix in "" "usr/"; do
        srcdir="extracted/''${prefix}$d"
        if [ -d "$srcdir" ]; then
          mkdir -p "$out/$d"
          cp -a "$srcdir/." "$out/$d/"
        fi
      done
    done
    chmod -R u+w "$out"

    # NixOS expects udev rules under lib/udev/rules.d.
    if [ -d "$out/etc/udev/rules.d" ]; then
      mkdir -p "$out/lib/udev/rules.d"
      cp -a "$out/etc/udev/rules.d/." "$out/lib/udev/rules.d/"
    fi
    rm -rf "$out/etc/udev" "$out/var"

    # ---- Fix dynamic linking ----
    interp="$(cat "${stdenv.cc}/nix-support/dynamic-linker")"
    rpath="${lib.makeLibraryPath runtimeLibs}:${lib.getLib stdenv.cc.cc}/lib:${stdenv.cc.libc}/lib:$out/lib:$out/lib/Canon/CUPS_SFPR/Libs"

    find "$out" -type f | while read -r f; do
      if ! file "$f" | grep -q ELF; then
        continue
      fi
      patchelf --set-rpath "$rpath" "$f" 2>/dev/null || true
      if file "$f" | grep -q 'executable'; then
        patchelf --set-interpreter "$interp" "$f" 2>/dev/null || true
      fi
    done

    # ---- Fix hardcoded absolute-path lookups ----
    # Build a map from every original absolute path the .deb shipped
    # (e.g. /usr/lib/Canon/CUPS_SFPR/Libs/libcanon_commonr.so.1) to
    # where we actually installed it under $out. Any binary that
    # dlopen()s, exec()s, or fopen()s that literal string at runtime
    # gets transparently redirected via libredirect, with no sandbox.
    : > redirect-pairs.txt
    find extracted -mindepth 1 \( -type f -o -type l \) -print | while read -r orig; do
      rel="''${orig#extracted/}"
      case "$rel" in
        usr/*) rel="''${rel#usr/}" ;;
      esac
      origAbs="/''${orig#extracted/}"
      newAbs="$out/$rel"
      if [ -e "$newAbs" ]; then
        printf '%s=%s\n' "$origAbs" "$newAbs" >> redirect-pairs.txt
      fi
    done
    redirects="$(paste -sd: redirect-pairs.txt)"

    # Wrap every real ELF executable anywhere in $out (bin/, sbin/,
    # and CUPS filter directories like lib/cups/filter/) with the
    # redirect map plus its own library path. rastertosfp in
    # particular lives under lib/cups/filter, not bin/, so it must
    # be included here too.
    find "$out" -type f -perm -u+x | while read -r bin; do
      file "$bin" | grep -q ELF || continue
      wrapProgram "$bin" \
        --prefix LD_LIBRARY_PATH : "$out/lib" \
        --set LD_PRELOAD "${libredirect}/lib/libredirect.so" \
        --set NIX_REDIRECTS "$redirects"
    done

    # rastertosfp is CUPS' filter entry point; it should already be a
    # real wrapped file at lib/cups/filter/rastertosfp from the copy
    # above (the .deb ships it there directly), so nothing extra
    # to do here beyond confirming it exists.
    if [ ! -e "$out/lib/cups/filter/rastertosfp" ]; then
      echo "WARNING: rastertosfp not found at expected filter path" >&2
    fi

    runHook postInstall
  '';

  meta = {
    description = "Canon UFRII LT CUPS driver (patchelf + libredirect, no sandbox)";
    homepage = "https://www.canon.com/";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
  };
}
