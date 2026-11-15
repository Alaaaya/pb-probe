// Host-only fixtures exercise exact targeting, not sandbox access.
#import "../Sources/ContainerCandidates.m"
void mirsa_pb_progress(const char *message) {}
static void check(BOOL ok, NSString *message) {
    if (!ok) { NSLog(@"FAIL %@", message); exit(1); }
}
int main(void) { @autoreleasepool {
    NSString *root = @"/var/mobile/Containers/Data/Application/11111111-2222-3333-4444-555555555555";
    NSString *store = @"Library/Application Support/PRBPosterExtensionDataStore";
    check([PBContainerFromPath(root) isEqualToString:root], @"UUID root");
    check([PBContainerFromPath([@"/private" stringByAppendingString:root]) isEqualToString:root], @"private alias");
    check([PBContainerFromPath([root stringByAppendingPathComponent:store]) isEqualToString:root], @"target ancestor");
    check(!PBContainerFromPath(@"/var/mobile/Containers/Data/Application/not-a-uuid"), @"invalid UUID");
    check(!PBContainerFromPath(@"/var/mobile/Containers/Shared/AppGroup/11111111-2222-3333-4444-555555555555"), @"wrong root");
    check(!PBContainerFromPath([root stringByAppendingString:@"/../other"]), @"traversal");
    check(PBPosterHint(store), @"exact PosterBoard store");
    check(PBPosterHint([store stringByAppendingString:@"/61/Extensions"]), @"store descendant");
    check(PBPosterHint(@"Library/Preferences/com.apple.PosterBoard.unprotectedUserDefaults.plist"), @"exact pref");
    check(!PBPosterHint(@"Documents/com.apple.PosterBoard.plist"), @"unrelated document");
    check(!PBPosterHint(@"Library/Application Support/PRBPosterExtensionDataStoreFake"), @"prefix collision");
    check(!PBPosterHint(@".com.apple.mobile_container_manager.metadata.plist"), @"generic metadata is not a hint");
    check(!PBPosterHint(@"Library/Preferences/com.apple.other.plist"), @"unrelated pref");
    NSLog(@"PASS discovery targeting fixtures");
    return 0;
}}
