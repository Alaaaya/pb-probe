# Placard access research

Read-only reference was frs0n/placard 7f470dd0242f9d69ea5ad17e521566487706c891. Its source is GPLv3. No source was copied into this repository. Newly written code is an independent behavior-level implementation added to the existing MIT Gester-derived adapter; it is not presented as a license opinion.

Placard calls this method worse_query. Its normal path uses libsystem_containermanager container_query_create, container_query_set_class (7, own app-group), container_query_set_group_identifiers (a scalar XPC string), container_query_operation_set_part (3, cache), container_query_operation_set_flags (0x8000000000 on iOS27; alternative 0x800000000 for iOS26), container_query_get_single_result and container_copy_sandbox_token. It does not set part_domain. Its own app-group Library/Caches is temporarily a symlink to the requested path; sandbox_extension_consume consumes the returned extension before Caches is restored. It then accesses the canonical target, not a retained Caches alias. Separate root, metadata, datastore and descriptor grants avoid assuming a root grant is recursive.

It discovers exact UUID children of the Application/InternalDaemon/PluginKitPlugin data roots using fsgetpath on the app's data volume, with a bounded inode pass; xattr identity or MCMMetadataIdentifier identifies com.apple.PosterBoard. It does not need to list the parent directory. App groups are obtained from process entitlements with an own Mach-O embedded-entitlement fallback, then checked via FileManager group-container lookup.

Official release inspected was v2.0.3, downloaded from https://github.com/frs0n/placard/releases/download/v2.0.3/placard-v2.0.3-unsigned.ipa .
SHA256 eeec5ab5063477d1f65b3835eb4ebabb2186ad766d84ae7f5e610b50dcc23f83.
Its built executable's LC_CODE_SIGNATURE XML entitlements contain only com.apple.security.application-groups = [group.me.ssus.placard]. No get-task-allow, system-container entitlement or provisioning profile was found. We did not inspect the owner's re-signed copy, so its actual final grants are unknown.

Differences from the previous Probe include corrected flags (previously 0x8100000000), immediate restoration/canonical-path use, per-path extension acquisition, embedded ad-hoc app-group request, executable entitlement fallback and inode-based discovery. None alone is yet proven to explain the owner's failure. A signer can still strip or fail to provision the group. Device success remains unverified.
