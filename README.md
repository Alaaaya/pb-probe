# PB Probe

Owner-authorized, experimental local PosterBoard installation probe for iOS 17+.

Wallpaper-only code extracted from Alaaaya/Mirsa-iOS commit 1b16937.
No Mirsa source repository is changed. Gester-derived MIT access adapter retains its notice in LICENSES/Gester-MIT.txt. No Placard/Pocket Poster source is included.

Import validates ZIP paths, types, size limits, duplicates and checksums. Apply creates fresh descriptor UUIDs, targets only com.apple.WallpaperKit.CollectionsPoster, verifies destination SHA-256 and preferences readback, and preserves backup/report files in Documents/TendiesBackups. It does not respring or claim gallery registration.

Strict identity uses PosterBoard metadata plus existing datastore. Metadata-or-markers requires the active exact-path lease and an existing versioned CollectionsPoster directory. Readable contradictory metadata is always rejected. Diagnose reads PosterBoard only; acquisition temporarily swaps the signed own-group Caches path and restores it.

Signing must preserve/provision exactly one usable own app group, group.com.alaa.pbprobe. get-task-allow is NOT required. The IPA now embeds the group request in a verified ad-hoc signature, matching the packaging approach observed in Placard's official unsigned release; it still has no provisioning profile or device grant. RequestedEntitlements.plist is only a reference. Diagnose logs process entitlements, an own-executable signature fallback and FileManager group lookup. A different bundle ID needs its own compatible profile. Never add foreign/system group entitlements.

The new placard-style strategy independently reimplements the observed worse_query behavior through the existing MIT adapter. It temporarily redirects only the signed own group's Library/Caches to an allowlisted target, requests a class-7 part-3 container-manager extension with flags 0x8000000000 and no part-domain, consumes the token, then restores Caches immediately and uses the canonical target. Exact metadata/datastore paths receive separate scoped grants. A bounded fsgetpath inode pass discovers UUID container roots on the app's own data volume without assuming the parent is listable. Discovery reads only container identity attributes/metadata, not other app content. Only the identified PosterBoard wallpaper layout can be written. See RESEARCH.md for provenance and limitations.

Use Import, then Diagnose and Copy Log. Apply is experimental, separately confirmed and may make the wallpaper picker unstable. Existing descriptors are never replaced. Recovery backups must not be deleted.

Current v8 UI provides a separately confirmed one-shot Test Install for the exact approved Anime-Squad package. It does not invoke the legacy prefs-writing installer described above. No prefs, resets or registration IPC. Duplicate identity blocks installation. COPY PASS is not visible gallery/activation proof. Preserve InstallTests recovery material; a pending journal blocks repeated installs.

## Standalone import parity experiment

Branch `mirsa/standalone-import-parity` changes only normal archive/import
semantics, independently implemented from observed behavior. Container discovery,
lease/token acquisition and access mechanisms are unchanged.

The approved Anime-Squad SHA-256 remains the only installable archive. Extraction
uses pinned ZIPFoundation 0.9.20's public URL extractor for POSIX permissions and
modification dates, after a bounded streaming size/CRC pass. Explicit directory
attributes are applied last. Existing traversal, symlink, entry-count, expansion,
duplicate-path and Finder-junk protections remain; extraction requires a fresh
private empty directory. Hidden-file filtering intentionally remains stricter
than the reference importer.

For packages without an exact case-insensitive Container path component, one
10000...99999 integer updates only raw descriptor identifier text, the top-level
userInfo wallpaperRepresentingIdentifier, and the top-level Wallpaper.plist
identifier. Plist formats, nested IDs, filenames and suggestion metadata remain
unchanged. Atomic local rewrites retain restored mode/date.

Foundation copies the entire descriptor root to a fresh UUID, refusing existing
paths. Readback verifies hashes, paths, mode and mtime, not ownership/ACL/protection.
A failed initial copy has uncertain ownership and is retained for review. Later
rollback is allowed only with matching root inode/device and known contents.

An old pending journal, original identifier 7400, matching normalized identifier,
original descriptor UUID, or known prior test UUID blocks installation. Nothing
clears journals, deletes old tests or overwrites existing wallpapers. Alaa's prior
successful copy therefore remains a real blocker, not something this build
silently works around. Do not remove it to force this test.

No refresh/respring mechanism is included. No preferences, gallery-index writes,
registration IPC, reset or activation calls are added. Copy success is not gallery
acceptance proof. A prior normal reboot did not make the wallpaper visible.
No Mirsa edits, release publication or device execution is authorized here.
