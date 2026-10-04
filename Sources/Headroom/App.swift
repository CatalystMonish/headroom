import SwiftUI

@main
struct HeadroomApp: App {
	@NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

	// the menubar item is AppKit (see StatusItemController); no windows here
	var body: some Scene {
		Settings { EmptyView() }
	}
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
	private var usage: UsageStore?
	private var statusItem: StatusItemController?

	func applicationDidFinishLaunching(_ notification: Notification) {
		// menubar-only agent app: no Dock icon
		NSApp.setActivationPolicy(.accessory)
		let usage = UsageStore()
		statusItem = StatusItemController(usage: usage)
		usage.start()
		self.usage = usage
	}
}
