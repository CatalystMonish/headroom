import AppKit

// The menubar/app logo, inlined from assets/logo.svg (NSImage renders SVG
// natively on macOS 14+), so the app needs no resource bundle.
enum Logo {
	static let svg = ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><g fill="none" stroke="#D97757" stroke-linecap="round"><path d="M23.13 82.87A38 38 0 1 1 76.87 82.87" stroke-width="12"/><path d="M50 56L66.7 36.1" stroke-width="9"/></g><circle cx="50" cy="56" r="8.5" fill="#D97757"/></svg>"##

	static func image(size: CGFloat, template: Bool) -> NSImage {
		let img = NSImage(data: Data(svg.utf8)) ?? NSImage(systemSymbolName: "asterisk", accessibilityDescription: nil)!
		img.size = NSSize(width: size, height: size)
		img.isTemplate = template
		img.accessibilityDescription = "Headroom"
		return img
	}
}
