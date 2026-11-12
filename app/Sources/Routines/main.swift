import AppKit
import Foundation
import RoutinesKit

// The same binary is the PreToolUse hook of guarded agent tools, so the guard needs no Bun.
if CommandLine.arguments.contains(ToolGuard.flag) {
    let verdict = ToolGuard.run(stdin: FileHandle.standardInput.readDataToEndOfFile(), environment: ProcessInfo.processInfo.environment)
    if let message = verdict.message { FileHandle.standardError.write(Data((message + "\n").utf8)) }
    exit(verdict.code)
}

// `Routines --perform <plugin> <action> [text]` asks the running app for a menu action and prints its answer.
if let index = CommandLine.arguments.firstIndex(of: ExternalAction.flag) {
    exit(PerformClient.run(Array(CommandLine.arguments[(index + 1)...])))
}

// A child that exits before it reads its stdin must fail its write, not kill the app.
signal(SIGPIPE, SIG_IGN)

RoutinesApp.main()
