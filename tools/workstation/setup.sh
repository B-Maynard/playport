#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Automates this workstation's setup (docs/BUILDING.md, docs/DEVICE.md) for `pp install`.
#
#   tools/workstation/setup.sh status            what is present, what is missing; changes nothing
#   tools/workstation/setup.sh install [--xip F] everything that needs no sudo; safe to run again
#   tools/workstation/setup.sh system            the sudo commands still needed (printed, not run)
#   tools/workstation/setup.sh rollback [--tools] undo what install made (--tools also deletes the
#                                                toolchains under .work/tools and the downloads)
#
# Design rules:
#  - Nothing system-wide changes. The macOS shims use the host clang recorded as HOST_CLANG_BIN
#    (pp setup --host-clang-bin), so /usr/bin/clang and the update-alternatives defaults stay put.
#  - Every system-level thing is named in `system`; this script never runs sudo.
#  - install writes a manifest (.work/workstation/manifest) of what it created outside the repo,
#    and rollback removes only those entries.
#  - Versions are pinned below; pins.lock pins xtool.

set -euo pipefail


ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
WS=$ROOT/.work/tools          # toolchains installed by this script (gitignored)
DL=$ROOT/.work/downloads      # archives (gitignored)
STATE=$ROOT/.work/workstation # env.sh, manifest, logs (gitignored)
LOGS=$STATE/logs
MANIFEST=$STATE/manifest
UNITDIR=$HOME/.config/systemd/user
XTOOL_WRAPPER=$HOME/.local/bin/xtool
DARWIN_BUNDLE=$HOME/.swiftpm/swift-sdks/darwin.artifactbundle
# Tools this script extracted (bison, flex, m4) are found before the system ones.
export PATH="$WS/bison-flex/usr/bin:$PATH"

