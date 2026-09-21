import Foundation
import XCTest
@testable import MarkdownHelpers

final class NavigatorRootSetTests: XCTestCase {

    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    // MARK: - mount

    func testMountReplaceSetsExplicitRootsInOrder() {
        var set = NavigatorRootSet()
        XCTAssertTrue(set.mount([url("/a"), url("/b")], mode: .replace))
        XCTAssertEqual(set.urls.map(\.path), ["/a", "/b"])
        XCTAssertTrue(set.roots.allSatisfy(\.isExplicit))
        XCTAssertTrue(set.hasExplicitRoots)
    }

    func testMountReplaceDropsEverything() {
        var set = NavigatorRootSet()
        set.mount([url("/a"), url("/b")], mode: .replace)
        XCTAssertTrue(set.mount([url("/c")], mode: .replace))
        XCTAssertEqual(set.urls.map(\.path), ["/c"])
    }

    func testMountAddAppendsAndPreservesOrder() {
        var set = NavigatorRootSet()
        set.mount([url("/a")], mode: .replace)
        XCTAssertTrue(set.mount([url("/b"), url("/c")], mode: .add))
        XCTAssertEqual(set.urls.map(\.path), ["/a", "/b", "/c"])
    }

    func testMountDuplicatePathIsANoOp() {
        var set = NavigatorRootSet()
        set.mount([url("/a")], mode: .replace)
        XCTAssertFalse(set.mount([url("/a")], mode: .add))
        XCTAssertFalse(set.mount([url("/a/")], mode: .add)) // standardizes to /a
        XCTAssertEqual(set.urls.map(\.path), ["/a"])
    }

    func testMountDedupesWithinTheBatch() {
        var set = NavigatorRootSet()
        XCTAssertTrue(set.mount([url("/a"), url("/a"), url("/b")], mode: .replace))
        XCTAssertEqual(set.urls.map(\.path), ["/a", "/b"])
    }

    func testMountReplaceWithSameRootsReportsNoChange() {
        var set = NavigatorRootSet()
        set.mount([url("/a"), url("/b")], mode: .replace)
        XCTAssertFalse(set.mount([url("/a"), url("/b")], mode: .replace))
    }

    // MARK: - overlap (D4)

    func testOverlappingAncestorAndDescendantRootsBothRetained() {
        var set = NavigatorRootSet()
        set.mount([url("/proj")], mode: .replace)
        XCTAssertTrue(set.mount([url("/proj/docs")], mode: .add))
        XCTAssertEqual(set.urls.map(\.path), ["/proj", "/proj/docs"])
    }

    // MARK: - remove

    func testRemoveDropsTheMatchingRoot() {
        var set = NavigatorRootSet()
        set.mount([url("/a"), url("/b")], mode: .replace)
        XCTAssertTrue(set.remove(url("/a")))
        XCTAssertEqual(set.urls.map(\.path), ["/b"])
    }

    func testRemoveOfUnknownRootIsANoOp() {
        var set = NavigatorRootSet()
        set.mount([url("/a")], mode: .replace)
        XCTAssertFalse(set.remove(url("/zzz")))
        XCTAssertEqual(set.urls.map(\.path), ["/a"])
    }

    // MARK: - accommodate (D3)

    func testAccommodateImplicitOnlySetFollowsAnUnrelatedFile() {
        var set = NavigatorRootSet()
        // Seed the implicit root as the app does on first open.
        XCTAssertTrue(set.accommodate(openFileURL: url("/x/README.md")))
        XCTAssertEqual(set.urls.map(\.path), ["/x"])
        XCTAssertFalse(set.hasExplicitRoots)

        XCTAssertTrue(set.accommodate(openFileURL: url("/y/notes.md")))
        XCTAssertEqual(set.urls.map(\.path), ["/y"])
    }

    func testAccommodateLeavesTheSetWhenFileIsInsideARoot() {
        var set = NavigatorRootSet()
        set.accommodate(openFileURL: url("/x/README.md"))
        // A nested file still counts as inside the root.
        XCTAssertFalse(set.accommodate(openFileURL: url("/x/sub/deep.md")))
        XCTAssertEqual(set.urls.map(\.path), ["/x"])
    }

    func testAccommodateLeavesAnExplicitSetForAnOutsideFile() {
        var set = NavigatorRootSet()
        set.mount([url("/a"), url("/b")], mode: .replace)
        XCTAssertFalse(set.accommodate(openFileURL: url("/c/other.md")))
        XCTAssertEqual(set.urls.map(\.path), ["/a", "/b"])
    }

    func testAccommodateLeavesExplicitRootsForANilFile() {
        var set = NavigatorRootSet()
        set.mount([url("/a")], mode: .replace)
        XCTAssertFalse(set.accommodate(openFileURL: nil))
        XCTAssertEqual(set.urls.map(\.path), ["/a"])
    }

    func testAccommodateClearsAnImplicitRootForANilFile() {
        var set = NavigatorRootSet()
        set.accommodate(openFileURL: url("/x/README.md"))
        XCTAssertTrue(set.accommodate(openFileURL: nil))
        XCTAssertTrue(set.urls.isEmpty)
    }

    // MARK: - containingRoot (D4)

    func testContainingRootPicksTheFirstContainingRootInOrder() {
        var set = NavigatorRootSet()
        set.mount([url("/proj"), url("/proj/docs")], mode: .replace)
        // Both roots contain the file; the first in order wins.
        XCTAssertEqual(set.containingRoot(for: url("/proj/docs/guide.md"))?.url.path, "/proj")
        XCTAssertEqual(set.containingRoot(for: url("/proj/readme.md"))?.url.path, "/proj")
        XCTAssertNil(set.containingRoot(for: url("/elsewhere/x.md")))
    }

    // MARK: - PathDisambiguation

    func testLabelsLeaveUniqueNamesBare() {
        let labels = PathDisambiguation.labels(for: [url("/a/README.md"), url("/b/CHANGELOG.md")])
        XCTAssertEqual(labels[url("/a/README.md")], "README.md")
        XCTAssertEqual(labels[url("/b/CHANGELOG.md")], "CHANGELOG.md")
    }

    func testLabelsDisambiguateSharedNamesWithShortestParentSuffix() {
        let a = url("/proj/README.md")
        let b = url("/proj/child/README.md")
        let labels = PathDisambiguation.labels(for: [a, b])
        XCTAssertEqual(labels[a], "README.md (proj)")
        XCTAssertEqual(labels[b], "README.md (child)")
    }

    func testLabelsGrowTheSuffixUntilItDistinguishes() {
        // Two files whose immediate parents share a name ("child") need the
        // grandparent to disambiguate.
        let a = url("/one/child/README.md")
        let b = url("/two/child/README.md")
        let labels = PathDisambiguation.labels(for: [a, b])
        XCTAssertEqual(labels[a], "README.md (one/child)")
        XCTAssertEqual(labels[b], "README.md (two/child)")
    }

    func testLabelsDisambiguateIdenticalFolderNamesInDifferentParents() {
        let a = url("/projA/docs")
        let b = url("/projB/docs")
        let labels = PathDisambiguation.labels(for: [a, b])
        XCTAssertEqual(labels[a], "docs (projA)")
        XCTAssertEqual(labels[b], "docs (projB)")
    }
}
