import SwiftUI
import AppKit
import CleanerEngine

// MARK: - Pressure

extension MemoryPressure {
    /// Pill text beside "Memory".
    var label: String {
        switch self {
        case .normal: return L10n.t("memory.pressure.normal", "Normal")
        case .warning: return L10n.t("memory.pressure.warning", "Elevated")
        case .critical: return L10n.t("memory.pressure.critical", "High")
        }
    }

    /// The same, as a sentence for places without the "Memory" heading.
    var sentence: String {
        switch self {
        case .normal: return L10n.t("memory.pressure.normalSentence", "Pressure is normal")
        case .warning: return L10n.t("memory.pressure.warningSentence", "Pressure is elevated")
        case .critical: return L10n.t("memory.pressure.criticalSentence", "Pressure is high")
        }
    }

    var tint: Color {
        switch self {
        case .normal: return DustyTheme.success
        case .warning: return DustyTheme.warn
        case .critical: return DustyTheme.danger
        }
    }
}

extension MemorySnapshot {
    /// App, wired, compressed, and cached memory as bar slices; the empty
    /// track after them is memory holding nothing at all.
    var barSegments: [CapacityBar.Segment] {
        guard totalBytes > 0 else { return [] }
        let share = { (bytes: Int64) in Double(bytes) / Double(totalBytes) }
        return [
            CapacityBar.Segment(id: "app", fraction: share(appBytes), color: DustyTheme.memory),
            CapacityBar.Segment(id: "wired", fraction: share(wiredBytes), color: DustyTheme.usedSpace),
            CapacityBar.Segment(id: "compressed", fraction: share(compressedBytes), color: DustyTheme.memoryCompressed),
            CapacityBar.Segment(id: "cached", fraction: share(cachedFilesBytes), color: DustyTheme.memory.opacity(0.3)),
        ]
    }
}

/// Wording shared by the memory views.
enum MemoryText {
    /// "2 hours", "45 minutes": how long, rounded to one unit.
    static func duration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        formatter.allowedUnits = seconds >= 86400 ? [.day, .hour] : (seconds >= 3600 ? [.hour, .minute] : [.minute])
        return formatter.string(from: max(60, seconds)) ?? ""
    }

    /// "Slack, Figma, and 2 more": at most three names, then a count.
    static func names(_ names: [String]) -> String {
        guard names.count > 3 else { return names.formatted(.list(type: .and)) }
        let shown = Array(names.prefix(2)) + [L10n.f("memory.names.more", "%d more", names.count - 2)]
        return shown.formatted(.list(type: .and))
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }
}

// MARK: - Home card

/// Memory on the home screen: how much is in use, how hard macOS is working
/// for it, and whether idle apps are sitting on a lot of it. The whole card
/// opens the memory screen.
struct MemoryCard: View {
    @ObservedObject var memory: MemoryModel
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(
                title: L10n.t("memory.title", "Memory"),
                detail: memory.snapshot.map { L10n.f("memory.card.total", "%@ RAM", Bytes.memory($0.totalBytes)) }
            )
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        IconTile(symbol: "memorychip", tint: DustyTheme.memory, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(headline)
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                                .lineLimit(1)
                            detail
                        }
                        Spacer(minLength: 8)
                        if let snapshot = memory.snapshot {
                            UsageRing(fraction: snapshot.usedFraction, tint: snapshot.pressure.tint)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DustyTheme.faint)
                    }
                    if let snapshot = memory.snapshot {
                        CapacityBar(segments: snapshot.barSegments, height: 6)
                            .padding(.leading, 42)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.leading, 13)
                .padding(.trailing, 14)
                .padding(.vertical, 11)
            }
            .buttonStyle(DustyRowButtonStyle())
            .clipShape(RoundedRectangle(cornerRadius: DustyTheme.cardRadius, style: .continuous))
            .dustyCard()
            .accessibilityElement(children: .combine)
            .accessibilityHint(L10n.t("memory.card.hint", "Shows the apps using the most memory"))
        }
    }

    private var headline: String {
        guard let snapshot = memory.snapshot else { return L10n.t("memory.reading", "Reading memory…") }
        return L10n.f("memory.card.inUse", "%1$@ of %2$@ in use",
                      Bytes.memory(snapshot.usedBytes), Bytes.memory(snapshot.totalBytes))
    }

    @ViewBuilder private var detail: some View {
        if memory.suggestedBytes > 0 {
            Text(L10n.f("memory.card.idle", "%@ held by apps you are not using", Bytes.memory(memory.suggestedBytes)))
                .font(.caption.weight(.semibold))
                .foregroundStyle(DustyTheme.memory)
                .lineLimit(1)
        } else if let snapshot = memory.snapshot {
            Text(snapshot.swapUsedBytes >= 512 * 1_048_576
                 ? L10n.f("memory.card.withSwap", "%1$@ · %2$@ swap", snapshot.pressure.sentence,
                          Bytes.memory(snapshot.swapUsedBytes))
                 : snapshot.pressure.sentence)
                .font(.caption)
                .foregroundStyle(snapshot.pressure == .normal ? Color.secondary : snapshot.pressure.tint)
                .lineLimit(1)
        }
    }
}

