# Keep fast-forward playback on footage between recording windows

At 8×, each two-minute recording window lasts about fifteen seconds. Aura previously loaded the following window only at that boundary, briefly showing “No footage at this time” in detail even when recordings continued.

Prepare the following completed window while the current footage plays and reuse its ready, paused player in the Timeline grid and camera detail. Keep the last valid detail frame during handoff, preserve real gaps and growing-window freshness, and coalesce recovery requests after a failed preload. Ignore callbacks from replaced players. This is the 0.8.3 playback patch (build 67).

Validation: all host package tests, 892 iOS Simulator package tests, and both iOS/macOS app builds passed, including twelve regressions reproduced before their fixes. The pinned iOS 26.5 snapshot check remains required before acceptance. Snapshot references and tolerances are unchanged.

Physical iPhone frame continuity against real Frigate recordings remains a post-merge TestFlight check. The Xcode 27 migration is separate.
