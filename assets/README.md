# Bundled manager

Signed Picters Modules Manager **1.3.2**, versionCode **14**, arm64-v8a.

This APK fixes Ultra → Full switching under thermal GPU limits, displays Max for the Full GPU profile and keeps frequency chips compact with a stable width. It contains frequency fixes and a read-only GitHub Releases button. It has no update downloader, module installer, APK installer or boot flasher. Both A16 and A17 OOT packs embed this same APK, but each pack's kernel modules are compiled separately for its paired kernel.

Certificate SHA-256: `6e4c01c0ea50a7103a5c9e3a06e883f651f28fb34cdfb9ecfec9710701ee1bd7`.

The signed public APK is checked into CI to make each build reproducible without a separate application release or uploading the signing key. Refresh this file and its checksum whenever the manager changes. The private keystore remains outside Git.
