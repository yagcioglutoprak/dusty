import SwiftUI

/// First run. A new user gives a cleaner about thirty seconds of attention; this
/// spends them on the only thing that matters: why it can be trusted. Three
/// facts, staggered in, then one action that runs the first scan.
struct WelcomeView: View {
    let onScan: () -> Void
    let onSkip: () -> Void
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            hero
            Spacer(minLength: 22)
            facts
                .padding(.horizontal, DustyTheme.gutter)
            Spacer(minLength: 22)
            actions
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
        .onAppear { revealed = true }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [DustyTheme.azure.opacity(0.35), .clear],
                                         center: .center, startRadius: 4, endRadius: 70))
                    .frame(width: 150, height: 150)
                BrandMark(size: 76)
                    .scaleEffect(revealed || reduceMotion ? 1 : 0.7)
                    .opacity(revealed ? 1 : 0)
                    .animation(.spring(response: 0.55, dampingFraction: 0.7), value: revealed)
            }
            .frame(height: 110)
            .accessibilityHidden(true)

            VStack(spacing: 5) {
                Text(L10n.t("welcome.title", "Welcome to Dusty"))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(L10n.t("welcome.subtitle", "A disk cleaner that shows its work."))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
    }

    private var facts: some View {
        VStack(spacing: 0) {
            fact(index: 0, symbol: "list.bullet.rectangle.fill", tint: DustyTheme.azure,
                 title: L10n.t("welcome.row1.title", "It shows its work"),
                 text: L10n.t("welcome.row1.text", "A scan lists every path and its size before anything happens. Scanning never deletes."))
            Hairline(leading: 58)
            fact(index: 1, symbol: "checkmark.shield.fill", tint: DustyTheme.safe,
                 title: L10n.t("welcome.row2.title", "Allowlist only"),
                 text: L10n.t("welcome.row2.text", "Dusty can only delete from a fixed registry of cache and junk paths. Documents, Photos, and Mail are unreachable by design."))
            Hairline(leading: 58)
            fact(index: 2, symbol: "arrow.uturn.backward", tint: DustyTheme.developer,
                 title: L10n.t("welcome.row3.title", "Undo, plus a receipt"),
                 text: L10n.t("welcome.row3.text", "Cleans pass through the Trash with an Undo window, and every deletion is written to a log you can open."))
        }
        .dustyCard()
    }

    private func fact(index: Int, symbol: String, tint: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(symbol: symbol, tint: tint, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed || reduceMotion ? 0 : 12)
        .animation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.12 + Double(index) * 0.08), value: revealed)
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button(action: onScan) {
                Label(L10n.t("welcome.scan", "Scan my Mac"), systemImage: "magnifyingglass")
            }
            .buttonStyle(DustyPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
            .accessibilityHint(L10n.t("welcome.scan.hint", "Scans for reclaimable space. Nothing is deleted."))

            Button(L10n.t("welcome.skip", "I'll look around first"), action: onSkip)
                .buttonStyle(DustyLinkButtonStyle(tint: .secondary))
                .font(.subheadline.weight(.medium))
        }
        .opacity(revealed ? 1 : 0)
        .animation(.easeOut(duration: 0.35).delay(0.4), value: revealed)
    }
}
