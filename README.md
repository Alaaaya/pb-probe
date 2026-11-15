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
original descriptor UUID, or known prior test UUID blocks installation. No install path clears journals, deletes old tests or overwrites existing wallpapers.
Historical pending state blocks installation unless separately reconciled as described below.

No refresh/respring mechanism is included. No preferences, gallery-index writes,
registration IPC, reset or activation calls are added. Copy success is not gallery
acceptance proof. A prior normal reboot did not make the wallpaper visible.
No Mirsa edits, release publication or device execution is authorized here.


The standalone parity build additionally offers a separately confirmed **Remove Prior Anime Test** operation. This is owner-approved only for descriptor BE2EE206-9948-4F2B-BD3E-C02042EDBC5D, journal B6DDAE7B-791A-4618-A85E-D9AC55BDF09E, CollectionsPoster store61. It checks strict container identity, the completed historical journal and archive hash, an independently pinned exact 26-file manifest, complete path inventory and current held inode identities. Extra/missing/changed files, links, redirects or unavailable evidence fail closed. A byte-verified synced backup and journal proof are retained BEFORE the first deletion. Removal uses held directory descriptors and individual no-follow checked unlink operations, never recursive deletion. Unexpected changes may stop partway; preserve evidence and never retry blindly. Only after verified target absence and lease close is this exact journal's pending marker renamed, preserving its contents. No other journal is cleared. No device execution has been performed. No automatic reinstall, index/preference write, reset or refresh is part of cleanup. Button presence and compile success do not prove device behavior.


## Current v13 journal-only reconciliation

The owner externally removed the historical wallpaper. Build18's read-only
exact-path syscall observations found ENOENT. Those past observations alone do
not authorize clearing any marker. The current explicit confirmation archives
ONLY InstallTests/B6DDAE7B-791A-4618-A85E-D9AC55BDF09E/pending.json,
after fresh conservative absence checks for descriptor BE2EE206 in store61
using the existing diagnostic, strict container identity and unchanged grants.
Presence, denial, redirects, journal changes and uncertain absence stop the action.

Original completed-copy evidence, archive SHA and historical manifest must match.
Held local directory/marker inodes and bytes are rechecked. Original journal bytes,
a scope proof and the fresh observation transcript are synced locally. Only after
successful lease close is the exact marker exclusively renamed to
reconciled-absent-anime-pending.json in the SAME own-app journal directory.
Existing archive destinations, including dangling links, are never overwritten.
No PosterBoard files are written or removed by reconciliation. No new access
mechanism, preferences, indexes, reset, refresh or Mirsa changes are introduced.
The older removal action is disabled in both UI and model.

Same-certificate UPDATE in place, without deleting the app or its data.
Choose Reconcile Prior Anime Journal, confirm, then Copy Log and STOP.
Do not import/install until the actual result has been reviewed. After successful
reconciliation in the same process session, the existing approved Import and
separately confirmed Test Install become available. Installation never autoruns.
Relaunch intentionally resets this UI eligibility; do not delete evidence or
repeat reconciliation blindly if pending has already been archived.
Absence is a conservative point-in-time observation, not a guarantee against a
future external writer. Existing install duplicate and pending-journal guards
remain. Neither build success nor copy success proves device/gallery behavior.


## Read-only bounded Placard comparison diagnostic v15

Compare With Placard reads only exact CollectionsPoster/descriptors and its necessary ancestors through the unchanged exact-path lease/grant implementation. Our pinned 43E29B4A UUID is opened and its tree read FIRST, without sibling enumeration. It then shallowly enumerates at most 256 names and checks root metadata of at most 12 UUID siblings. Only exact approved descriptor.identifier hashes or Anime-Squad title matches select at most two candidate trees for recursive hashing. Matching assets/title do NOT establish installer provenance or gallery visibility. Noncandidate versions/assets, all Clock/Photos providers, other store directories and external indexes are never traversed or granted. Candidate discovery can miss a copy, and cannot establish absence.

Cooperative defaults are 30 seconds, 128 total extra grant attempts (bounding retained native handles, plus the existing fixed identity/base grants), two denied grants, 512 visited entries, depth 20, 8MiB per full-tree file, 64KiB per root metadata file and 32MiB total reads. Limits are checked before every new grant, directory iteration and read loop. An individual native call is not preemptible, so 30 seconds is not a hard completion deadline. Phase/count checkpoints show incremental progress. Limits, denial, errors and final path revalidation failure preserve partial observations and a terminal report; lease close is attempted before returning it, with explicit cleanup errors rather than false closure claims.

Reports include recursive selected metadata, SHA256, xattr names (not values), protection class, full decoded plists/JSON and DIFF. External index/reference search is deliberately NOT performed. All import/install/removal/reconciliation actions remain model-blocked. No native access changes, PosterBoard/index/preference writes, refresh, device actions, Mirsa changes or publication. Build/fixture success is not device verification. Session display is limited to 4MB with an explicit incomplete marker. Update in place using the same certificate without deleting app/data; Compare With Placard once, wait, Copy Log and stop.


## Build 26 copy plus separately confirmed respring

After successful Test Install readback and lease close, a second confirmation offers the local iframe/WebKit compositor-stress mechanism observed in Placard's NeoSpring completion stage. Independent implementation; mechanism credits rooootdev, skadz108 and neonmodder123. The page is nonpersistent and local-only. This intentionally disruptive attempt can close apps or interrupt unsaved work. It is not PosterBoard registration IPC and does not prove gallery acceptance. Skip leaves the copied descriptor alone. No payload runs on launch, failure, reconciliation, comparison, or diagnosis. No automatic retry after web process termination. Stop/return clears the local page.

BEFORE evidence is saved and synchronized in Documents/LastRefreshAttempt.txt before opening WebKit; inability to save blocks the attempt. AFTER observations record page load, navigation errors, process termination or dismissal only, never assert that a system respring happened. Evidence is shown on next app launch; an actual respring may interrupt callbacks. Reconcile still requires exact absence of the journal's descriptor and modifies only the own-app pending marker. Device behavior and the proposed boot-cleanup hypothesis remain unverified.
