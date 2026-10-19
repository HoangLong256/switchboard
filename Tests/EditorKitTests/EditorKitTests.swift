import EditorKit
import XCTest

final class EditorTabsTests: XCTestCase {
    func testPreviewIsReplacedByTheNextPreview() {
        var t = EditorTabs()
        t.open("/a", pinned: false)
        t.open("/b", pinned: false)
        XCTAssertEqual(t.paths, ["/b"])
        XCTAssertEqual(t.preview, "/b")
        XCTAssertEqual(t.active, "/b")
    }

    func testPinnedTabsStayAndPreviewTakesItsOwnSlot() {
        var t = EditorTabs()
        t.open("/a", pinned: true)
        t.open("/b", pinned: false)
        t.open("/c", pinned: false)
        XCTAssertEqual(t.paths, ["/a", "/c"])
        t.pin("/c")
        t.open("/d", pinned: false)
        XCTAssertEqual(t.paths, ["/a", "/c", "/d"])
        XCTAssertEqual(t.preview, "/d")
    }

    func testOpeningAnOpenPreviewPinnedKeepsIt() {
        var t = EditorTabs()
        t.open("/a", pinned: false)
        t.open("/a", pinned: true)   // double click after the single click
        XCTAssertNil(t.preview)
        t.open("/b", pinned: false)
        XCTAssertEqual(t.paths, ["/a", "/b"])
    }

    func testNewTabGoesRightOfTheActiveOne() {
        var t = EditorTabs()
        t.open("/a", pinned: true)
        t.open("/b", pinned: true)
        t.active = "/a"
        t.open("/c", pinned: true)
        XCTAssertEqual(t.paths, ["/a", "/c", "/b"])
    }

    func testCloseActivatesTheNeighbor() {
        var t = EditorTabs()
        for p in ["/a", "/b", "/c"] { t.open(p, pinned: true) }
        t.active = "/b"
        t.close("/b")
        XCTAssertEqual(t.active, "/c")
        t.close("/c")
        XCTAssertEqual(t.active, "/a")
        t.close("/a")
        XCTAssertNil(t.active)
    }
}

final class TextDocumentTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("doc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func file(_ name: String, _ text: String) throws -> String {
        let p = dir.appendingPathComponent(name).path
        try Data(text.utf8).write(to: URL(fileURLWithPath: p))
        return p
    }

    /// Later modification date than the last write, so the change is visible even within one second.
    private func touchLater(_ p: String, _ text: String) throws {
        try Data(text.utf8).write(to: URL(fileURLWithPath: p))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: p)
    }

    func testEditSave() throws {
        let p = try file("a.txt", "one")
        var d = TextDocument.open(p)
        XCTAssertEqual(d.load, .text)
        XCTAssertFalse(d.isDirty)
        d.text = "two"
        XCTAssertTrue(d.isDirty)
        XCTAssertEqual(d.save(), .saved)
        XCTAssertFalse(d.isDirty)
        XCTAssertEqual(try String(contentsOfFile: p, encoding: .utf8), "two")
    }

    func testCleanDocumentFollowsTheDisk() throws {
        let p = try file("a.txt", "one")
        var d = TextDocument.open(p)
        try touchLater(p, "changed by claude")
        XCTAssertTrue(d.reloadIfClean())
        XCTAssertEqual(d.text, "changed by claude")
        XCTAssertFalse(d.isDirty)
    }

    func testDirtyDocumentIsNotReloadedAndSavingIsAConflict() throws {
        let p = try file("a.txt", "one")
        var d = TextDocument.open(p)
        d.text = "my edit"
        try touchLater(p, "changed by claude")
        XCTAssertFalse(d.reloadIfClean())
        XCTAssertEqual(d.text, "my edit")
        XCTAssertEqual(d.save(), .conflict)
        XCTAssertEqual(try String(contentsOfFile: p, encoding: .utf8), "changed by claude", "nothing written on conflict")
        XCTAssertEqual(d.diskText(), "changed by claude")
        XCTAssertEqual(d.save(overwrite: true), .saved)
        XCTAssertEqual(try String(contentsOfFile: p, encoding: .utf8), "my edit")
    }

    func testRevert() throws {
        let p = try file("a.txt", "one")
        var d = TextDocument.open(p)
        d.text = "oops"
        d.revert()
        XCTAssertEqual(d.text, "one")
        XCTAssertFalse(d.isDirty)
    }

    func testBinaryInvalidUTF8MissingAndOpenAnyway() throws {
        let bin = dir.appendingPathComponent("b.bin").path
        try Data([0x41, 0x00, 0x42]).write(to: URL(fileURLWithPath: bin))
        XCTAssertEqual(TextDocument.open(bin).load, .binary)
        let latin = dir.appendingPathComponent("l.txt").path
        try Data([0x63, 0x61, 0x66, 0xE9]).write(to: URL(fileURLWithPath: latin))   // "café" in Latin-1
        XCTAssertEqual(TextDocument.open(latin).load, .binary)
        XCTAssertEqual(TextDocument.open(bin, force: true).load, .text)
        XCTAssertEqual(TextDocument.open(dir.appendingPathComponent("nope").path).load, .missing)
    }
}
