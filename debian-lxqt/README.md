# xorriso — Debian LXQt foundation (experimental)

This is a **separate, not-yet-validated** live ISO path, alongside the existing initramfs implementation.
It deliberately does not replace `build-from-source.sh`, change GRUB boot on the old ISO,
or modify/mount/format `XORRISO_DATA` and `XORRISO_RUNTIME`.

## What this phase includes
- Debian 13 (trixie), amd64, official Debian live-build tooling.
- Xorg + LXQt + SDDM with a dedicated `xorriso` account, automatic graphical login.
- Minimal LXQt panel configuration, network manager and base userland.
- No unattended administrative rights. No direct raw shell root from an LLM.

## What is **not** integrated yet
The current project's `src/ai-agent.sh`, `src/root-exec.sh`, MiniCPM runtime and VDI discovery
were designed for the original BusyBox initramfs (they reference `/run/xorriso`,
`/data`, `/runtime-data`, `/bin/busybox`, etc.). Copying them into Debian without
adapting and testing would falsely claim a working administrator. This scaffold
does **not** install or start them yet. The GUI AI client is also not integrated.

## Build
Run on a Debian/Ubuntu **build host** (not in your VirtualBox VM):
```sh
sudo apt-get update
sudo apt-get install -y live-build xorriso
bash debian-lxqt/build.sh
```
The build needs root for live-build and Internet access for Debian packages.
Result, if successful: `debian-lxqt/work/live-image-amd64.hybrid.iso`.
This pathname is an expected output, **not a verified existing ISO**.

## Validation gates before calling it a xorriso release
1. Boot a new **disposable** VirtualBox VM from the ISO, with no existing user VDIs attached.
2. Repeat cold boots and restarts; verify SDDM enters the LXQt session without keyboard shortcuts.
3. Ensure the original two VDIs remain untouched and do not attach them before a read-only mount/detection design is reviewed.
4. Adapt MiniCPM server to a dedicated unprivileged systemd service; show real loading/failure states.
5. Adapt agent as an unprivileged client using the local model API; connect audited, authorized privileged operations through an explicit service (not arbitrary root shell).
6. Confirm that questions about abilities never execute actions; test create/list/read and administrative approval/denial.
7. Add end-to-end graphical boot tests and publish a real ISO only after they pass.

For now, the original ISO build path remains the known experimental fallback.
