import AppKit

// Plain AppKit entry point. The UI is a menubar item + popover only; a SwiftUI
// `App` would need a scene, and recent macOS opens even an empty Settings
// scene as a blank window at launch.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
	private var usage: UsageStore?
	private var statusItem: StatusItemController?

	func applicationDidFinishLaunching(_ notification: Notification) {
		let usage = UsageStore()
		statusItem = StatusItemController(usage: usage)
		usage.start()
		self.usage = usage
	}
}

MainActor.assumeIsolated {
	let app = NSApplication.shared
	let delegate = AppDelegate()
	app.delegate = delegate
	app.setActivationPolicy(.accessory) // menubar-only agent app: no Dock icon
	withExtendedLifetime(delegate) { app.run() }
}
