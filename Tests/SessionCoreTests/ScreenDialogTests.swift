import SessionCore
import XCTest

/// Screens as Claude Code 2.1 shows them (captured with `tmux capture-pane -p`).
final class ScreenDialogTests: XCTestCase {
    let permission = """
    ⏺ Creating empty file named answer-test.txt
      ⎿  $ touch answer-test.txt
    ────────────────────────────────────────────────────────────
     Bash command
     Create empty file named answer-test.txt
     touch answer-test.txt
     Do you want to proceed?
     ❯ 1. Yes
       2. Yes, and always allow access to /tmp/realans from this project
       3. No
     Esc to cancel · Tab to amend
    """

    let trust = """
     Accessing workspace:
     /tmp/realans
     Quick safety check: Is this a project you created or one you trust?
     Claude Code'll be able to read, edit, and execute files here.
     Security guide
     ❯ No, exit
       Yes, I trust this folder
     Enter to confirm · Esc to cancel
    """

    func testPermissionDialogMapsToAllowAlwaysDeny() {
        let d = ScreenDialog.parse(permission)
        XCTAssertEqual(d?.options.map(\.number), [1, 2, 3])
        XCTAssertEqual(d?.permission(.allow)?.number, 1)
        XCTAssertEqual(d?.permission(.alwaysAllow)?.number, 2)
        XCTAssertEqual(d?.permission(.deny)?.number, 3)
        XCTAssertEqual(d?.options.first?.selected, true)
        XCTAssertFalse(ScreenDialog.hasOpenPrompt(permission) && d == nil)
    }

    func testAnotherDialogIsNotTheSame() {
        let d = ScreenDialog.parse(permission)!
        let edit = ScreenDialog.parse(permission.replacingOccurrences(of: "touch answer-test.txt", with: "rm -rf build"))!
        XCTAssertFalse(d.sameDialog(as: edit))
        XCTAssertTrue(d.sameDialog(as: ScreenDialog.parse(permission)!))
    }

    func testTrustPromptHasNoNumbersButIsOpen() {
        XCTAssertNil(ScreenDialog.parse(trust))
        XCTAssertTrue(ScreenDialog.hasOpenPrompt(trust))
    }

    func testNormalInputIsNoPrompt() {
        let idle = """
        ⏺ Done. The file answer-test.txt has been created.
        ──────────────────────────────
        ❯ 
        ──────────────────────────────
          Haiku 4.5 · ctx 19%
        """
        XCTAssertNil(ScreenDialog.parse(idle))
        XCTAssertFalse(ScreenDialog.hasOpenPrompt(idle))
    }
}
