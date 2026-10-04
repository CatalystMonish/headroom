import AppKit

// Draws the status item. With nothing pinned it's the logo; once any stat is
// pinned, the stats replace the icon, in the chosen style. Colored styles use
// non-template content, so neutral parts use plain colors picked for the
// menubar's light/dark appearance (see Ink).
@MainActor
enum MenuBarRenderer {
	// Text / Color styles use the same 11pt size as the Meter+% values
	private static let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
	private static let boldFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

	// Neutral colors for the drawn (non-template) styles. Semantic colors like
	// secondaryLabelColor resolve to vibrancy-blend values in the live menubar and
	// come out dark in a plain image, so pick plain colors for its light/dark.
	private struct Ink {
		let primary: NSColor, secondary: NSColor, track: NSColor
		init(_ appearance: NSAppearance) {
			let dark = [.darkAqua, .vibrantDark].contains(appearance.bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark]))
			let base: NSColor = dark ? .white : .black
			primary = base.withAlphaComponent(dark ? 1 : 0.85)
			secondary = base.withAlphaComponent(dark ? 0.6 : 0.5)
			track = base.withAlphaComponent(dark ? 0.25 : 0.2)
		}
	}

	// The logo, as a template image so the menubar tints it.
	private static let icon = Logo.image(size: 16, template: true)

	static func apply(to button: NSStatusBarButton, stats: [UsageStat], style: BarStyle, tooltip: String) {
		button.toolTip = tooltip

		if stats.isEmpty {
			button.image = icon
			button.imagePosition = .imageOnly
			button.attributedTitle = NSAttributedString()
			return
		}
		switch style {
		case .text:
			button.image = nil
			button.imagePosition = .noImage
			button.font = font
			button.title = stats.map(\.barText).joined(separator: " · ")
		case .coloredText:
			button.image = nil
			button.imagePosition = .noImage
			button.attributedTitle = coloredTitle(stats)
		case .meter, .meterText:
			button.attributedTitle = NSAttributedString()
			button.image = meterImage(stats, showValue: style == .meterText,
			                          appearance: button.effectiveAppearance, description: tooltip)
			button.imagePosition = .imageOnly
		case .dial:
			button.attributedTitle = NSAttributedString()
			button.image = dialImage(stats, appearance: button.effectiveAppearance, description: tooltip)
			button.imagePosition = .imageOnly
		}
	}

	// One speedometer per stat: a 270° arc in the severity color with a needle,
	// then the label over the value.
	private static func dialImage(_ stats: [UsageStat],
	                              appearance: NSAppearance, description: String) -> NSImage {
		let labelFont = NSFont.systemFont(ofSize: 8, weight: .semibold)
		let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
		let h: CGFloat = 18, d: CGFloat = 17, gap: CGFloat = 8, line: CGFloat = 2.2

		struct Cell { let stat: UsageStat; let x: CGFloat; let textW: CGFloat }
		var cells: [Cell] = []
		var x: CGFloat = 0
		for st in stats {
			let lw = (st.short as NSString).size(withAttributes: [.font: labelFont]).width
			let vw = (st.value as NSString).size(withAttributes: [.font: valueFont]).width
			let tw = ceil(max(lw, vw))
			cells.append(Cell(stat: st, x: x, textW: tw))
			x += d + 3 + tw + gap
		}
		let width = x - gap

		let ink = Ink(appearance)
		let img = NSImage(size: NSSize(width: ceil(width), height: h), flipped: false) { _ in
			appearance.performAsCurrentDrawingAppearance {
				for c in cells {
					let center = NSPoint(x: c.x + d / 2, y: h / 2 - 0.5)
					let r = d / 2 - line / 2
					// the dial runs clockwise from bottom-left (225°) to bottom-right (-45°)
					let start: CGFloat = 225, end = start - 270 * CGFloat(c.stat.percent) / 100
					let track = NSBezierPath()
					track.appendArc(withCenter: center, radius: r, startAngle: start, endAngle: -45, clockwise: true)
					track.lineWidth = line
					track.lineCapStyle = .round
					ink.track.setStroke()
					track.stroke()
					if c.stat.percent > 0 {
						let arc = NSBezierPath()
						arc.appendArc(withCenter: center, radius: r, startAngle: start, endAngle: end, clockwise: true)
						arc.lineWidth = line
						arc.lineCapStyle = .round
						valueColor(c.stat, dimmed: ink.secondary).setStroke()
						arc.stroke()
					}
					// needle + hub
					let a = end * .pi / 180, len = r - line - 0.5
					let needle = NSBezierPath()
					needle.move(to: center)
					needle.line(to: NSPoint(x: center.x + cos(a) * len, y: center.y + sin(a) * len))
					needle.lineWidth = 1.3
					needle.lineCapStyle = .round
					ink.primary.setStroke()
					needle.stroke()
					ink.primary.setFill()
					NSBezierPath(ovalIn: NSRect(x: center.x - 1.4, y: center.y - 1.4, width: 2.8, height: 2.8)).fill()

					let tx = c.x + d + 3
					let label = NSAttributedString(string: c.stat.short, attributes: [.font: labelFont, .foregroundColor: ink.secondary])
					label.draw(at: NSPoint(x: tx, y: h - label.size().height + 1))
					let value = NSAttributedString(string: c.stat.value, attributes: [.font: valueFont, .foregroundColor: ink.primary])
					value.draw(at: NSPoint(x: tx, y: -1))
				}
			}
			return true
		}
		img.isTemplate = false
		img.accessibilityDescription = description
		return img
	}

	private static func valueColor(_ s: UsageStat, dimmed: NSColor = .secondaryLabelColor) -> NSColor {
		s.dimmed ? dimmed : ClaudeUsage.severityColor(s.percent)
	}

	// "5h 0% · 7d 60%" with each value in its severity color
	private static func coloredTitle(_ stats: [UsageStat]) -> NSAttributedString {
		let s = NSMutableAttributedString()
		for (i, st) in stats.enumerated() {
			if i > 0 { s.append(NSAttributedString(string: " · ", attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])) }
			s.append(NSAttributedString(string: st.short + " ", attributes: [.font: font, .foregroundColor: NSColor.labelColor]))
			s.append(NSAttributedString(string: st.value, attributes: [.font: boldFont, .foregroundColor: valueColor(st)]))
		}
		return s
	}

	// One mini meter per stat: tiny label over a colored bar, optionally
	// followed by the value.
	private static func meterImage(_ stats: [UsageStat], showValue: Bool,
	                               appearance: NSAppearance, description: String) -> NSImage {
		let labelFont = NSFont.systemFont(ofSize: 8, weight: .semibold)
		let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
		let h: CGFloat = 18, barW: CGFloat = 22, barH: CGFloat = 4, gap: CGFloat = 7

		struct Cell { let stat: UsageStat; let x: CGFloat; let w: CGFloat }
		var cells: [Cell] = []
		var x: CGFloat = 0
		for st in stats {
			let lw = ceil((st.short as NSString).size(withAttributes: [.font: labelFont]).width)
			let w = max(barW, lw)
			cells.append(Cell(stat: st, x: x, w: w))
			let vw = showValue ? ceil((st.value as NSString).size(withAttributes: [.font: valueFont]).width) + 3 : 0
			x += w + vw + gap
		}
		let width = x - gap

		let ink = Ink(appearance)
		let img = NSImage(size: NSSize(width: ceil(width), height: h), flipped: false) { _ in
			appearance.performAsCurrentDrawingAppearance {
				for c in cells {
					let label = NSAttributedString(string: c.stat.short, attributes: [.font: labelFont, .foregroundColor: ink.primary])
					let ls = label.size()
					label.draw(at: NSPoint(x: c.x + (c.w - ls.width) / 2, y: h - ls.height + 1))

					let track = NSRect(x: c.x, y: 2, width: c.w, height: barH)
					ink.track.setFill()
					NSBezierPath(roundedRect: track, xRadius: barH / 2, yRadius: barH / 2).fill()
					if c.stat.percent > 0 {
						var fill = track
						fill.size.width = max(barH, c.w * c.stat.percent / 100)
						valueColor(c.stat, dimmed: ink.secondary).setFill()
						NSBezierPath(roundedRect: fill, xRadius: barH / 2, yRadius: barH / 2).fill()
					}
					if showValue {
						let v = NSAttributedString(string: c.stat.value, attributes: [.font: valueFont, .foregroundColor: ink.primary])
						v.draw(at: NSPoint(x: c.x + c.w + 3, y: (h - v.size().height) / 2))
					}
				}
			}
			return true
		}
		img.isTemplate = false
		img.accessibilityDescription = description
		return img
	}
}
