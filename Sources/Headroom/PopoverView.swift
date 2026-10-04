import ServiceManagement
import SwiftUI

// The popup: every usage stat as a colored meter (checkbox = pin it to the
// menubar), the menubar style, the account, launch at login, quit.
struct PopoverView: View {
	@EnvironmentObject var usage: UsageStore
	@State private var showAccount = false
	@State private var launchAtLogin = SMAppService.mainApp.status == .enabled

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack(spacing: 8) {
				Image(nsImage: Logo.image(size: 18, template: false))
				Text("Headroom").font(.headline)
				Spacer()
				status
				Button { usage.refresh() } label: { Image(systemName: "arrow.clockwise") }
					.buttonStyle(.borderless)
					.disabled(usage.loading)
					.help("Refresh now")
			}

			if usage.stats.isEmpty {
				Text(emptyMessage).font(.caption).foregroundStyle(.secondary)
			} else {
				// re-render so reset countdowns stay current between fetches
				TimelineView(.periodic(from: .now, by: 30)) { _ in
					VStack(spacing: 6) {
						ForEach(usage.stats) { stat in
							StatRow(stat: stat, pinned: Binding(
								get: { usage.isPinned(stat.id) },
								set: { usage.setPinned(stat.id, $0) }
							), timeLeft: Binding(
								get: { usage.showsTimeLeft(stat.id) },
								set: { usage.setShowsTimeLeft(stat.id, $0) }
							))
						}
					}
				}
				if let shares = breakdownText {
					Text(shares).font(.caption2).foregroundStyle(.secondary)
				}
				Text("Tick a stat to show it in the menu bar. The clock shows its time left instead of its name.")
					.font(.caption2).foregroundStyle(.tertiary)
					.fixedSize(horizontal: false, vertical: true)
			}

			VStack(alignment: .leading, spacing: 4) {
				Text("Menu bar style").font(.caption).foregroundStyle(.secondary)
				Picker("Menu bar style", selection: $usage.barStyle) {
					ForEach(BarStyle.allCases) { Text($0.title).tag($0) }
				}
				.pickerStyle(.segmented)
				.labelsHidden()
				.controlSize(.small)
			}

			Divider()

			DisclosureGroup("Account", isExpanded: $showAccount) {
				AccountView().padding(.top, 6)
			}
			.font(.caption)

			Divider()

			HStack {
				Toggle("Launch at login", isOn: $launchAtLogin)
					.toggleStyle(.switch).controlSize(.small).fixedSize()
					.onChange(of: launchAtLogin) { _, on in
						do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {}
						launchAtLogin = SMAppService.mainApp.status == .enabled
					}
				Spacer()
				Button("Quit") { NSApplication.shared.terminate(nil) }
			}
			Text("Unofficial. Not affiliated with or endorsed by Anthropic.")
				.font(.caption2).foregroundStyle(.tertiary)
		}
		.padding(16)
		.frame(width: 320)
		.onAppear { if usage.error == .noToken || usage.error == .reauth { showAccount = true } }
	}

	@ViewBuilder private var status: some View {
		if let e = usage.error {
			Text(usage.isStale ? "stale · \(e.label)" : e.label)
				.font(.caption2).foregroundStyle(usage.isStale ? .orange : .red)
		} else if let t = usage.lastUpdated {
			Text("updated \(t, style: .relative) ago").font(.caption2).foregroundStyle(.secondary)
		}
	}

	private var emptyMessage: String {
		switch usage.error {
		case .noToken: "No token. Sign in to Claude Code, or paste a token under Account."
		case .reauth: "Token expired. Sign in to Claude Code again, or paste a fresh token."
		case .some(let e): "Couldn't load usage (\(e.label))."
		case nil: "Loading…"
		}
	}

	private var breakdownText: String? {
		let rows = (usage.snapshot?.breakdown ?? []).filter { $0.percent > 0 }
		guard !rows.isEmpty else { return nil }
		return "This week: " + rows.map { "\($0.name) \(Int($0.percent.rounded()))%" }.joined(separator: " · ")
	}
}

private struct AccountView: View {
	@EnvironmentObject var usage: UsageStore
	@State private var useClaudeCode = TokenStore.useClaudeCode
	@State private var token = TokenStore.pasted() ?? ""

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Toggle("Use Claude Code's login (from the Keychain)", isOn: $useClaudeCode)
				.toggleStyle(.checkbox)
			SecureField("…or paste an OAuth token (sk-ant-oat01-…)", text: $token)
			HStack {
				Text("A pasted token is stored in your Keychain.").font(.caption2).foregroundStyle(.secondary)
				Spacer()
				Button("Save") {
					TokenStore.useClaudeCode = useClaudeCode
					TokenStore.setPasted(token)
					usage.refresh()
				}
				.controlSize(.small)
				.keyboardShortcut(.defaultAction)
			}
		}
	}
}

private struct StatRow: View {
	let stat: UsageStat
	@Binding var pinned: Bool
	@Binding var timeLeft: Bool

	var body: some View {
		HStack(spacing: 8) {
			Toggle("Show in menu bar", isOn: $pinned)
				.toggleStyle(.checkbox)
				.labelsHidden()
				.help("Show in menu bar")
			// menubar label: time left (on) or the stat's name (off)
			Button { timeLeft.toggle() } label: {
				Image(systemName: timeLeft && stat.resetsAt != nil ? "clock.fill" : "clock")
			}
			.buttonStyle(.borderless)
			.foregroundStyle(timeLeft && stat.resetsAt != nil ? .primary : .tertiary)
			.disabled(stat.resetsAt == nil)
			.help(timeLeft ? "Menu bar shows the time left. Click to show the name instead." : "Menu bar shows the name. Click to show the time left instead.")
			Text(stat.label).font(.caption).lineLimit(1).frame(width: 78, alignment: .leading)
			Meter(percent: stat.percent, color: stat.dimmed ? .secondary : Color(nsColor: ClaudeUsage.severityColor(stat.percent)))
			Text(stat.value).font(.caption.monospacedDigit()).bold()
				.foregroundStyle(stat.dimmed ? .secondary : .primary)
				.frame(minWidth: 34, alignment: .trailing)
			Text(ClaudeUsage.formatReset(stat.resetsAt)).font(.caption2).foregroundStyle(.secondary)
				.frame(width: 44, alignment: .trailing)
		}
	}
}

private struct Meter: View {
	let percent: Double
	let color: Color

	var body: some View {
		GeometryReader { g in
			ZStack(alignment: .leading) {
				Capsule().fill(Color.primary.opacity(0.12))
				Capsule().fill(color).frame(width: g.size.width * min(max(percent, 0), 100) / 100)
			}
		}
		.frame(height: 6)
	}
}
