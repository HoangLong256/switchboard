import Foundation
import StatusLineKit

// Status line command for Claude Code (`statusLine` in ~/.claude/settings.json): stores plan limits, context
// and cost for Switchboard under ~/.switchboard and prints "Opus 5.5 · ctx 37% · 5h 12% · wk 40%".
let env = ProcessInfo.processInfo.environment
let dataDir = env["SWITCHBOARD_DATA"] ?? "\(NSHomeDirectory())/.switchboard"
let input = FileHandle.standardInput.readDataToEndOfFile()
let output = StatusLine.process(input)
StatusLine.write(output, dataDir: dataDir)
print(output.line)