# ---- pins -------------------------------------------------------------------
SWIFT_VERSION=6.4.2
SWIFT_URL=https://download.swift.org/swift-6.4.2-release/ubuntu2404/swift-6.4.2-RELEASE/swift-6.4.2-RELEASE-ubuntu24.04.tar.gz
LLVM_MINGW_URL=https://github.com/mstorsjo/llvm-mingw/releases/download/20260922/llvm-mingw-20260922-ucrt-ubuntu-22.04-x86_64.tar.xz
LLVM_MINGW_SHA256=bb7bb7654b33d5aa8712acb837c963b2e0c56352560c76105270a3268c665c21
MINGW_W64_URL=https://git.code.sf.net/p/mingw-w64/mingw-w64
MINGW_W64_COMMIT=57b595039040eaa15bece85b7cc71d952281b269   # the commit llvm-mingw names
NETMUXD_VERSION=v0.4.3
PYMOBILEDEVICE3_VERSION=11.55.0
# Prebuilt packages, not source builds: Ubuntu 26.04 (resolute) binaries, which run on noble
# (their highest glibc symbol is GLIBC_2.38; noble has 2.39). xtool-core needs libimobiledevice >= 1.4.0.
# Each entry: archive path, sha256. They are unpacked (dpkg -x) into $WS/idevice-stack.
UBUNTU_ARCHIVE=https://archive.ubuntu.com/ubuntu
PREBUILT_IDEVICE=(
    "pool/main/libi/libimobiledevice/libimobiledevice-1.0-6_1.4.0-1build1_amd64.deb b5277ade48034e54db3f0b714ab0935b4657632fbdd8ec3d795e2c044272a622"
    "pool/main/libi/libimobiledevice/libimobiledevice-dev_1.4.0-1build1_amd64.deb e19ea5e7068cc69ad5af8cc9ae5a8c5f91dce10b9a7e2d8f9cab2a1a7a51e594"
    "pool/main/libi/libimobiledevice-glue/libimobiledevice-glue-1.0-0_1.3.2-2build1_amd64.deb c2e1b9b47592a645be9ece937f3c4f18a99a8de0d9f79134dca9d4582bcdfcdb"
    "pool/main/libi/libimobiledevice-glue/libimobiledevice-glue-dev_1.3.2-2build1_amd64.deb e5b37fd0c739465342b26a4802ae1c4ee860b00074328badbee8158c3c66cd0a"
    "pool/main/libp/libplist/libplist-2.0-4_2.7.0+git20250820-1build1_amd64.deb 04eb26d40bbb9cee682e6f51a25a1b311351b4c30722b8174acd67d4144bce47"
    "pool/main/libp/libplist/libplist-dev_2.7.0+git20250820-1build1_amd64.deb 6fa8f9018d3bed6b3bc9d65866cb7183dc9013de1a93d2bfdb474d4a5176ab9d"
    "pool/universe/libt/libtatsu/libtatsu0_1.0.5-2_amd64.deb 1f387d5dc5853dfa6e235cc7f34ea3a5fa662a63d8462a53459133bae4dca31c"
    "pool/universe/libt/libtatsu/libtatsu-dev_1.0.5-2_amd64.deb 18bf19eef7a55c55062ae8efaf0f44ac5797985b4d4813f1ba1a5ebfcccf6152"
    "pool/main/libu/libusbmuxd/libusbmuxd-2.0-7_2.1.1-1_amd64.deb f4cd323620e90c825069f0866d038347deded8d8d0c469ab42c75ba34e231f67"
    "pool/main/libu/libusbmuxd/libusbmuxd-dev_2.1.1-1_amd64.deb 9c91450a23517d9f2981653c158b06139aefacc63a73c21b4ec9a83db5db965a"
)
# SPIRV-LLVM-Translator for LLVM 22 (Mesa's host shader tools), same source and method.
PREBUILT_SPIRV=(
    "pool/universe/s/spirv-llvm-translator-22/libllvmspirvlib22.1_22.1.0-1ubuntu1_amd64.deb 1931cc92d330a883ddbbb693cd84eef13598e8c0621f0c8cdc65bc20ee594a6e"
    "pool/universe/s/spirv-llvm-translator-22/libllvmspirvlib-22-dev_22.1.0-1ubuntu1_amd64.deb b52865401000877ff3c93f9ea80e1a55142c79a0e5e58fe7178c806940fec711"
    "pool/universe/s/spirv-tools/spirv-tools_2025.1~rc1-1~ubuntu0.24.04.2_amd64.deb 529e396c337d15beb8ed0f03fcbeb2a066e5a818e032e197b6ef2d3328dc7ae9"
)
# LLVM 15.0.7 host tools for DXMT's air helpers (the version the fork pins). Ubuntu 24.04 (noble)
# packages, unpacked into $WS/llvm-15; wrappers in $WS/llvm-15/bin set the library path.
PREBUILT_LLVM15=(
    "pool/universe/l/llvm-toolchain-15/llvm-15_15.0.7-14build3_amd64.deb 0e5a8a1fc3cf9b21a0b262d39d53dd411c72e5df400a54787cde53210591bf70"
    "pool/universe/l/llvm-toolchain-15/llvm-15-tools_15.0.7-14build3_amd64.deb 58d5ac8752a9c03d42e3de31399666dcaca04156d86cad5394ccfbec38af43f9"
    "pool/universe/l/llvm-toolchain-15/llvm-15-linker-tools_15.0.7-14build3_amd64.deb 4b4ad65e9ea481c4ddd679a42d3deddcf98db66951d0b9f0155e4aa373403491"
    "pool/universe/l/llvm-toolchain-15/llvm-15-runtime_15.0.7-14build3_amd64.deb b2caf977d98a3bd2586325d5b1ddccf4d40d6b29ab651f20ee2e18ae7b443d98"
    "pool/universe/l/llvm-toolchain-15/libllvm15t64_15.0.7-14build3_amd64.deb a486f3bdd974133edb049b5f3396f9e75cf7894b9e91008407bec9885a2f33d9"
)
IDEVICE_LIB=$WS/idevice-stack/usr/lib/x86_64-linux-gnu

