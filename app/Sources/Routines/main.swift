import AppKit
import Foundation
import RoutinesKit

// The same binary is the PreToolUse hook of guarded agent tools, so the guard needs no Bun.
if CommandLine.arguments.contains(ToolGuard.flag) {
    let verdict = ToolGuard.run(stdin: FileHandle.standardInput.readDataToEndOfFile(), environment: ProcessInfo.processInfo.environment)
    if let message = verdict.message { FileHandle.standardError.write(Data((message + "\n").utf8)) }
    exit(verdict.code)
}

// `Routines --memory-mcp --routine <id>` is the read-only memory search server of an agent node.
if let index = CommandLine.arguments.firstIndex(of: MemoryServer.flag) {
    let rest = CommandLine.arguments[(index + 1)...]
    guard let flag = rest.firstIndex(of: "--routine"), flag + 1 < CommandLine.arguments.count else {
        FileHandle.standardError.write(Data("usage: Routines --memory-mcp --routine <id>\n".utf8))
        exit(64)
    }
    MemoryServer.serve(routine: CommandLine.arguments[flag + 1], entries: HostPaths.standard().file("memory/entries.json"))
    exit(0)
}

// `Routines --perform <routine> <transition-or-action> [--item <id>] [text]` asks the running app and prints its answer.
if let index = CommandLine.arguments.firstIndex(of: ExternalAction.flag) {
    exit(PerformClient.run(Array(CommandLine.arguments[(index + 1)...])))
}

// A child that exits before it reads its stdin must fail its write, not kill the app.
signal(SIGPIPE, SIG_IGN)

RoutinesApp.main()
