## Picters compatibility channels

Manual builds default to `android16` (6.12.23, KMI5). `android17` contains the experimental 6.12.69/KMI6 tree; Android 17 support has not been established. Variant selection is independent of source branch: both use ReSukiSU.

All dispatch builds are artifacts only. Source `picters-compatibility.json` must match `build.config.constants`. Releases require `status: validated`, an Android SDK, tested exact vendor fingerprints, and the full ABI baseline check. Both channels currently have no validated vendor fingerprints, so releases are blocked.

A successful boot test is required before recording an actual `ro.vendor.build.fingerprint`. Do not infer it from the HyperOS version or SDK. New releases include `picters-update.json` binding the two assets to SDK, KMI generation, channel and tested vendor identities. Manager 1.3.3 rejects releases without this metadata and rechecks before installing.

Old managers also scan prereleases, so KMI6 module names deliberately omit `OOT-Modules`; old managers ignore them. KMI5 ZIP installers check Android SDK and, once validated, vendor fingerprint before modifying boot or installing modules. Experimental artifacts are for manual testing only and do not establish firmware compatibility.

# Picters Kernel CI Center

CI/CD that builds the **Picters kernel** (with extra out-of-tree modules) and the **Modules pack**
for the **Xiaomi 17 Series** (`sm8850`, *pudding*) — a Rust core (`ci_core`) driving source sync,
toolchain, ReSukiSU/SuSFS, the build and packaging via GitHub Actions.

Each release ships two assets: the flashable kernel (AnyKernel3) and a manager-agnostic
KernelSU/Magisk **Modules pack** (Wi-Fi injection, BT, CAN, SDR/DVB, NTFS). Non-Wi-Fi drivers load
at boot; Wi-Fi injection stays off until switched on in the Picters Modules Manager app.

## Build

Dispatch **Build Kernel** (`project=mi17_sm8850`, `branch=resukisu`) from the Actions tab. After
editing anything under `ci_core_rs/`, run **Build CI Core** first and let it finish.

## Credits

Base CI & kernel: **Kokuban / YuzakiKokuban** · Root: **ReSukiSU / KernelSU** · SuSFS:
**simonpunk** · Injection drivers: **aircrack-ng**, **morrownr**.
