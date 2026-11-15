// Independent bounded candidate discovery using the Darwin fsgetpath API.
// No third-party implementation is incorporated.
#import <Foundation/Foundation.h>
#include <sys/fsgetpath.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/xattr.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

extern void mirsa_pb_progress(const char *message);

static NSString *candidateIdentity(NSString *path) {
    for (NSString *key in @[@"com.apple.containermanager.identity", @"com.apple.containermanager.identifier"]) {
        char value[65537];
        ssize_t size = getxattr(path.fileSystemRepresentation, key.UTF8String, value, sizeof(value) - 1, 0, XATTR_NOFOLLOW);
        if (size <= 0 || size > 65536) continue;
        value[size] = 0;
        NSString *text = [[NSString alloc] initWithBytes:value length:(NSUInteger)size encoding:NSUTF8StringEncoding];
        NSMutableCharacterSet *trim = [NSCharacterSet.whitespaceAndNewlineCharacterSet mutableCopy];
        [trim addCharactersInString:[NSString stringWithFormat:@"%C", (unichar)0]];
        for (NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
            NSString *clean = [line stringByTrimmingCharactersInSet:trim];
            if ([clean hasPrefix:@"identifier:"]) return [[clean substringFromIndex:11] stringByTrimmingCharactersInSet:trim];
        }
        NSString *clean = [text stringByTrimmingCharactersInSet:trim];
        if (clean.length && [clean rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@":\n\r"]].location == NSNotFound) return clean;
    }
    return nil;
}

char *mirsa_pb_candidates_copy_json(void) {
    @autoreleasepool {
        mirsa_pb_progress("DISCOVERY C BEFORE scratch open/fstat/fstatfs");
        NSMutableArray *unknown = [NSMutableArray array], *matched = [NSMutableArray array];
        NSMutableSet *seen = [NSMutableSet set];
        NSMutableDictionary *report = [NSMutableDictionary dictionary];
        report[@"unknown"] = unknown; report[@"matched"] = matched;
        NSString *scratch = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [@"pb-inode-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        int fd = open(scratch.fileSystemRepresentation, O_CREAT | O_EXCL | O_RDWR | O_CLOEXEC, 0600);
        struct stat file;
        struct statfs volume;
        BOOL ready = fd >= 0 && fstat(fd, &file) == 0 && fstatfs(fd, &volume) == 0;
        int saved = errno;
        if (fd >= 0) { close(fd); unlink(scratch.fileSystemRepresentation); }
        mirsa_pb_progress("DISCOVERY C AFTER own-volume setup; BEFORE inode scan (6-second cooperative budget)");
        if (!ready || file.st_ino > UINT64_MAX - 100000) {
            report[@"error"] = [NSString stringWithFormat:@"own-volume probe failed errno=%d", saved];
        } else {
            NSArray *roots = @[@"/var/mobile/Containers/Data/Application",
                               @"/var/mobile/Containers/Data/InternalDaemon",
                               @"/var/mobile/Containers/Data/PluginKitPlugin"];
            uint64_t limit = file.st_ino + 100000, visited = 0;
            NSTimeInterval started = NSProcessInfo.processInfo.systemUptime;
            BOOL stopped = NO;
            NSTimeInterval nextProgress = started + 1;
            char pathbuf[4096];
            for (uint64_t inode = 1; inode <= limit; inode++) {
                visited = inode;
                NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
                if (now - started >= 6) { stopped = YES; break; }
                if (now >= nextProgress) {
                    NSString *status = [NSString stringWithFormat:@"DISCOVERY progress BEFORE fsgetpath inode=%llu elapsed=%.1fs UUIDs=%lu",
                        (unsigned long long)inode, now-started, (unsigned long)seen.count];
                    mirsa_pb_progress(status.UTF8String);
                    nextProgress = now + 1;
                }
                if (fsgetpath(pathbuf, sizeof(pathbuf), &volume.f_fsid, inode) <= 0) continue;
                @autoreleasepool {
                    NSString *path = [NSString stringWithUTF8String:pathbuf];
                    if ([path hasPrefix:@"/private/var/"]) path = [path substringFromIndex:8];
                    if (![roots containsObject:path.stringByDeletingLastPathComponent] ||
                        ![[NSUUID alloc] initWithUUIDString:path.lastPathComponent] || [seen containsObject:path]) continue;
                    [seen addObject:path];
                    mirsa_pb_progress("DISCOVERY BEFORE candidate identity xattrs");
                    NSString *identifier = candidateIdentity(path);
                    mirsa_pb_progress("DISCOVERY AFTER candidate identity xattrs");
                    if ([identifier isEqualToString:@"com.apple.PosterBoard"]) [matched addObject:path];
                    else if (!identifier.length && unknown.count < 1024) [unknown addObject:path];
                    // Never emit unrelated bundle identifiers or read unrelated files.
                }
                if (matched.count) break;
            }
            report[@"visitedInodes"] = @(visited);
            report[@"timeLimited"] = @(stopped);
            report[@"seconds"] = @(NSProcessInfo.processInfo.systemUptime - started);
            report[@"UUIDContainersSeen"] = @(seen.count);
        }
        mirsa_pb_progress("DISCOVERY C AFTER inode scan; returning candidate report");
        NSData *data = [NSJSONSerialization dataWithJSONObject:report options:0 error:nil];
        NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        return strdup(json.UTF8String ?: "{}");
    }
}

char *mirsa_pb_container_identifier(const char *path) {
    @autoreleasepool {
        NSString *identifier = path ? candidateIdentity([NSString stringWithUTF8String:path]) : nil;
        return identifier ? strdup(identifier.UTF8String) : NULL;
    }
}
