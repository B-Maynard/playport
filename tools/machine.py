# SPDX-License-Identifier: GPL-3.0-or-later
"""pp setup: record where this machine's system tools are, once.

  pp setup [--llvm-mingw DIR] [--darwin-sdk DIR] [--usbmux-socket PATH] [--host-clang-bin DIR] [--check]

The repository names no path outside itself. Each input below is found, checked
and written to $PLAYPORT_BUILD/inputs.local (gitignored), which build/env.sh
and build/inputs.py read. A value comes from the option, else the environment,
else the file already written, else what the tool itself reports:

  LLVM_MINGW              the llvm-mingw whose aarch64-w64-mingw32-clang is on PATH
  DARWIN_SDK              the bundle `swift sdk configure --show-configuration darwin` names
  PLAYPORT_USBMUX_SOCKET  the --socket-path of the running netmuxd user unit
  HOST_CLANG_BIN          a bin directory with clang 23.x and ld64.lld (LLVM 23 reads the
                          iOS 27.2 SDK's stubs; system LLVM 22 does not). The macOS-target
                          shims use it instead of /usr/bin, so no system default changes

--check reports what is recorded and whether it is usable, and writes nothing.
The tools themselves stay installed where they are (AGENTS.md, Disk).
"""

import os
import re
import shutil
import stat
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "build"))
import inputs  # noqa: E402
import phonelib  # noqa: E402

IOS_SDK = "Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.2.sdk"
OPTIONS = {"--llvm-mingw": "LLVM_MINGW", "--darwin-sdk": "DARWIN_SDK", "--usbmux-socket": "PLAYPORT_USBMUX_SOCKET",
           "--host-clang-bin": "HOST_CLANG_BIN", "--host-llvm15-bin": "HOST_LLVM15_BIN"}


def out(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=60).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def find_llvm_mingw():
    clang = shutil.which("aarch64-w64-mingw32-clang")
    return os.path.dirname(os.path.dirname(os.path.realpath(clang))) if clang else None


def find_darwin_sdk():
    m = re.search(r'toolsetPaths: \["([^"]+)"', out(["swift", "sdk", "configure", "--show-configuration",
                                                     "darwin", "arm64-apple-ios"]))
    return os.path.dirname(m.group(1)) if m else None


def find_socket():
    return phonelib.netmuxd_unit_socket()


def find_host_clang_bin():
    d = "/usr/lib/llvm-22/bin"
    return d if os.path.isfile(os.path.join(d, "clang")) else None


FIND = {"LLVM_MINGW": find_llvm_mingw, "DARWIN_SDK": find_darwin_sdk, "PLAYPORT_USBMUX_SOCKET": find_socket,
        "HOST_CLANG_BIN": find_host_clang_bin, "HOST_LLVM15_BIN": lambda: None}


def problem(key, v):
    """Why V is not usable for KEY, or None."""
    if not v:
        return "not found: pass it as an option (pp setup --help)"
    if key == "LLVM_MINGW":
        if not os.access(os.path.join(v, "bin/aarch64-w64-mingw32-clang"), os.X_OK):
            return "no bin/aarch64-w64-mingw32-clang"
        if not os.path.isfile(os.path.join(v, "aarch64-w64-mingw32/lib/libgcc.a")):
            return "no arm64ec CRT rebuild (docs/BUILDING.md, llvm-mingw)"
    elif key == "DARWIN_SDK":
        if not os.path.isdir(os.path.join(v, IOS_SDK)):
            return f"no {os.path.basename(IOS_SDK)} (xtool sdk install; docs/BUILDING.md)"
    elif key == "HOST_LLVM15_BIN":
        for tool in ("llvm-as", "llvm-dis", "llvm-link", "llc", "opt"):
            if not os.access(os.path.join(v, tool), os.X_OK):
                return f"no {tool} (LLVM 15.0.7: tools/workstation/setup.sh install)"
        ver = out([os.path.join(v, "llvm-as"), "--version"])
        if not re.search(r"LLVM version 15\.0\.7", ver):
            return "llvm-as here is not LLVM 15.0.7"
    elif key == "HOST_CLANG_BIN":
        for tool in ("clang", "clang++", "ld64.lld"):
            if not os.access(os.path.join(v, tool), os.X_OK):
                return f"no {tool} (LLVM 23.x: docs/BUILDING.md, host LLVM)"
        ver = out([os.path.join(v, "clang"), "--version"]).splitlines()
        # LLVM 23 or later: its ld64.lld reads the iOS 27.2 SDK's stubs (tbd v4, arm64e.x1); 22 does not.
        if not ver or not re.search(r"version 23\.", ver[0]):
            return "clang here is not 23.x"
    elif key == "PLAYPORT_USBMUX_SOCKET":
        try:
            if not stat.S_ISSOCK(os.stat(v).st_mode):
                return "not a socket"
        except OSError:
            return "absent: is netmuxd running? (docs/DEVICE.md, Setup)"
    return None


def main(args):
    if "-h" in args or "--help" in args:
        print(__doc__)
        return 0
    check, given = False, {}
    while args:
        a = args.pop(0)
        if a == "--check":
            check = True
        elif a in OPTIONS and args:
            given[OPTIONS[a]] = os.path.abspath(os.path.expanduser(args.pop(0)))
        else:
            print(f"pp setup: unknown argument {a} (pp setup --help)", file=sys.stderr)
            return 2
    recorded = inputs.read()
    values, bad = dict(recorded), 0
    for key in inputs.KEYS:
        v = given.get(key) or os.environ.get(key) or recorded.get(key) or (None if check else FIND[key]())
        why = "not recorded: run pp setup" if check and not v else problem(key, v)
        # A socket that is down now is still the right path to record.
        bad += why is not None and not (key == "PLAYPORT_USBMUX_SOCKET" and v)
        print(f"{key:24} {v or '-'}" + (f"  ({why})" if why else ""))
        if v:
            values[key] = v
    where = inputs.rel(inputs.FILE)
    if check:
        print(f"pp setup: {where} {'is usable' if not bad else 'needs pp setup'}")
        return 1 if bad else 0
    if values != recorded:
        inputs.write(values)
        print(f"pp setup: wrote {where}")
    else:
        print(f"pp setup: {where} unchanged")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
