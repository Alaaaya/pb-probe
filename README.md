# PB Probe

Owner-authorized, experimental local PosterBoard installation probe for iOS 17+.

Wallpaper-only code extracted from Alaaaya/Mirsa-iOS commit 1b16937.
No Mirsa source repository is changed. Gester-derived MIT access adapter retains its notice in LICENSES/Gester-MIT.txt. No Placard/Pocket Poster source is included.

Import validates ZIP paths, types, size limits, duplicates and checksums. Apply creates fresh descriptor UUIDs, targets only com.apple.WallpaperKit.CollectionsPoster, verifies destination SHA-256 and preferences readback, and preserves backup/report files in Documents/TendiesBackups. It does not respring or claim gallery registration.

Strict identity uses PosterBoard metadata plus existing datastore. Metadata-or-markers requires the active exact-path lease and an existing versioned CollectionsPoster directory. Readable contradictory metadata is always rejected. Diagnose reads PosterBoard only; acquisition temporarily swaps the signed own-group Caches path and restores it.

Signing must preserve get-task-allow and exactly one usable app group. PBProbe.entitlements requests group.com.alaa.pbprobe. Like Mirsa's unsigned build, the IPA has no signing profile or baked-in usable grant; the installer must provision and sign the group. The copied RequestedEntitlements.plist is a reference, not a grant. Diagnose logs the actual signed get-task-allow and usable group count. A different bundle ID necessarily needs its own compatible profile. Never add foreign/system group entitlements.

Use Import, then Diagnose and Copy Log. Apply is experimental, separately confirmed and may make the wallpaper picker unstable. Existing descriptors are never replaced. Recovery backups must not be deleted.
