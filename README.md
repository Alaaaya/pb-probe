# PB Probe

Owner-authorized, experimental local PosterBoard installation probe for iOS 17+.

Wallpaper-only code extracted from Alaaaya/Mirsa-iOS commit 1b16937.
No Mirsa source repository is changed. Gester-derived MIT access adapter retains its notice in LICENSES/Gester-MIT.txt. No Placard/Pocket Poster source is included.

Import validates ZIP paths, types, size limits, duplicates and checksums. Apply creates fresh descriptor UUIDs, targets only com.apple.WallpaperKit.CollectionsPoster, verifies destination SHA-256 and preferences readback, and preserves backup/report files in Documents/TendiesBackups. It does not respring or claim gallery registration.

Strict identity uses PosterBoard metadata plus existing datastore. Metadata-or-markers requires the active exact-path lease and an existing versioned CollectionsPoster directory. Readable contradictory metadata is always rejected. Diagnose reads PosterBoard only; acquisition temporarily swaps the signed own-group Caches path and restores it.

Signing must preserve/provision exactly one usable own app group, group.com.alaa.pbprobe. get-task-allow is NOT required. The IPA now embeds the group request in a verified ad-hoc signature, matching the packaging approach observed in Placard's official unsigned release; it still has no provisioning profile or device grant. RequestedEntitlements.plist is only a reference. Diagnose logs process entitlements, an own-executable signature fallback and FileManager group lookup. A different bundle ID needs its own compatible profile. Never add foreign/system group entitlements.

The new placard-style strategy independently reimplements the observed worse_query behavior through the existing MIT adapter. It temporarily redirects only the signed own group's Library/Caches to an allowlisted target, requests a class-7 part-3 container-manager extension with flags 0x8000000000 and no part-domain, consumes the token, then restores Caches immediately and uses the canonical target. Exact metadata/datastore paths receive separate scoped grants. A bounded fsgetpath inode pass discovers UUID container roots on the app's own data volume without assuming the parent is listable. Discovery reads only container identity attributes/metadata, not other app content. Only the identified PosterBoard wallpaper layout can be written. See RESEARCH.md for provenance and limitations.

Use Import, then Diagnose and Copy Log. Apply is experimental, separately confirmed and may make the wallpaper picker unstable. Existing descriptors are never replaced. Recovery backups must not be deleted.
