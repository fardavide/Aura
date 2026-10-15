# Pin Xcode 27 and refresh iOS snapshot references

Build and test Aura with Xcode 27.0 build 27A266a on the `xcode-27` runner. Snapshot tests use a test-owned iPhone 17 on iOS 27.0 build 24A434 and wait for it to boot. Missing or mismatched toolchains/runtimes fail visibly. iOS 26 and macOS 26.5 support remain declared.

Re-record and review all 592 iOS reference images for the new rendering environment. Keep the existing four required checks, full device/appearance matrix, comparison tolerances, dependency pins, and failure artifacts. The playback fix has already merged separately.

Validation on main at `5a48558`:
- 940 host package tests and 880 iOS package tests passed.
- All 79 snapshots passed after rebasing. Two earlier independent full comparisons also passed.
- Both app builds and four CI environment tests passed.
- Visual review covered 592 panels and 11 full-resolution comparison pairs; no new missing content or controls found.

Remaining before migration acceptance: execute the candidate on the hosted runner and validate Xcode 27-built code on iOS 26. The local machine currently has only iOS 27. Xcode Cloud archive settings and signed distribution remain separate.