/// Memory in use as a small pill for the home screen's top bar, so memory is
/// one click away without scrolling. Tinted once pressure rises, and dotted
/// when idle apps are sitting on memory.
struct MemoryPill: View {
    @ObservedObject var memory: MemoryModel
    let onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        if let snapshot = memory.snapshot {
            let tint: Color = snapshot.pressure == .normal ? .secondary : snapshot.pressure.tint
            let percent = MemoryText.percent(snapshot.usedFraction)
            Button(action: onOpen) {
                HStack(spacing: 4) {
                    Image(systemName: "memorychip")
                        .font(.system(size: 11, weight: .semibold))
                    Text(percent)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .foregroundStyle(hovering ? Color.primary : tint)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(
                    Capsule().fill(snapshot.pressure == .normal
                                   ? (hovering ? DustyTheme.insetHover : DustyTheme.inset)
                                   : snapshot.pressure.tint.opacity(hovering ? 0.2 : 0.13))
                )
                .overlay(alignment: .topTrailing) {
                    if memory.suggestedBytes > 0 {
                        Circle()
                            .fill(DustyTheme.memory)
                            .frame(width: 7, height: 7)
                            .offset(x: 1, y: -1)
                    }
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .help(L10n.f("memory.pill.help", "Memory: %@ in use", percent))
            .accessibilityLabel(L10n.t("memory.title", "Memory"))
            .accessibilityValue(L10n.f("memory.pill.help", "Memory: %@ in use", percent))
        }
    }
}

/// A small ring with the share of memory in use.
private struct UsageRing: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(DustyTheme.inset, lineWidth: 3.5)
            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0, fraction))))
                .stroke(tint, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(MemoryText.percent(fraction))
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 3)
        }
        .frame(width: 34, height: 34)
        .animation(DustyTheme.revealSpring, value: fraction)
        .accessibilityHidden(true)
    }
}

// MARK: - Screen

/// Memory, app by app: what is in use, what macOS thinks of it, and the apps
/// holding the most, with the idle ones already ticked. Quitting always goes
/// through a confirmation, uses the app's own Quit, and can be undone by
/// reopening from the receipt.
struct MemoryView: View {
    @ObservedObject var memory: MemoryModel
    @ObservedObject var viewModel: DustyViewModel
    @ObservedObject var settings: AppSettings
    @State private var showsAll = false

    /// Apps listed before "Show all".
    private static let collapsedCount = 8

    private var visibleApps: [RunningAppMemory] {
        showsAll ? memory.apps : Array(memory.apps.prefix(Self.collapsedCount))
    }

