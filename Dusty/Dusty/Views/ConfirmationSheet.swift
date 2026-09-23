import SwiftUI
import AppKit
import CleanerEngine

/// The paths of one target that a clean would remove, for the confirmation list.
struct ConfirmationGroup: Identifiable {
    let id: String
    let name: String
    let paths: [ResolvedPath]

    var bytes: Int64 { paths.reduce(0) { $0 + $1.estimatedBytes } }
}

/// The last gate before a clean: a bottom sheet that says exactly how much,
/// from where, what it does to free space, and how to take it back. Every path
/// is one click away. Drawn in-panel (never a system sheet) so the menu bar
/// window keeps focus while the user decides.
struct ConfirmationSheet: View {
    let level: CleanupLevel
    let groups: [ConfirmationGroup]
    let bytes: Int64
    let itemCount: Int
    let dryRun: Bool
    let moveToTrash: Bool
    let skippedApps: [String]
    let freeBefore: Int64
    /// Free space once the clean lands; nil when it will not free space right
    /// away (items kept in the Trash).
    let freeAfter: Int64?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var showsItems = false

    private var tint: Color { dryRun ? DustyTheme.accent : level.tint }
    private var buttonTint: Color { dryRun ? DustyTheme.azure : level.solid }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(DustyTheme.hairline)
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 16) {
                header
                if !dryRun, let freeAfter {
                    freeSpaceRow(after: freeAfter)
                }
                notes
                itemsDisclosure
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 18)

            actions
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DustyTheme.sheetRadius, style: .continuous)
                .fill(DustyTheme.elevated)
                .shadow(color: .black.opacity(0.25), radius: 24, y: -4)
                // Run the shape past the panel's bottom edge so only the top corners round.
                .padding(.bottom, -DustyTheme.sheetRadius)
        )
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var header: some View {
        HStack(spacing: 13) {
            IconTile(symbol: dryRun ? "eye.fill" : "trash.fill", tint: tint, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(dryRun
                     ? L10n.t("confirm.title.dryRun", "Preview Cleanup")
                     : L10n.f("confirm.titleBytes", "Clean %@?", Bytes.format(bytes)))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                Text(L10n.f("confirm.fromLevel", "%1$d items from %2$@", itemCount, level.name))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func freeSpaceRow(after: Int64) -> some View {
        HStack(spacing: 8) {
            Text(L10n.t("confirm.freeSpace", "Free space"))
                .foregroundStyle(.secondary)
            Spacer()
            Text(Bytes.format(freeBefore))
                .foregroundStyle(.secondary)
            Image(systemName: "arrow.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(DustyTheme.faint)
            Text(Bytes.format(after))
                .fontWeight(.semibold)
                .foregroundStyle(DustyTheme.success)
        }
        .font(.subheadline.monospacedDigit())
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DustyTheme.inset))
        .accessibilityElement(children: .combine)
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !skippedApps.isEmpty {
                note(symbol: "app.badge", tint: DustyTheme.warn,
                     text: L10n.f("confirm.skippingApps", "Skipping %@ cache, app is open",
                                  skippedApps.formatted(.list(type: .and))))
            }
            if dryRun {
                note(symbol: "eye", tint: DustyTheme.accent,
                     text: L10n.t("confirm.dryRunNote", "Dry run: nothing will be deleted"))
            } else {
                note(symbol: "arrow.uturn.backward", tint: .secondary,
                     text: L10n.t("confirm.undoNote", "Recoverable for a few seconds via Undo"))
                if moveToTrash {
                    note(symbol: "trash", tint: .secondary,
                         text: L10n.t("confirm.trashNote", "Items stay in the Trash until you empty it"))
                }
                note(symbol: "doc.text", tint: .secondary,
                     text: L10n.t("confirm.logNote", "Every path is written to the deletion log"))
            }
        }
    }

    private func note(symbol: String, tint: Color, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var itemsDisclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(DustyTheme.revealSpring) { showsItems.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(showsItems ? 90 : 0))
                    Text(showsItems
                         ? L10n.t("confirm.hideItems", "Hide items")
                         : L10n.f("confirm.showItems", "Show all %d items", itemCount))
                        .font(.caption.weight(.semibold))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(DustyLinkButtonStyle())

            if showsItems {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(group.name)
                                        .font(.caption.weight(.semibold))
                                    Spacer()
                                    Text(Bytes.format(group.bytes))
                                        .font(.caption.weight(.semibold).monospacedDigit())
                                }
                                ForEach(group.paths) { path in
                                    HStack(spacing: 8) {
                                        Text(path.displayName)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .help(path.path)
                                        Spacer(minLength: 8)
                                        Text(Bytes.format(path.estimatedBytes))
                                            .monospacedDigit()
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 10)
                                    .contextMenu {
                                        if path.path.hasPrefix("/") {
                                            Button(L10n.t("common.revealInFinder", "Reveal in Finder")) {
                                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path.path)])
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 170)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DustyTheme.inset))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(L10n.t("common.cancel", "Cancel"), action: onCancel)
                .buttonStyle(DustySecondaryButtonStyle(fullWidth: true))
                .keyboardShortcut(.cancelAction)
            Button(action: onConfirm) {
                Text(dryRun
                     ? L10n.t("confirm.action.dryRun", "Run Dry Run")
                     : L10n.f("confirm.action.deleteBytes", "Delete %@", Bytes.format(bytes)))
                    .monospacedDigit()
            }
            .buttonStyle(DustyPrimaryButtonStyle(tint: buttonTint))
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }
}
