# Madeira wineserver and ntdll-unix link collisions (2026-11-14)

The app link (`S1Probe-App`, ld64) failed with four duplicate symbols
between `libwineserver.a` and `libntdll_unix.a`: `_server_start_time`,
`_supported_machines`, `_supported_machines_count` and `_native_machine`.
`server_ios.c` in ntdll-unix defines them, and wineserver's `request_ios.o`
and `registry.o` define them too.

The unix stage's linktest reported the same failure on the raw archive
(`LINK FAIL`) and linked a copy whose `_ws_`-renamed symbols were the four
names (`LINK OK`, 1001 gnutls functions linked). The Madeira wineserver build's
`COLLISIONS` rename list did not include them. patches/madeira-unix 0289 adds
them, so the wineserver archive is renamed like the other collisions.

Before the patch: `pp check` stopped at the app link with the four
duplicate symbols. The unix stage that produced the archive ran at
2026-11-14 11:33 (`.work/run/logs/unix.log`).
