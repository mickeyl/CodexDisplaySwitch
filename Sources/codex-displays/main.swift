import AppKit
import ArgumentParser
import Darwin
import DisplayPower
import Foundation

@main
struct CodexDisplays: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "codex-displays",
        abstract: "Control external DDC monitors while keeping macOS awake.",
        version: "0.1.0",
        subcommands: [Off.self, On.self, Status.self]
    )

    struct Off: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Ask the running menu bar app to turn displays off.")

        mutating func run() throws {
            guard let app = runningApp() else {
                throw ValidationError("Open Codex Display Switch first, so a key press can wake the displays.")
            }
            guard kill(app.processIdentifier, SIGUSR1) == 0 else {
                throw ValidationError("Could not reach the menu bar app. Try opening it again.")
            }
            print("Turning displays off.")
        }
    }

    struct On: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Turn displays on; also works when the app has stopped.")

        @Flag(help: "Send DDC wake commands directly, even if the menu bar app is running.")
        var direct = false

        mutating func run() throws {
            if !direct, let app = runningApp(), kill(app.processIdentifier, SIGUSR2) == 0 {
                print("Turning displays on.")
                return
            }
            let result = DisplayPower.turnOn()
            guard result.succeeded else {
                for message in result.failures { fputs("codex-displays: \(message)\n", stderr) }
                throw ExitCode.failure
            }
            print("Turned on \(result.attempted) display(s).")
        }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Read the current DDC power state of external displays.")

        mutating func run() throws {
            let statuses = DisplayPower.statuses()
            guard !statuses.isEmpty else {
                throw ValidationError("No external DDC displays found.")
            }
            for display in statuses {
                print("\(display.state.rawValue)\t\(display.name)")
            }
        }
    }

}

private func runningApp() -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.mickeyl.CodexDisplaySwitch").first
}