say() { printf '%s\n' "$*"; }
die() { printf 'setup.sh: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
mark() { mkdir -p "$STATE"; grep -qxF "$1" "$MANIFEST" 2>/dev/null || printf '%s\n' "$1" >> "$MANIFEST"; }
log_run() { # log_run NAME CMD...  (output to a log; prints the log on failure)
    local name=$1; shift; mkdir -p "$LOGS"
    if ! "$@" > "$LOGS/$name.log" 2>&1; then
        say "  FAILED: $name (log: ${LOGS#$ROOT/}/$name.log)"; tail -5 "$LOGS/$name.log" | sed 's/^/    /'; return 1
    fi
}
ubuntu_noble() { . /etc/os-release 2>/dev/null; [ "${UBUNTU_CODENAME:-}" = noble ]; }

# Environment the build and the tools need; written to .work/workstation/env.sh for your shell.
write_env() {
    mkdir -p "$STATE"
    cat > "$STATE/env.sh" <<EOF
# Generated by tools/workstation/setup.sh. Source it in a terminal: . ${STATE#$ROOT/}/env.sh
export PATH="$WS/swift-$SWIFT_VERSION/usr/bin:$WS/pmd3/bin:$WS/netmuxd:$WS/bison-flex/usr/bin:$HOME/.local/bin:\$PATH"
# LLVM 22 tools (llvm-nm, llvm-lipo) for pp build; only this shell.
[ -d /usr/lib/llvm-22/bin ] && export PATH="\$PATH:/usr/lib/llvm-22/bin"
export PATH="$WS/glslang/usr/bin:\$PATH"
export LD_LIBRARY_PATH="$IDEVICE_LIB\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
export PKG_CONFIG_PATH="$IDEVICE_LIB/pkgconfig:$WS/spirv/usr/lib/x86_64-linux-gnu/pkgconfig\${PKG_CONFIG_PATH:+:\$PKG_CONFIG_PATH}"
export CPATH="$WS/liblzma-dev/usr/include\${CPATH:+:\$CPATH}"
export LIBRARY_PATH="$WS/liblzma-dev/usr/lib/x86_64-linux-gnu\${LIBRARY_PATH:+:\$LIBRARY_PATH}"
export BISON_PKGDATADIR="$WS/bison-flex/usr/share/bison"
EOF
}

# ---- status -----------------------------------------------------------------
status() {
    row() { printf '  %-28s %s\n' "$1" "$2"; }
    say "toolchains (.work/tools):"
    row swift "$( [ -x "$WS/swift-$SWIFT_VERSION/usr/bin/swift" ] && echo ok || echo missing)"
    row "llvm-mingw+CRT" "$( [ -f "$WS/llvm-mingw/aarch64-w64-mingw32/lib/libgcc.a" ] && echo ok || echo missing)"
    row idevice-stack "$( pkg_atleast libimobiledevice-1.0 1.4.0 && echo ok || echo missing)"
    row pymobiledevice3 "$( [ -x "$WS/pmd3/bin/pymobiledevice3" ] && echo ok || echo missing)"
    row netmuxd "$( [ -x "$WS/netmuxd/netmuxd" ] && echo ok || echo missing)"
    row bison/flex "$( (have bison && have flex) && echo ok || echo missing)"
    row "liblzma headers" "$( [ -f "$WS/liblzma-dev/usr/include/lzma.h" ] && echo ok || echo "missing (in $WS/liblzma-dev)")"
    row xtool "$( [ -x "$ROOT/.work/inputs/xtool-src/.build/release/xtool" ] && echo ok || echo missing)"
    row "xtool wrapper" "$( [ -x "$XTOOL_WRAPPER" ] && echo ok || echo missing)"
    row "darwin SDK bundle" "$( [ -d "$DARWIN_BUNDLE" ] && echo ok || echo "missing (xtool sdk install <Xcode.xip> --slim)")"
    say "system (sudo, printed by 'system'):"
    row "host clang 22" "$( [ -x /usr/lib/llvm-22/bin/clang ] && echo ok || echo missing)"
    local absent=()
    for p in libdrm-dev libelf-dev libexpat1-dev libwayland-dev libclc-22-dev; do dpkg -s "$p" >/dev/null 2>&1 || absent+=("$p"); done
    row "mesa dev packages" "$( [ ${#absent[@]} -eq 0 ] && echo ok || echo "missing: ${absent[*]}")"
    say "repo inputs (.work/inputs.local):"
    if [ -f "$ROOT/.work/inputs.local" ]; then sed 's/^/  /' "$ROOT/.work/inputs.local" | grep -v '^  #' || true; else say "  not recorded yet"; fi
    say "user units:"
    row netmuxd "$(systemctl --user is-active netmuxd 2>/dev/null || echo "not running")"
}

pkg_exists() { PKG_CONFIG_PATH="$IDEVICE_LIB/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" pkg-config --exists "$1"; }
pkg_atleast() { PKG_CONFIG_PATH="$IDEVICE_LIB/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" pkg-config --atleast-version="$2" "$1"; }

# ---- system: printed, never run ----------------------------------------------
system() {
    # Mesa's host build (docs/BUILDING.md, vulkan stage) reads these through pkg-config; they are
    # ready-made Ubuntu packages, so they're installed, not built.
    local mesa=(libdrm-dev libelf-dev libexpat1-dev libwayland-dev libclc-22-dev)
    local absent=()
    for p in "${mesa[@]}"; do dpkg -s "$p" >/dev/null 2>&1 || absent+=("$p"); done
    if [ ${#absent[@]} -gt 0 ]; then
        say "sudo apt install ${absent[*]}"
    else
        say "# Mesa's development packages are present"
    fi
    if [ ! -x /usr/lib/llvm-22/bin/clang ]; then
        say "# host clang 22 (LLVM 22.x, with ld64.lld):"
        say "wget https://apt.llvm.org/llvm.sh && chmod +x llvm.sh && sudo ./llvm.sh 22 all"
    else
        say "# host clang 22 present: /usr/lib/llvm-22/bin"
    fi
    say "# Nothing above is run by this script. System defaults are not changed: pp setup records"
    say "# the LLVM 22 directory as HOST_CLANG_BIN (tools/workstation/setup.sh install does that)."
}

# ---- install ---------------------------------------------------------------
install_swift() {
    [ -x "$WS/swift-$SWIFT_VERSION/usr/bin/swift" ] && return 0
    ubuntu_noble || die "the Swift $SWIFT_VERSION download is for Ubuntu 24.04 (noble); this is not noble"
    mkdir -p "$DL" "$WS"; say "swift $SWIFT_VERSION: downloading"
    log_run swift-download curl -fL -o "$DL/swift-$SWIFT_VERSION.tar.gz" "$SWIFT_URL"
    log_run swift-extract bash -c "tar -xzf '$DL/swift-$SWIFT_VERSION.tar.gz' -C '$WS' && mv '$WS/swift-$SWIFT_VERSION-RELEASE-ubuntu24.04' '$WS/swift-$SWIFT_VERSION'"
    mark "dir:$WS/swift-$SWIFT_VERSION"
}

install_llvm_mingw() {
    if [ ! -x "$WS/llvm-mingw/bin/aarch64-w64-mingw32-clang" ]; then
        mkdir -p "$DL" "$WS"; say "llvm-mingw: downloading the pinned release"
        log_run llvm-mingw-download curl -fL -o "$DL/llvm-mingw.tar.xz" "$LLVM_MINGW_URL"
        echo "$LLVM_MINGW_SHA256  $DL/llvm-mingw.tar.xz" | sha256sum -c --quiet || die "llvm-mingw sha256 does not match the pin"
        log_run llvm-mingw-extract bash -c "tar -xJf '$DL/llvm-mingw.tar.xz' -C '$WS' && mv '$WS/llvm-mingw-20260922-ucrt-ubuntu-22.04-x86_64' '$WS/llvm-mingw'"
        mark "dir:$WS/llvm-mingw"
    fi
    if [ ! -f "$WS/llvm-mingw/aarch64-w64-mingw32/lib/libgcc.a" ]; then
        say "llvm-mingw: rebuilding the aarch64 CRT with arm64ec (one-time, slow)"
        local src=$WS/mingw-w64-src
        [ -d "$src/.git" ] || log_run mingw-clone git clone -q "$MINGW_W64_URL" "$src"
        log_run mingw-checkout git -C "$src" -c advice.detachedHead=false checkout -q "$MINGW_W64_COMMIT"
        mark "dir:$src"
        local L=$WS/llvm-mingw B=$WS/build-crt-aarch64
        mkdir -p "$B"
        (
            export PATH="$L/bin:$PATH"
            cd "$src/mingw-w64-crt"; [ -x configure ] || autoreconf -fi >/dev/null 2>&1
            cd "$B"
            log_run crt-configure "$src/mingw-w64-crt/configure" --prefix="$L" --host=aarch64-w64-mingw32 \
                --disable-lib32 --disable-lib64 --enable-libarm64 --enable-arm64x \
                --with-default-msvcrt=ucrt --enable-cfguard --enable-silent-rules
            log_run crt-make make -j"$(nproc)"
            log_run crt-install make install
        ) || die "CRT build failed (logs in ${LOGS#$ROOT/})"
        local b; b=$(find "$L/lib" -name 'libclang_rt.builtins-aarch64.a' | head -1)
        [ -n "$b" ] || die "no aarch64 builtins library under $L/lib"
        for n in libgcc.a libgcc_eh.a libgcc_s.a; do cp "$b" "$L/aarch64-w64-mingw32/lib/$n"; done
    fi
}

install_liblzma() {
    pkg_exists liblzma && return 0
    local arch=/usr/lib/x86_64-linux-gnu so
    so=$(ls $arch/liblzma.so.5.* 2>/dev/null | head -1)
    [ -n "$so" ] || die "liblzma runtime missing"
    mkdir -p "$DL" "$WS/liblzma-dev"
    if [ ! -f "$WS/liblzma-dev/usr/include/lzma.h" ]; then
        say "liblzma headers: fetching the development package (no sudo)"
        (cd "$DL" && log_run liblzma-fetch apt-get download liblzma-dev)
        dpkg -x "$DL"/liblzma-dev_*.deb "$WS/liblzma-dev"
    fi
    mkdir -p "$WS/liblzma-dev/usr/lib/x86_64-linux-gnu"
    ln -sfn "$so" "$WS/liblzma-dev/usr/lib/x86_64-linux-gnu/liblzma.so"
    mark "dir:$WS/liblzma-dev"
}

install_glslang() {
    [ -x "$WS/glslang/usr/bin/glslangValidator" ] && return 0
    mkdir -p "$DL" "$WS/glslang"
    say "glslangValidator (Mesa's shader compiler): fetching glslang-tools (no sudo)"
    (cd "$DL" && log_run glslang-fetch apt-get download glslang-tools)
    dpkg -x "$DL"/glslang-tools_*.deb "$WS/glslang"
    mark "dir:$WS/glslang"
}

install_bison_flex() {
    if have bison && have flex && have m4; then return 0; fi
    mkdir -p "$DL" "$WS/bison-flex"
    say "bison/flex/m4: fetching the packages (no sudo)"
    (cd "$DL" && log_run bison-fetch apt-get download bison flex m4)
    for f in "$DL"/bison_*.deb "$DL"/flex_*.deb "$DL"/m4_*.deb; do dpkg -x "$f" "$WS/bison-flex"; done
    mark "dir:$WS/bison-flex"
}

install_pymobiledevice3() {
    [ -x "$WS/pmd3/bin/pymobiledevice3" ] && return 0
    say "pymobiledevice3 $PYMOBILEDEVICE3_VERSION: venv + pip (no ensurepip on this system)"
    mkdir -p "$DL"
    log_run pmd3-venv python3 -m venv --without-pip "$WS/pmd3"
    mark "dir:$WS/pmd3"
    log_run getpip curl -fsSL -o "$DL/get-pip.py" https://bootstrap.pypa.io/get-pip.py
    log_run pmd3-pip-bootstrap "$WS/pmd3/bin/python3" "$DL/get-pip.py"
    log_run pmd3-install "$WS/pmd3/bin/pip" install "pymobiledevice3==$PYMOBILEDEVICE3_VERSION" cmake ninja meson pefile mako pyyaml packaging
}

# Fetch prebuilt .deb packages (LIST: "archive-path sha256" per entry), check each sha256, unpack
# them into DEST with dpkg -x. Nothing is installed system-wide.
fetch_debs() {
    local dest=$1; shift
    mkdir -p "$DL/prebuilt" "$dest"
    local entry path sha file
    for entry in "$@"; do
        read -r path sha <<<"$entry"
        file=$DL/prebuilt/$(basename "$path")
        [ -f "$file" ] || log_run "fetch-$(basename "$path")" curl -fL -o "$file" "$UBUNTU_ARCHIVE/$path"
        echo "$sha  $file" | sha256sum -c --quiet || die "checksum mismatch for $(basename "$path"): the archive changed; re-pin it"
        dpkg -x "$file" "$dest"
    done
}

# The prebuilt libraries need a glibc no newer than this machine's.
check_glibc() {
    local lib=$1 need have
    need=$(objdump -T "$lib" 2>/dev/null | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1 | sed 's/GLIBC_//')
    have=$(ldd --version 2>/dev/null | head -1 | grep -o '[0-9.]*$')
    [ -z "$need" ] || [ "$(printf '%s\n%s\n' "$need" "$have" | sort -V | tail -1)" = "$have" ] ||
        die "$(basename "$lib") needs glibc $need, this system has $have"
}

install_idevice_stack() {
    if [ ! -d "$IDEVICE_LIB" ] || ! PKG_CONFIG_PATH="$IDEVICE_LIB/pkgconfig" pkg-config --atleast-version=1.4.0 libimobiledevice-1.0 2>/dev/null; then
        say "idevice stack: unpacking the prebuilt libimobiledevice 1.4 packages (no source build)"
        fetch_debs "$WS/idevice-stack" "${PREBUILT_IDEVICE[@]}"
        # pkg-config files name the unpacking prefix as /usr: point them at this copy.
        sed -i "s|^prefix=/usr\$|prefix=$WS/idevice-stack/usr|" "$IDEVICE_LIB"/pkgconfig/*.pc
        check_glibc "$IDEVICE_LIB/libimobiledevice-1.0.so.6.1.0"
        mark "dir:$WS/idevice-stack"
    fi
}

install_spirv() {
    [ -f "$WS/spirv/usr/lib/x86_64-linux-gnu/libLLVMSPIRVLib.so.22.1" ] && return 0
    say "SPIRV-LLVM-Translator 22: unpacking the prebuilt package (Mesa's shader tools need it)"
    fetch_debs "$WS/spirv" "${PREBUILT_SPIRV[@]}"
    # The package's .pc file names /usr as its prefix and lib/ as its libdir; both differ here.
    sed -i "s|^prefix=.*|prefix=$WS/spirv/usr|; s|^libdir=.*|libdir=\${prefix}/lib/x86_64-linux-gnu|" "$WS/spirv/usr/lib/x86_64-linux-gnu/pkgconfig/LLVMSPIRVLib.pc"
    sed -i "s|^prefix=.*|prefix=$WS/spirv/usr|" "$WS/spirv/usr/lib/x86_64-linux-gnu/pkgconfig/SPIRV-Tools.pc"
    check_glibc "$WS/spirv/usr/lib/x86_64-linux-gnu/libLLVMSPIRVLib.so.22.1"
    mark "dir:$WS/spirv"
}

LLVM15_DIR=$WS/llvm-15
install_llvm15() {
    if [ ! -x "$LLVM15_DIR/usr/lib/llvm-15/bin/llvm-as" ]; then
        say "LLVM 15.0.7 host tools: unpacking the prebuilt Ubuntu packages (DXMT's air helpers)"
        fetch_debs "$LLVM15_DIR" "${PREBUILT_LLVM15[@]}"
    fi
    # Each tool is a wrapper that sets the library path to the unpacked libLLVM-15.so.1.
    mkdir -p "$LLVM15_DIR/bin"
    local t
    for t in llvm-as llvm-dis llvm-link llc opt llvm-tblgen; do
        cat > "$LLVM15_DIR/bin/$t" <<EOF
#!/bin/sh
# managed by tools/workstation/setup.sh
LD_LIBRARY_PATH="$LLVM15_DIR/usr/lib/x86_64-linux-gnu\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}" exec "$LLVM15_DIR/usr/lib/llvm-15/bin/$t" "\$@"
EOF
        chmod +x "$LLVM15_DIR/bin/$t"
    done
    "$LLVM15_DIR/bin/llvm-as" --version | grep -q 'LLVM version 15\.0\.7' || die "LLVM 15 wrapper does not report 15.0.7"
    mark "dir:$LLVM15_DIR"
}

install_xtool() {
    local x=$ROOT/.work/inputs/xtool-src/.build/release/xtool
    if [ ! -x "$x" ]; then
        say "xtool: building the pinned, patched xtool (build/toolchain/xtool.sh)"
        (
            export PATH="$WS/swift-$SWIFT_VERSION/usr/bin:$PATH"
            export PKG_CONFIG_PATH="$IDEVICE_LIB/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
            export LD_LIBRARY_PATH="$IDEVICE_LIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
            export CPATH="$WS/liblzma-dev/usr/include${CPATH:+:$CPATH}"
            export LIBRARY_PATH="$WS/liblzma-dev/usr/lib/x86_64-linux-gnu${LIBRARY_PATH:+:$LIBRARY_PATH}"
            cd "$ROOT"; log_run xtool-build build/toolchain/xtool.sh
        ) || die "xtool build failed (log in ${LOGS#$ROOT/}/xtool-build.log)"
    fi
    # The wrapper sets the library path that the built xtool needs.
    if [ ! -e "$XTOOL_WRAPPER" ] || grep -q 'setup.sh' "$XTOOL_WRAPPER"; then
        mkdir -p "$(dirname "$XTOOL_WRAPPER")"
        cat > "$XTOOL_WRAPPER" <<EOF
#!/bin/sh
# managed by tools/workstation/setup.sh (removed by its rollback)
LD_LIBRARY_PATH="$IDEVICE_LIB\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH
exec "$x" "\$@"
EOF
        chmod +x "$XTOOL_WRAPPER"; mark "file:$XTOOL_WRAPPER"
    fi
}

install_netmuxd() {
    if [ ! -x "$WS/netmuxd/netmuxd" ]; then
        say "netmuxd $NETMUXD_VERSION: downloading the release binary"
        mkdir -p "$DL" "$WS/netmuxd"
        log_run netmuxd-download curl -fL -o "$DL/netmuxd.tgz" \
            "https://github.com/jkcoxson/netmuxd/releases/download/$NETMUXD_VERSION/netmuxd-x86_64-unknown-linux-gnu.tar.gz"
        log_run netmuxd-extract tar -xzf "$DL/netmuxd.tgz" -C "$WS/netmuxd"
        mark "dir:$WS/netmuxd"
    fi
    # User unit: the repo's unit, its route-wait drop-in, and our binary path (Wi-Fi-only, as docs/DEVICE.md).
    if [ ! -e "$UNITDIR/netmuxd.service" ]; then
        mkdir -p "$UNITDIR" "$HOME/.local/share/port22"
        cp -r "$ROOT/tools/systemd/netmuxd.service" "$ROOT/tools/systemd/netmuxd.service.d" "$UNITDIR/"
        cat > "$UNITDIR/netmuxd.service.d/local-binary.conf" <<EOF
# managed by tools/workstation/setup.sh (removed by its rollback)
[Service]
ExecStart=
ExecStart=$WS/netmuxd/netmuxd --socket-path %h/.local/share/port22/nm.sock --disable-usb --plist-storage /var/lib/lockdown
EOF
        mark "unit:$UNITDIR/netmuxd.service"
        mark "unit:$UNITDIR/netmuxd.service.d"
        systemctl --user daemon-reload
        systemctl --user enable --now netmuxd >/dev/null 2>&1 || say "  netmuxd did not start: journalctl --user -u netmuxd"
    fi
}

record_inputs() {
    local darwin_arg=() sock=
    [ -d "$DARWIN_BUNDLE" ] && darwin_arg=(--darwin-sdk "$DARWIN_BUNDLE")
    if [ -S /var/run/usbmuxd ]; then sock=/var/run/usbmuxd   # USB phones: the system usbmuxd (auto-started on plug-in)
    elif [ -S "$HOME/.local/share/port22/nm.sock" ]; then sock=$HOME/.local/share/port22/nm.sock; fi
    local args=(--llvm-mingw "$WS/llvm-mingw")
    [ ${#darwin_arg[@]} -gt 0 ] && args+=("${darwin_arg[@]}")
    [ -n "$sock" ] && args+=(--usbmux-socket "$sock")
    [ -x /usr/lib/llvm-22/bin/clang ] && args+=(--host-clang-bin /usr/lib/llvm-22/bin)
    [ -x "$LLVM15_DIR/bin/llvm-as" ] && args+=(--host-llvm15-bin "$LLVM15_DIR/bin")
    (cd "$ROOT" && PATH="$WS/swift-$SWIFT_VERSION/usr/bin:$PATH" ./pp setup "${args[@]}")
}

install() {
    local xip=
    while [ $# -gt 0 ]; do case $1 in
        --xip) xip=$2; shift 2 ;;
        *) die "install: unknown argument $1" ;;
    esac; done
    mkdir -p "$WS" "$STATE" "$LOGS"
    install_swift
    install_llvm_mingw
    install_bison_flex
    install_glslang
    install_pymobiledevice3
    install_liblzma
    install_idevice_stack
    install_xtool
    install_spirv
    install_llvm15
    install_netmuxd
    if [ -n "$xip" ] && [ ! -d "$DARWIN_BUNDLE" ]; then
        say "darwin SDK: xtool sdk install $xip --slim (writes $DARWIN_BUNDLE; outside the repo, as SwiftPM expects)"
        log_run darwin-sdk "$XTOOL_WRAPPER" sdk install "$xip" --slim || die "xtool sdk install failed (log in ${LOGS#$ROOT/}/darwin-sdk.log)"
        mark "dir:$DARWIN_BUNDLE"
    fi
    write_env
    record_inputs
    say "done. In a terminal: . ${STATE#$ROOT/}/env.sh   (then tools/workstation/setup.sh status)"
}

# ---- rollback --------------------------------------------------------------
rollback() {
    local all=0
    [ "${1:-}" = --tools ] && all=1
    if [ -f "$MANIFEST" ]; then
        while IFS= read -r entry; do
            case $entry in
                unit:*) p=${entry#unit:}; if [ -e "$p" ]; then rm -rf "$p"; say "removed $p"; fi ;;
                file:*) p=${entry#file:}; grep -q 'setup.sh' "$p" 2>/dev/null && { rm -f "$p"; say "removed $p"; } ;;
            esac
        done < "$MANIFEST"
    fi
    # Stop netmuxd only when install created its unit: a netmuxd set up by hand is left alone.
    if [ -f "$MANIFEST" ] && grep -q '^unit:' "$MANIFEST"; then
        systemctl --user disable --now netmuxd >/dev/null 2>&1 || true
        systemctl --user daemon-reload 2>/dev/null || true
    fi
    if [ -f "$ROOT/.work/inputs.local" ]; then
        sed -i '/^HOST_CLANG_BIN=/d; /^HOST_LLVM15_BIN=/d' "$ROOT/.work/inputs.local"
        say "removed HOST_CLANG_BIN from .work/inputs.local (macOS shims fall back to /usr/bin)"
    fi
    rm -f "$STATE/env.sh"
    if [ $all -eq 1 ]; then
        printf 'Delete %s, %s and %s? [y/N] ' "${WS#$ROOT/}" "${DL#$ROOT/}" "$ROOT/.work/inputs/xtool-src"
        read -r ans; if [ "$ans" = y ]; then
            rm -rf "$WS" "$DL" "$ROOT/.work/inputs/xtool-src"; say "toolchains and downloads deleted"
        fi
    fi
    rm -f "$MANIFEST"
    say "rolled back. Not changed: system packages (see 'system'; remove with apt if you want them gone),"
    say "  the repo's source edits (build/env.sh, build/inputs.py, build/stages/unix.sh, tools/machine.py),"
    say "  which are inert without HOST_CLANG_BIN, and ~/.swiftpm (xtool's SDK)."
}

case ${1:-status} in
    status) status ;;
    install) shift; install "$@" ;;
    system) system ;;
    rollback) shift; rollback "$@" ;;
    -h|--help|help) sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
    *) die "unknown command: $1 (status | install | system | rollback)" ;;
esac
