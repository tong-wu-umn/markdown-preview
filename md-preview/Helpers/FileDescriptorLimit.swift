//
//  FileDescriptorLimit.swift
//  md-preview
//
//  Apps launched by LaunchServices (Finder, Dock, `open`) start with a soft
//  limit of 256 open file descriptors. The Project Navigator holds one
//  descriptor per watched folder, so a large mounted tree can reach that
//  limit. After that the app cannot read the document the user clicked
//  ("NSCocoaErrorDomain error 256"). Its own frameworks fail as well:
//  LaunchServices crashed updating Open Recent, and Foundation showed error
//  text without loading its localized strings. A shell launch inherits the
//  shell's much higher limit, which is why none of this reproduced from a
//  terminal. Raising the soft limit at launch removes the difference. Kept
//  free of AppKit so the SPM helper tests can exercise it.
//

import Foundation

enum FileDescriptorLimit {
    /// `OPEN_MAX`: the largest soft limit `setrlimit` accepts for
    /// RLIMIT_NOFILE on macOS without extra conditions.
    static let target: rlim_t = 10_240

    /// Raises the soft RLIMIT_NOFILE to `target`, capped by the hard limit.
    /// Never lowers it. Returns the soft limit in effect afterwards, or nil if
    /// it could not be read.
    @discardableResult
    static func raiseSoftLimit(to target: rlim_t = target) -> rlim_t? {
        var limit = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &limit) == 0 else { return nil }
        let desired = min(target, limit.rlim_max)
        guard limit.rlim_cur < desired else { return limit.rlim_cur }
        var raised = limit
        raised.rlim_cur = desired
        guard setrlimit(RLIMIT_NOFILE, &raised) == 0 else { return limit.rlim_cur }
        return desired
    }
}
