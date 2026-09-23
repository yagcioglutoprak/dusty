import SwiftUI
import CleanerEngine

/// The receipt after a clean, floating at the bottom of the panel: how much,
/// what it did to free space, and (while it lasts) an Undo whose ring empties
/// as the window closes. Receipts that need no action fade on their own.
struct ResultToast: View {
    let result: DeletionResult
    let style: ResultBannerStyle
    let undoDeadline: Date?
    let undoWindow: TimeInterval
    let onUndo: () -> Void
    let onDismiss: () -> Void

    @State private var showsSkipped = false

    /// How long a finished receipt stays up before it clears itself.
    private static let lingerSeconds: UInt64 = 12

    private var isDryRun: Bool {
        !result.entries.isEmpty && result.entries.allSatisfy(\.dryRun)
    }

    private var tint: Color {
        if isDryRun { return DustyTheme.accent }
        return style == .trashed ? DustyTheme.warn : DustyTheme.success
    }

    private var symbol: String {
        if isDryRun { return "eye.fill" }
        return style == .trashed ? "trash.fill" : "checkmark"
    }

    private var headline: String {
        let amount = Bytes.format(result.bytesFreed)
        if isDryRun { return L10n.f("toast.dryRun", "Dry run: %@ would be cleaned", amount) }
        switch style {
        case .trashed: return L10n.f("toast.trashed", "%@ moved to Trash", amount)
        case .undoable, .reclaimed: return L10n.f("toast.cleaned", "%@ cleaned", amount)
        }
    }

    private var detail: String {
        if isDryRun { return L10n.t("toast.dryRunBody", "Nothing was deleted.") }
        switch style {
        case .trashed:
            return L10n.t("result.body.trashed", "Empty Trash to reclaim this space.")
        case .undoable:
            return L10n.t("result.body.undoable", "Undo is available for a few seconds.")
        case .reclaimed:
            return L10n.f("toast.freeSpace", "Free space %1$@ → %2$@",
                          Bytes.format(result.freeSpaceBefore), Bytes.format(result.freeSpaceAfter))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)

                Spacer(minLength: 6)

                if style == .undoable {
                    Button(action: onUndo) {
                        HStack(spacing: 6) {
                            if let undoDeadline {
                                CountdownRing(deadline: undoDeadline, duration: undoWindow, tint: DustyTheme.accent, size: 13)
                            }
                            Text(L10n.t("common.undo", "Undo"))
                        }
                    }
                    .buttonStyle(DustySecondaryButtonStyle(tint: DustyTheme.accent))
                    .keyboardShortcut("z", modifiers: .command)
                    .help(L10n.t("toast.undoHelp", "Put everything back (⌘Z)"))
                } else {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(DustyIconButtonStyle(size: 24))
                    .accessibilityLabel(L10n.t("common.dismiss", "Dismiss"))
                }
            }

            if !result.skippedPaths.isEmpty {
                skipped
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
        .task(id: lingerKey) {
            guard style != .undoable else { return }
            try? await Task.sleep(nanoseconds: Self.lingerSeconds * 1_000_000_000)
            guard !Task.isCancelled, !showsSkipped else { return }
            onDismiss()
        }
    }

    /// Restarts the linger timer whenever the receipt changes state.
    private var lingerKey: String {
        "\(style)-\(result.bytesFreed)-\(result.freeSpaceAfter)"
    }

    private var skipped: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(DustyTheme.revealSpring) { showsSkipped.toggle() }
            } label: {
                Label(L10n.f(showsSkipped ? "result.skipped.hide" : "result.skipped.show",
                             showsSkipped ? "%d skipped, tap to hide" : "%d skipped, tap to show",
                             result.skippedPaths.count),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
            }
            .buttonStyle(DustyLinkButtonStyle(tint: DustyTheme.warn))
            .padding(.leading, 43)

            if showsSkipped {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(result.skippedPaths.enumerated()), id: \.offset) { _, item in
                            Text(L10n.f("result.skippedLine", "%1$@: %2$@",
                                        (item.path as NSString).abbreviatingWithTildeInPath, item.reason))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 90)
                .padding(.leading, 43)
            }
        }
    }
}
