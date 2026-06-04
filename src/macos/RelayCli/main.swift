import Foundation

// Native Swift entry point for the `relay` command-line target. All behavior
// lives in the UI-free RelayCore dispatcher so it stays testable; this file only
// adapts argv and process exit to that dispatcher.

let result = runRelayCli(Array(CommandLine.arguments.dropFirst()))

if !result.stdout.isEmpty {
    print(result.stdout)
}

if !result.stderr.isEmpty {
    FileHandle.standardError.write(Data((result.stderr + "\n").utf8))
}

exit(result.exitCode)
