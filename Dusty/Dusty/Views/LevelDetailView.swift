import SwiftUI
import AppKit
import CleanerEngine

/// One cleanup level, item by item: every target Dusty found, largest first,
/// each with a checkbox, and every path inside it one click away. A sticky bar
/// at the bottom always says what a clean would take and starts it.
struct LevelDetailView: View {
    let level: CleanupLevel
    @ObservedObject var viewModel: DustyViewModel
    @ObservedObject var settings: AppSettings
    @State private var query = ""
    @State private var expanded: Set<String> = []
    @State private var highlighted: String?

    private var result: LevelScanResult? { viewModel.levelResult(for: level) }

    /// Targets that found something (or failed to look), largest first.
    private var populated: [TargetScanResult] {
        (result?.targetResults ?? [])
            .filter { !$0.resolvedPaths.isEmpty || !$0.scanErrors.isEmpty }
            .sorted { $0.totalBytes > $1.totalBytes }
    }

    private var visibleTargets: [TargetScanResult] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return populated }
        return populated.filter { target in
            target.target.localizedName.localizedCaseInsensitiveContains(needle)
                || target.resolvedPaths.contains {
                    $0.displayName.localizedCaseInsensitiveContains(needle)
                        || $0.path.localizedCaseInsensitiveContains(needle)
                }
        }
    }

    private var blockedIDs: Set<String> { viewModel.blockedTargetIDs(for: level) }

    var body: some View {
        VStack(spacing: 0) {
            NavHeader(title: level.name, subtitle: subtitle, onBack: { viewModel.goHome() }) {
                if result != nil && viewModel.itemCount(for: level) > 0 {
                    selectAllButton
                }
            }
            Hairline()
            content
            if result != nil {
                bottomBar
            }
        }
    }

    private var subtitle: String {
        guard let result else { return level.blurb }
        let items = viewModel.itemCount(for: level)
        if items == 0 { return L10n.t("home.level.nothing", "Nothing to clean") }
        return L10n.f("level.subtitle", "%1$@ found · %2$d items", Bytes.format(result.totalBytes), items)
    }

    private var selectAllButton: some View {
        let allSelected = viewModel.selectedCount(for: level) == viewModel.itemCount(for: level)
        return Button(allSelected ? L10n.t("level.selectNone", "Select None") : L10n.t("level.selectAll", "Select All")) {
            withAnimation(.easeOut(duration: 0.15)) {
                viewModel.setAllSelected(level: level, selected: !allSelected)
            }
        }
        .buttonStyle(DustySecondaryButtonStyle())
        .font(.caption.weight(.semibold))
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        if result == nil {
            VStack(spacing: 14) {
                Spacer()
                if viewModel.isScanning {
                    Spinner(tint: level.tint, size: 22)
                    Text(L10n.t("panel.scan.scanning", "Scanning…"))
                        .font(.headline)
                } else {
                    EmptyStateView(
                        symbol: level.symbol,
                        tint: level.tint,
                        title: L10n.t("level.notScanned.title", "Not scanned yet"),
                        message: L10n.t("level.notScanned", "Run a scan to see what this level holds.")
                    )
                    Button {
                        viewModel.startScan(settings: settings)
                    } label: {
                        Label(L10n.t("panel.scan.start", "Scan disk"), systemImage: "magnifyingglass")
                    }
                    .buttonStyle(DustyPrimaryButtonStyle(compact: true))
                }
                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if populated.isEmpty {
            VStack {
                Spacer()
                EmptyStateView(
                    symbol: "checkmark",
                    tint: DustyTheme.success,
                    title: L10n.t("level.empty.title", "Nothing to clean here"),
                    message: L10n.f("level.empty.body", "Dusty checked %d places at this level and found nothing worth removing.",
                                    result?.targetResults.count ?? 0)
                )
                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            list
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(level.blurb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    if populated.count > 5 {
                        SearchField(text: $query, prompt: L10n.t("level.filter", "Filter by name or path"))
                    }

                    if let error = viewModel.errorMessage {
                        InlineBanner(
                            symbol: "exclamationmark.circle.fill",
                            tint: DustyTheme.danger,
                            title: error,
                            onDismiss: { viewModel.errorMessage = nil }
                        )
                    }

                    let blocking = viewModel.blockingApps(for: level)
                    if !blocking.isEmpty {
                        InlineBanner(
                            symbol: "app.badge",
                            tint: DustyTheme.warn,
                            title: L10n.f("level.blocking",
                                          "%2$@ are open, so their caches are skipped. Quit them to include them.",
                                          blocking.count, blocking.formatted(.list(type: .and)))
                        )
                    }

                    ForEach(visibleTargets) { target in
                        TargetCard(
                            target: target,
                            tint: level.tint,
                            isExpanded: expanded.contains(target.id) || target.target.needsUserSelection,
                            isHighlighted: highlighted == target.id,
                            isBlocked: blockedIDs.contains(target.id),
                            onToggleExpand: { toggleExpanded(target.id) },
                            onSetAll: { selected in
                                viewModel.setAllSelected(level: level, targetID: target.id, selected: selected)
                            },
                            onTogglePath: { pathID in
                                viewModel.togglePathSelection(level: level, targetID: target.id, pathID: pathID)
                            }
                        )
                        .id(target.id)
                    }

                    if visibleTargets.isEmpty {
                        Text(L10n.f("level.noMatches", "Nothing matches “%@”.", query))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }

                    let checkedElsewhere = (result?.targetResults.count ?? 0) - populated.count
                    if checkedElsewhere > 0 && query.isEmpty {
                        Label(L10n.f("level.alsoChecked", "Also checked %d more places, nothing to clean there.",
                                     checkedElsewhere),
                              systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(DustyTheme.faint)
                            .padding(.horizontal, 4)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, DustyTheme.gutter)
                .padding(.vertical, 14)
                // Leave room for the receipt toast so it never hides the last card.
                .padding(.bottom, viewModel.lastDeletionResult == nil ? 0 : 64)
            }
            .task(id: viewModel.focusedTargetID) {
                guard let id = viewModel.focusedTargetID else { return }
                expanded.insert(id)
                highlighted = id
                try? await Task.sleep(nanoseconds: 350_000_000)
                withAnimation(DustyTheme.revealSpring) { proxy.scrollTo(id, anchor: .top) }
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                withAnimation(.easeOut(duration: 0.4)) { highlighted = nil }
            }
        }
    }

    private func toggleExpanded(_ id: String) {
        withAnimation(DustyTheme.revealSpring) {
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        let bytes = viewModel.cleanableBytes(for: level)
        let count = viewModel.cleanablePaths(for: level).count
        let isCleaningHere = viewModel.isCleaning && viewModel.cleaningLevel == level
        let blocking = viewModel.blockingApps(for: level)

        return VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(bytes > 0
                         ? L10n.f("level.bar.selected", "%@ selected", Bytes.format(bytes))
                         : L10n.t("level.bar.nothing", "Nothing selected"))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                    Text(barDetail(count: count, blocking: blocking))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                Button {
                    viewModel.requestClean(level: level)
                } label: {
                    HStack(spacing: 6) {
                        if isCleaningHere {
                            Spinner(tint: .white, size: 12)
                            Text(L10n.t("hero.cleaning", "Cleaning…"))
                        } else {
                            Image(systemName: settings.dryRunDefault ? "eye" : "trash")
                            Text(settings.dryRunDefault
                                 ? L10n.t("level.bar.preview", "Preview")
                                 : L10n.t("level.clean", "Clean"))
                        }
                    }
                }
                .buttonStyle(DustyPrimaryButtonStyle(tint: level.tint, compact: true))
                .disabled(bytes == 0 || viewModel.isCleaning)
                .accessibilityLabel(L10n.f("level.a11y.cleanLabel", "Clean %@ items", level.name))
            }
            .padding(.horizontal, DustyTheme.gutter)
            .frame(height: 58)
        }
        .background(DustyTheme.canvas)
    }

    private func barDetail(count: Int, blocking: [String]) -> String {
        if !blocking.isEmpty {
            return L10n.f("level.bar.skipping", "Skipping %@ while open", blocking.formatted(.list(type: .and)))
        }
        if settings.dryRunDefault {
            return L10n.t("confirm.dryRunNote", "Dry run: nothing will be deleted")
        }
        if count == 0 {
            return L10n.t("level.bar.pick", "Tick the items you want gone")
        }
        return L10n.f("level.bar.items", "%d items, recoverable for a few seconds", count)
    }
}

// MARK: - Target card

/// One cleanup target: a group checkbox, its name and size, and (folded open)
/// every path it found. Manual-pick targets start open, since nothing in them
/// is selected until someone ticks it.
private struct TargetCard: View {
    let target: TargetScanResult
    let tint: Color
    let isExpanded: Bool
    let isHighlighted: Bool
    let isBlocked: Bool
    let onToggleExpand: () -> Void
    let onSetAll: (Bool) -> Void
    let onTogglePath: (String) -> Void

    /// Big targets (hundreds of cache folders) list in pages.
    @State private var visibleLimit = 40

    private var paths: [ResolvedPath] {
        target.resolvedPaths.sorted { $0.estimatedBytes > $1.estimatedBytes }
    }

    private var checkState: CheckState {
        CheckState(selected: target.selectedCount, total: target.resolvedPaths.count)
    }

    private var subtitle: String {
        let count = target.resolvedPaths.count
        if count == 0 { return L10n.t("target.nothing", "Nothing found") }
        switch checkState {
        case .on:
            return L10n.f("target.items", "%d items", count)
        case .off:
            return target.target.needsUserSelection
                ? L10n.f("target.pickByHand", "%d items · pick by hand", count)
                : L10n.f("target.noneSelected", "%d items · none selected", count)
        case .mixed:
            return L10n.f("target.partial", "%1$d of %2$d items · %3$@", target.selectedCount, count,
                          Bytes.format(target.selectedBytes))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                Hairline(leading: 14)
                items
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DustyTheme.cardRadius, style: .continuous))
        .dustyCard()
        .overlay(
            RoundedRectangle(cornerRadius: DustyTheme.cardRadius, style: .continuous)
                .strokeBorder(tint, lineWidth: 2)
                .opacity(isHighlighted ? 1 : 0)
        )
    }

    private var header: some View {
        HStack(spacing: 11) {
            Button {
                onSetAll(checkState != .on)
            } label: {
                DustyCheckbox(state: checkState, tint: tint)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(target.resolvedPaths.isEmpty)
            .accessibilityLabel(target.target.localizedName)
            .accessibilityValue(checkState == .on
                                ? L10n.t("a11y.selected", "selected")
                                : checkState == .off ? L10n.t("a11y.notSelected", "not selected")
                                : L10n.t("a11y.partlySelected", "partly selected"))

            Button(action: onToggleExpand) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(target.target.localizedName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if isBlocked, let app = target.target.requiresAppClosed {
                            Label(L10n.f("target.skippedWhileOpen", "Skipped while %@ is open", app),
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(DustyTheme.warn)
                                .lineLimit(1)
                        } else {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 6)
                    Text(Bytes.format(target.totalBytes))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(checkState == .off ? DustyTheme.faint : Color.primary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DustyTheme.faint)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .opacity(target.target.needsUserSelection ? 0 : 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.f(isExpanded ? "target.a11y.hideItems" : "target.a11y.showItems",
                                       isExpanded ? "Hide the %1$d items of %2$@" : "Show the %1$d items of %2$@",
                                       target.resolvedPaths.count, target.target.localizedName))
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .opacity(isBlocked ? 0.7 : 1)
    }

    private var items: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(paths.prefix(visibleLimit)) { path in
                PathRow(path: path, tint: tint) { onTogglePath(path.id) }
            }
            if paths.count > visibleLimit {
                Button {
                    withAnimation(DustyTheme.revealSpring) { visibleLimit += 200 }
                } label: {
                    Text(L10n.f("target.showMore", "Show %d more", paths.count - visibleLimit))
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 44)
                        .padding(.vertical, 8)
                }
                .buttonStyle(DustyLinkButtonStyle())
            }
            ForEach(target.scanErrors, id: \.self) { error in
                Label(error, systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(DustyTheme.danger)
                    .lineLimit(3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
        }
        .padding(.vertical, 4)
    }
}

/// One path: a whole-row toggle with its name, where it lives, and its size.
private struct PathRow: View {
    let path: ResolvedPath
    let tint: Color
    let onToggle: () -> Void

    /// Rows older than this get an age hint; fresher ages are noise.
    private static let ageHintAfterDays: TimeInterval = 30 * 86400

    private var isFile: Bool { path.path.hasPrefix("/") }

    private var location: String? {
        var parts: [String] = []
        if isFile {
            parts.append((path.path as NSString).abbreviatingWithTildeInPath)
        }
        if let modified = path.lastModified, Date().timeIntervalSince(modified) > Self.ageHintAfterDays {
            parts.append(L10n.f("path.untouchedSince", "untouched %@", RelativeTime.label(for: modified)))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 10) {
                DustyCheckbox(state: path.isSelected ? .on : .off, tint: tint)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(path.displayName)
                        .font(.subheadline)
                        .foregroundStyle(path.isSelected ? Color.primary : Color.secondary)
                        .lineLimit(2)
                    if let location {
                        Text(location)
                            .font(.caption)
                            .foregroundStyle(DustyTheme.faint)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 8)
                Text(Bytes.format(path.estimatedBytes))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
            }
            .padding(.leading, 13)
            .padding(.trailing, 14)
            .padding(.vertical, 7)
        }
        .buttonStyle(DustyRowButtonStyle())
        .help(path.path)
        .contextMenu {
            if isFile {
                Button(L10n.t("common.revealInFinder", "Reveal in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path.path)])
                }
                Button(L10n.t("common.copyPath", "Copy Path")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(path.path, forType: .string)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(path.isSelected ? L10n.t("a11y.selected", "selected") : L10n.t("a11y.notSelected", "not selected"))
        .accessibilityAddTraits(.isButton)
    }
}

/// A compact search field on an inset capsule.
struct SearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DustyTheme.faint)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.subheadline)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(DustyTheme.faint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("level.clearFilter", "Clear filter"))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(DustyTheme.inset)
        )
    }
}