    var body: some View {
        VStack(spacing: 0) {
            NavHeader(title: L10n.t("memory.title", "Memory"), subtitle: subtitle, onBack: { viewModel.goHome() }) {
                if !memory.apps.isEmpty {
                    selectAllButton
                }
            }
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    MemoryHeroCard(memory: memory, settings: settings)
                    if let error = memory.errorMessage {
                        InlineBanner(
                            symbol: "exclamationmark.circle.fill",
                            tint: DustyTheme.danger,
                            title: error,
                            onDismiss: { memory.errorMessage = nil }
                        )
                    }
                    appsSection
                    if !memory.backgroundProcesses.isEmpty {
                        backgroundSection
                    }
                    Text(L10n.t("memory.footnote",
                                "Dusty quits apps the way ⌘Q does and never force quits. It doesn’t run purge either: macOS already hands cached memory back the moment an app needs it."))
                        .font(.caption)
                        .foregroundStyle(DustyTheme.faint)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, DustyTheme.gutter)
                .padding(.vertical, 14)
                // Leave room for the receipt so it never hides the last row.
                .padding(.bottom, memory.receipt == nil ? 0 : 64)
                .animation(DustyTheme.revealSpring, value: memory.errorMessage)
            }
            .scrollIndicators(.never)
            bottomBar
        }
        .onAppear { memory.setLive(true) }
        .onDisappear { memory.setLive(false) }
    }

    private var subtitle: String {
        guard let snapshot = memory.snapshot else { return L10n.t("memory.reading", "Reading memory…") }
        return L10n.f("memory.subtitle", "%@ of RAM · updates live", Bytes.memory(snapshot.totalBytes))
    }

    private var selectAllButton: some View {
        let allSelected = memory.selection.count == memory.apps.count
        return Button(allSelected ? L10n.t("level.selectNone", "Select None") : L10n.t("level.selectAll", "Select All")) {
            withAnimation(.easeOut(duration: 0.15)) { memory.setAllSelected(!allSelected) }
        }
        .buttonStyle(DustySecondaryButtonStyle())
        .font(.caption.weight(.semibold))
    }

    // MARK: Apps

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(
                title: L10n.t("memory.apps", "Apps"),
                detail: memory.apps.isEmpty ? nil : Bytes.memory(memory.totalAppBytes)
            )
            if !memory.hasLoadedApps {
                HStack(spacing: 8) {
                    Spinner(tint: DustyTheme.memory, size: 13)
                    Text(L10n.t("memory.apps.loading", "Measuring apps…"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .dustyCard()
            } else if memory.apps.isEmpty {
                Text(L10n.t("memory.apps.none", "No apps are open."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                    .dustyCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visibleApps.enumerated()), id: \.element.id) { index, app in
                        AppMemoryRow(
                            app: app,
                            isSelected: memory.selection.contains(app.id),
                            isSuggested: memory.suggestedIDs.contains(app.id),
                            growth: memory.growth[app.id],
                            isQuitting: memory.quittingIDs.contains(app.id),
                            onToggle: { memory.toggle(app.id) },
                            onQuit: { memory.requestQuit([app.id]) },
                            onRelaunch: { Task { await memory.relaunch(app) } }
                        )
                        if index < visibleApps.count - 1 {
                            Hairline(leading: 70)
                        }
                    }
                    if memory.apps.count > Self.collapsedCount {
                        Hairline()
                        Button {
                            withAnimation(DustyTheme.revealSpring) { showsAll.toggle() }
                        } label: {
                            Text(showsAll
                                 ? L10n.t("memory.apps.showFewer", "Show fewer")
                                 : L10n.f("memory.apps.showAll", "Show all %d apps", memory.apps.count))
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                        }
                        .buttonStyle(DustyLinkButtonStyle())
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: DustyTheme.cardRadius, style: .continuous))
                .dustyCard()
            }
        }
    }

    // MARK: Other processes

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: L10n.t("memory.background", "Other processes"))
            VStack(spacing: 0) {
                ForEach(Array(memory.backgroundProcesses.enumerated()), id: \.element.id) { index, process in
                    HStack(spacing: 11) {
                        IconTile(symbol: "terminal", tint: DustyTheme.usedSpace, size: 26, style: .soft)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(process.name)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text((process.id as NSString).abbreviatingWithTildeInPath)
                                .font(.caption)
                                .foregroundStyle(DustyTheme.faint)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                        Text(Bytes.memory(process.footprintBytes))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .help(process.id)
                    .accessibilityElement(children: .combine)
                    if index < memory.backgroundProcesses.count - 1 {
                        Hairline(leading: 49)
                    }
                }
            }
            .dustyCard()
            Text(L10n.t("memory.background.note",
                        "These are not apps, so Dusty leaves them alone. Stop them where you started them."))
                .font(.caption)
                .foregroundStyle(DustyTheme.faint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        let bytes = memory.selectedBytes
        let count = memory.selectedApps.count
        return VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(bytes > 0
                         ? L10n.f("level.bar.selected", "%@ selected", Bytes.memory(bytes))
                         : L10n.t("level.bar.nothing", "Nothing selected"))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                    Text(count > 0
                         ? L10n.f("memory.bar.apps", "%d apps, each can ask to save first", count)
                         : L10n.t("memory.bar.pick", "Tick the apps you want to quit"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                Button {
                    memory.requestQuit()
                } label: {
                    HStack(spacing: 6) {
                        if memory.isQuitting {
                            Spinner(tint: .white, size: 12)
                            Text(L10n.t("memory.quitting", "Quitting…"))
                        } else {
                            Image(systemName: "power")
                            Text(L10n.t("memory.quit", "Quit"))
                        }
                    }
                }
                .buttonStyle(DustyPrimaryButtonStyle(tint: DustyTheme.memorySolid, compact: true))
                .disabled(count == 0 || memory.isQuitting)
                .accessibilityLabel(L10n.t("memory.a11y.quitSelected", "Quit the selected apps"))
            }
            .padding(.horizontal, DustyTheme.gutter)
            .frame(height: 58)
        }
        .background(DustyTheme.canvas)
    }
}

