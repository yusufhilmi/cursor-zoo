import AppKit

let app = NSApplication.shared

if let index = CommandLine.arguments.firstIndex(of: "--trackstest") {
    let output = CommandLine.arguments.count > index + 1 ? CommandLine.arguments[index + 1] : "tracks.png"
    app.setActivationPolicy(.prohibited)
    exit(SelfTest.runTracks(outputPath: output))
}

if let index = CommandLine.arguments.firstIndex(of: "--selftest") {
    let output = CommandLine.arguments.count > index + 1 ? CommandLine.arguments[index + 1] : "selftest.png"
    app.setActivationPolicy(.prohibited)
    exit(SelfTest.run(outputPath: output))
}

let delegate = AppDelegate()
app.delegate = delegate
// Menu-bar only: no Dock icon, no main menu, never steals focus.
app.setActivationPolicy(.accessory)
app.run()
