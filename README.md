# Picters Kernel CI Center

Build and package Picters kernels for Xiaomi 17 (`pudding`, SM8850), with ReSukiSU, SUSFS, extra drivers and Picters Modules Manager.

## Compatibility channels

| Channel | Base | Kernel archive | Matching modules archive |
| --- | --- | --- | --- |
| **A16** | Linux 6.12.23 · KMI 5 · ReSukiSU | `Mi17_Kernel-6.12.23-android16-…-YYYYMMDD-HHMM.zip` | `Mi17_OOTMODULES-6.12.23-android16-…-YYYYMMDD-HHMM.zip` |
| **A17 — experimental** | Linux 6.12.69 · KMI 6 · ReSukiSU | `Mi17_Kernel-6.12.69-android17-…-YYYYMMDD-HHMM.zip` | `Mi17_OOTMODULES-6.12.69-android17-…-YYYYMMDD-HHMM.zip` |

Install the matching pair for your Android version; the A17 kernel and app have not been tested on Android 17 firmware.

Each OOT pack contains modules compiled for its exact kernel and signed **Picters Modules Manager**. The original blue **Update** chip appears only for a newer release in the installed channel and opens the latest GitHub release. Downloads, APK/module installation and kernel flashing have been removed from the app. Manager 1.3.1 does not recognize the new OOTMODULES filenames.

## Manual installation

1. Download both archives from the same release and channel.
2. Install and boot the kernel using an AnyKernel3-compatible installer.
3. Install its matching OOT pack through KernelSU/Magisk and reboot. The manager is delivered as a system app.

The OOT installer checks the exact running kernel release. Its boot service skips loading drivers after a kernel change. App settings survive module updates. Non-Wi-Fi boot loading is optional; Wi-Fi injection remains off until enabled in the manager.

## Build

Run **Build A16 and A17 packages** to build both channels, or **Build Kernel** for one channel (`project=mi17_sm8850`, `branch=android16` or `android17`). Both channels use only ReSukiSU. The CI core is compiled from source during each build.

Kernel pushes call this reusable workflow directly; no repository-dispatch token is required. The workflow explicitly checks out this CI repository for its build tools. Automatic builds and the dual-channel workflow produce artifacts only.

The signed public APK is pinned in `assets/` with its SHA-256. The private keystore remains outside Git. Packaging verifies the APK checksum and never fetches a separate application release.

Each build includes both ZIPs, `SHA256SUMS`, `build-info.json`, `kmi-report.json` and `RELEASE-NOTES.md`. Manually published releases group both Android pairs under `Mi17_Kernel-ReSuki-susfs-YYYYMMDD-HHMM`. Automated publication still requires validated vendor compatibility and the ABI check.

## Credits

Base CI & kernel: **Kokuban / YuzakiKokuban** · Root: **ReSukiSU / KernelSU** · SUSFS: **simonpunk** · USB Wi-Fi drivers: **aircrack-ng**, **morrownr**.