// MARK: - Hero

/// The top of the memory screen: memory in use against the total, split the
/// way Activity Monitor splits it, the last hour at a glance, and the one
/// action worth taking (or the reassurance that there is none).
private struct MemoryHeroCard: View {
    @ObservedObject var memory: MemoryModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            usage
                .padding(16)
            Hairline()
            status
                .padding(16)
        }
        .dustyCard()
    }

    @ViewBuilder private var usage: some View {
        if let snapshot = memory.snapshot {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "memorychip")
                        .font(.system(size: 11, weight: .semibold))
                    Text(L10n.t("memory.hero.label", "Physical memory"))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    StatusPill(text: snapshot.pressure.label, tint: snapshot.pressure.tint)
                        .help(L10n.t("memory.pressure.help",
                                     "Memory pressure: how hard macOS is working to find memory. This, not free memory, says whether the Mac needs more."))
                }
                .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    BigBytes(bytes: snapshot.usedBytes, size: 34, memory: true)
                    Text(L10n.f("memory.hero.usedOf", "used of %@", Bytes.memory(snapshot.totalBytes)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.t("memory.title", "Memory"))
                .accessibilityValue(L10n.f("memory.a11y.value", "%1$@ used of %2$@, %3$@",
                                           Bytes.memory(snapshot.usedBytes), Bytes.memory(snapshot.totalBytes),
                                           snapshot.pressure.sentence))

                CapacityBar(segments: snapshot.barSegments, height: 10)
                    .accessibilityHidden(true)

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        LegendItem(color: DustyTheme.memory, label: L10n.t("memory.legend.apps", "Apps"),
                                   value: Bytes.memory(snapshot.appBytes))
                        LegendItem(color: DustyTheme.memoryCompressed, label: L10n.t("memory.legend.compressed", "Compressed"),
                                   value: Bytes.memory(snapshot.compressedBytes))
                    }
                    GridRow {
                        LegendItem(color: DustyTheme.usedSpace, label: L10n.t("memory.legend.wired", "System"),
                                   value: Bytes.memory(snapshot.wiredBytes))
                            .help(L10n.t("memory.legend.wiredHelp", "Wired memory: held by macOS itself, never swapped out."))
                        LegendItem(color: DustyTheme.memory.opacity(0.3), label: L10n.t("memory.legend.cached", "Cached files"),
                                   value: Bytes.memory(snapshot.cachedFilesBytes))
                            .help(L10n.t("memory.legend.cachedHelp", "Recently used files kept in spare memory. macOS hands it to any app that asks, instantly."))
                    }
                }

                if memory.usageHistory.count >= 2 {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(L10n.t("memory.hero.lastHour", "In use, last hour"))
                            Spacer()
                            if snapshot.swapUsedBytes > 0 {
                                Text(L10n.f("memory.hero.swap", "Swap %@", Bytes.memory(snapshot.swapUsedBytes)))
                                    .monospacedDigit()
                                    .help(L10n.t("memory.hero.swapHelp", "Memory moved to disk to make room. A lot of it, while pressure is up, is when a Mac feels slow."))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(DustyTheme.faint)
                        MemorySparkline(points: memory.usageHistory, now: snapshot.sampledAt, tint: snapshot.pressure.tint)
                            .frame(height: 30)
                            .accessibilityHidden(true)
                    }
                }
            }
        } else {
            HStack(spacing: 8) {
                Spinner(tint: DustyTheme.memory, size: 13)
                Text(L10n.t("memory.reading", "Reading memory…"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var status: some View {
        let suggested = memory.suggestedApps
        if !suggested.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        BigBytes(bytes: memory.suggestedBytes, size: 22, memory: true)
                        Text(L10n.t("memory.hero.idleHeld", "held by idle apps"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(L10n.f("memory.hero.idleNames", "Not used for at least %1$@: %2$@.",
                                MemoryText.duration(TimeInterval(settings.memoryIdleMinutes) * 60),
                                MemoryText.names(suggested.map(\.name))))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                Button {
                    memory.requestQuit(Set(suggested.map(\.id)))
                } label: {
                    HStack(spacing: 7) {
                        if memory.isQuitting {
                            Spinner(tint: .white, size: 13)
                            Text(L10n.t("memory.quitting", "Quitting…"))
                        } else {
                            Image(systemName: "wind")
                            Text(L10n.f("memory.hero.free", "Free up %@", Bytes.memory(memory.suggestedBytes)))
                                .monospacedDigit()
                        }
                    }
                }
                .buttonStyle(DustyPrimaryButtonStyle(tint: DustyTheme.memorySolid))
                .disabled(memory.isQuitting)
            }
        } else if let snapshot = memory.snapshot, snapshot.pressure > .normal {
            verdict(symbol: "exclamationmark", tint: snapshot.pressure.tint,
                    title: L10n.t("memory.hero.tight.title", "Memory is tight"),
                    body: L10n.t("memory.hero.tight.body",
                                 "Quitting an app you are not using gives its memory back right away. Tick one below."))
        } else if memory.snapshot != nil {
            verdict(symbol: "checkmark", tint: DustyTheme.success,
                    title: L10n.t("memory.hero.fine.title", "Memory is in good shape"),
                    body: L10n.t("memory.hero.fine.body",
                                 "macOS keeps spare memory busy caching files and hands it back the moment an app needs it. There is nothing to free up."))
        }
    }

    private func verdict(symbol: String, tint: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(tint.opacity(0.14))
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
    }
}

/// Memory in use over the last hour, as a filled line. The time axis is fixed
/// to the hour, so a freshly started Dusty draws a short line at the right.
private struct MemorySparkline: View {
    let points: [MemoryUsagePoint]
    let now: Date
    let tint: Color
    var span: TimeInterval = 3600

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            // The axis hugs the readings with at least a 30-point span: a climb
            // reads as a climb, and a steady Mac draws a steady line instead of
            // its noise blown up to fill the box.
            let fractions = points.map { min(1, max(0, $0.usedFraction)) }
            let bottom = max(0, (fractions.min() ?? 0) - 0.1)
            let top = min(1, max((fractions.max() ?? 1) + 0.05, bottom + 0.3))
            let plotted = points.map { point -> CGPoint in
                let x = (1 - CGFloat(now.timeIntervalSince(point.date) / span)) * size.width
                let share = (min(top, max(bottom, point.usedFraction)) - bottom) / max(0.05, top - bottom)
                let y = (1 - CGFloat(share)) * (size.height - 2) + 1
                return CGPoint(x: min(size.width, max(0, x)), y: y)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(DustyTheme.inset)
                if let first = plotted.first, let last = plotted.last {
                    Path { path in
                        path.move(to: CGPoint(x: first.x, y: size.height))
                        for point in plotted { path.addLine(to: point) }
                        path.addLine(to: CGPoint(x: last.x, y: size.height))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.04)],
                                         startPoint: .top, endPoint: .bottom))
                    Path { path in
                        path.move(to: first)
                        for point in plotted.dropFirst() { path.addLine(to: point) }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
    }
}

// MARK: - App row

/// One app: a checkbox, its icon and name, what it is doing, and its memory
/// (helpers included). An app that keeps growing gets a Relaunch button.
private struct AppMemoryRow: View {
    let app: RunningAppMemory
    let isSelected: Bool
    let isSuggested: Bool
    let growth: MemoryGrowth?
    let isQuitting: Bool
    let onToggle: () -> Void
    let onQuit: () -> Void
    let onRelaunch: () -> Void

    private var status: (text: String, tint: Color) {
        let base: (text: String, tint: Color)
        if app.isFrontmost {
            base = (L10n.t("memory.row.frontmost", "In use now"), DustyTheme.faint)
        } else if app.isUsingMicrophone {
            base = (L10n.t("memory.row.microphone", "Using the microphone"), .secondary)
        } else if app.isPlayingAudio {
            base = (L10n.t("memory.row.audio", "Playing audio"), .secondary)
        } else if let growth {
            base = (L10n.f("memory.row.grew", "Grew by %1$@ in %2$@", Bytes.memory(growth.grownBytes),
                           MemoryText.duration(Date().timeIntervalSince(growth.since))), DustyTheme.warn)
        } else if isSuggested {
            base = (L10n.f("memory.row.idle", "Not used for %@",
                           MemoryText.duration(Date().timeIntervalSince(app.idleSince))),
                    DustyTheme.memory)
        } else if let last = app.lastActiveAt {
            base = (L10n.f("memory.row.lastUsed", "Last used %@", RelativeTime.label(for: last)), DustyTheme.faint)
        } else {
            base = (L10n.t("memory.row.background", "In the background"), DustyTheme.faint)
        }
        // A growth line is long enough on its own; the Relaunch button sits beside it.
        guard app.processCount > 1, growth == nil || app.isFrontmost || app.isPlayingAudio || app.isUsingMicrophone else {
            return base
        }
        return (text: L10n.f("memory.row.withProcesses", "%1$@ · %2$@", base.text,
                             L10n.f("memory.row.processes", "%d processes", app.processCount)),
                tint: base.tint)
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    DustyCheckbox(state: isSelected ? .on : .off, tint: DustyTheme.memory)
                    icon
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.85))
                            .lineLimit(1)
                        Text(status.text)
                            .font(.caption)
                            .foregroundStyle(status.tint)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    if isQuitting {
                        Spinner(tint: DustyTheme.memory, size: 12)
                    }
                    Text(Bytes.memory(app.footprintBytes))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .contentTransition(.numericText())
                }
                .padding(.leading, 12)
                .padding(.trailing, showsRelaunch ? 8 : 14)
                .padding(.vertical, 8)
            }
            .buttonStyle(DustyRowButtonStyle())
            .accessibilityElement(children: .combine)
            .accessibilityValue(isSelected ? L10n.t("a11y.selected", "selected") : L10n.t("a11y.notSelected", "not selected"))

            if showsRelaunch {
                Button(L10n.t("memory.relaunch", "Relaunch"), action: onRelaunch)
                    .buttonStyle(DustySecondaryButtonStyle(tint: DustyTheme.warn))
                    .font(.caption.weight(.semibold))
                    .help(L10n.t("memory.relaunchHelp", "Quit and reopen it. Most apps pick up where they left off, with their memory back to a fresh start."))
                    .padding(.trailing, 12)
                    .disabled(isQuitting)
            }
        }
        .contextMenu {
            Button(L10n.f("memory.menu.quit", "Quit %@", app.name), action: onQuit)
            if app.bundleURL != nil {
                Button(L10n.f("memory.menu.relaunch", "Relaunch %@", app.name), action: onRelaunch)
            }
            if let url = app.bundleURL {
                Divider()
                Button(L10n.t("common.revealInFinder", "Reveal in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
    }

    private var showsRelaunch: Bool { growth != nil && app.bundleURL != nil }

    @ViewBuilder private var icon: some View {
        if let image = app.icon {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
        } else {
            IconTile(symbol: "app", tint: DustyTheme.usedSpace, size: 26, style: .soft)
        }
    }
}

// MARK: - Confirmation

/// The last gate before quitting: which apps, how much memory, and what
/// quitting means (their own Quit, save prompts included, and a way back).
struct MemoryQuitSheet: View {
    let apps: [RunningAppMemory]
    let availableBefore: Int64
    let availableAfter: Int64
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var bytes: Int64 { apps.reduce(0) { $0 + $1.footprintBytes } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(DustyTheme.hairline)
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 13) {
                    IconTile(symbol: "power", tint: DustyTheme.memory, size: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.f("memory.confirm.title", "Quit %d apps?", apps.count))
                            .font(.title3.weight(.bold))
                        Text(L10n.f("memory.confirm.subtitle", "Frees about %@ of memory", Bytes.memory(bytes)))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .accessibilityElement(children: .combine)

                HStack(spacing: 8) {
                    Text(L10n.t("memory.confirm.available", "Available memory"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Bytes.memory(availableBefore))
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(DustyTheme.faint)
                    Text(L10n.f("memory.confirm.about", "about %@", Bytes.memory(availableAfter)))
                        .fontWeight(.semibold)
                        .foregroundStyle(DustyTheme.success)
                }
                .font(.subheadline.monospacedDigit())
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DustyTheme.inset))
                .accessibilityElement(children: .combine)

                Group {
                    if apps.count > 4 {
                        ScrollView { appList }
                            .frame(height: 118)
                    } else {
                        appList
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DustyTheme.inset))

                VStack(alignment: .leading, spacing: 7) {
                    note(symbol: "hand.raised",
                         text: L10n.t("memory.confirm.saveNote", "Each app quits the way ⌘Q quits it. Apps with unsaved work ask you first."))
                    note(symbol: "arrow.uturn.backward",
                         text: L10n.t("memory.confirm.reopenNote", "Reopen them from the receipt for a few seconds."))
                    note(symbol: "checkmark.shield",
                         text: L10n.t("memory.confirm.safeNote", "Nothing is force quit, and no files are touched."))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 18)

            HStack(spacing: 10) {
                Button(L10n.t("common.cancel", "Cancel"), action: onCancel)
                    .buttonStyle(DustySecondaryButtonStyle(fullWidth: true))
                    .keyboardShortcut(.cancelAction)
                Button(action: onConfirm) {
                    Text(L10n.f("memory.confirm.action", "Quit %d apps", apps.count))
                }
                .buttonStyle(DustyPrimaryButtonStyle(tint: DustyTheme.memorySolid))
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DustyTheme.sheetRadius, style: .continuous)
                .fill(DustyTheme.elevated)
                .shadow(color: .black.opacity(0.25), radius: 24, y: -4)
                .padding(.bottom, -DustyTheme.sheetRadius)
        )
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var appList: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(apps) { app in
                HStack(spacing: 8) {
                    if let image = app.icon {
                        Image(nsImage: image)
                            .resizable()
                            .frame(width: 18, height: 18)
                            .accessibilityHidden(true)
                    }
                    Text(app.name)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Bytes.memory(app.footprintBytes))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
        .padding(12)
    }

    private func note(symbol: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - Receipt

/// What a quit did: memory freed and available before and after, anything that
/// stayed open (usually asking to save), and a Reopen that brings it all back
/// while its ring runs down.
struct MemoryToast: View {
    let receipt: MemoryQuitReceipt
    let reopenDeadline: Date?
    let reopenWindow: TimeInterval
    let onReopen: () -> Void
    let onDismiss: () -> Void

    private static let lingerSeconds: UInt64 = 12

    private var canReopen: Bool { reopenDeadline != nil }

    private var tint: Color {
        receipt.quit.isEmpty ? DustyTheme.warn : DustyTheme.success
    }

    private var symbol: String {
        if receipt.quit.isEmpty { return "exclamationmark" }
        return receipt.isRelaunch ? "arrow.clockwise" : "checkmark"
    }

    private var headline: String {
        if receipt.quit.isEmpty {
            return receipt.isRelaunch
                ? L10n.t("memory.toast.notRelaunched", "Nothing was relaunched")
                : L10n.t("memory.toast.nothingQuit", "No apps quit")
        }
        if receipt.isRelaunch {
            return L10n.f("memory.toast.relaunched", "Relaunched %@", receipt.quit.map(\.name).formatted(.list(type: .and)))
        }
        return L10n.f("memory.toast.freed", "%@ of memory freed", Bytes.memory(receipt.freedBytes))
    }

    private var detail: String {
        if !receipt.stillOpen.isEmpty {
            return L10n.f("memory.toast.stillOpen", "Still open: %@. It may be asking about unsaved work.",
                          receipt.stillOpen.formatted(.list(type: .and)))
        }
        if receipt.isRelaunch {
            return L10n.f("memory.toast.relaunchedBody", "It was holding %@.", Bytes.memory(receipt.freedBytes))
        }
        return L10n.f("memory.toast.available", "Available memory %1$@ → %2$@",
                      Bytes.memory(receipt.availableBefore), Bytes.memory(receipt.availableAfter))
    }

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(tint.opacity(0.16))
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(headline)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                Text(detail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 6)

            if canReopen {
                Button(action: onReopen) {
                    HStack(spacing: 6) {
                        if let reopenDeadline {
                            CountdownRing(deadline: reopenDeadline, duration: reopenWindow, tint: DustyTheme.accent, size: 13)
                        }
                        Text(L10n.t("memory.toast.reopen", "Reopen"))
                    }
                }
                .buttonStyle(DustySecondaryButtonStyle(tint: DustyTheme.accent))
                .keyboardShortcut("z", modifiers: .command)
                .help(L10n.t("memory.toast.reopenHelp", "Open the apps again (⌘Z)"))
            } else {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(DustyIconButtonStyle(size: 24))
                .accessibilityLabel(L10n.t("common.dismiss", "Dismiss"))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DustyTheme.elevated)
                .shadow(color: .black.opacity(0.2), radius: 18, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(DustyTheme.hairline, lineWidth: 1)
        )
        .task(id: "\(canReopen)-\(receipt.quit.count)-\(receipt.freedBytes)-\(receipt.stillOpen.count)") {
            guard !canReopen else { return }
            try? await Task.sleep(nanoseconds: Self.lingerSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }
}
