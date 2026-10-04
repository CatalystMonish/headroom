// Renders the real menubar item (every style, light + dark) and the popup
// offscreen at 2x, with the sample payload. Run via scripts/screens.sh.
import AppKit
import SwiftUI

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let out = CommandLine.arguments[1]
var snap = try! ClaudeUsage.parse(Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
// demo values that show all three severities
let now = Date()
snap.stats[0] = UsageStat(id: "session", label: "Session (5h)", short: "5h", percent: 42, value: "42%", resetsAt: now.addingTimeInterval(3*3600+12*60))
snap.stats[1] = UsageStat(id: "weekly", label: "Weekly (7d)", short: "7d", percent: 74, value: "74%", resetsAt: now.addingTimeInterval(2*86400+5*3600))
snap.stats[2] = UsageStat(id: "model:fable", label: "Fable weekly", short: "Fable", percent: 93, value: "93%", resetsAt: now.addingTimeInterval(2*86400+5*3600))

func png(_ v: NSView, _ name: String, scale: CGFloat = 2) {
	let size = v.bounds.size
	let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
	rep.size = size
	v.cacheDisplay(in: v.bounds, to: rep)
	try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name)"))
}

MainActor.assumeIsolated {
	let pins = ["session", "weekly", "model:fable"]
	for (mode, name) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
		let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
		let b = item.button!
		b.appearance = NSAppearance(named: mode)
		var cases: [(String, [UsageStat], BarStyle)] = [("logo", [], .meterText)]
		for s in BarStyle.allCases { cases.append((s.rawValue, snap.stats.filter { pins.contains($0.id) }, s)) }
		for (label, stats, style) in cases {
			for _ in 0..<2 { // first pass warms up the button
				MenuBarRenderer.apply(to: b, stats: stats, style: style, warn: false, tooltip: "")
				b.sizeToFit(); b.layoutSubtreeIfNeeded()
				RunLoop.main.run(until: Date().addingTimeInterval(0.05))
			}
			png(b, "bar-\(name)-\(label).png")
		}
		NSStatusBar.system.removeStatusItem(item)

		let usage = UsageStore()
		usage.snapshot = snap; usage.lastUpdated = Date().addingTimeInterval(-12)
		usage.pinned = pins; usage.barStyle = .dial
		let host = NSHostingView(rootView: PopoverView().environmentObject(usage))
		host.appearance = NSAppearance(named: mode)
		let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
		w.appearance = NSAppearance(named: mode)
		w.contentView = host
		host.frame.size = host.fittingSize
		RunLoop.main.run(until: Date().addingTimeInterval(0.3))
		png(host, "popup-\(name).png")
	}
}
print("done")
