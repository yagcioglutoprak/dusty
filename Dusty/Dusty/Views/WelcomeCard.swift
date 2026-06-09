import SwiftUI

/// One-time first-run overlay. A new user gets thirty seconds of attention; this
/// spends them on the only thing that matters for a cleaner: why it can be trusted.
/// Three facts, staggered in, then one gold action that runs the first Safe scan.
/// Drawn in-panel like every Dusty overlay (a sheet would steal the panel's focus
/// and close it).
struct WelcomeCard: View {
    let onScan: () -> Void
    let onSkip: () -> Void
    @State private var revealed = false

    var body: some View {
        VStack(spacing: 0) {
            hero
            VStack(spacing: 14) {
                trustRow(index: 0, icon: "list.bullet.rectangle",
                         title: "It shows its work",
                         text: "A scan lists every path and its size before anything happens. Scanning never deletes.")
                trustRow(index: 1, icon: "checklist",
                         title: "Allowlist only",
                         text: "Dusty can only delete from a fixed registry of cache and junk paths. Documents, Photos, and Mail are unreachable by design.")
                trustRow(index: 2, icon: "arrow.uturn.backward",
                         title: "Undo, plus a receipt",
                         text: "Cleans pass through the Trash with an Undo window, and every deletion is written to a log you can open.")
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 20)

            actions
        }
        .frame(width: 418)
        .background(
            RoundedRectangle(cornerRadius: DustyTheme.cornerRadius, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: DustyTheme.overlayShadow, radius: 28, y: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DustyTheme.cornerRadius, style: .continuous)
                .stroke(DustyTheme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DustyTheme.cornerRadius, style: .continuous))
        .padding(20)
        .onAppear { revealed = true }
    }

    /// Gold-lit sparkle over a soft radial pool: the brand moment, kept quiet.
    private var hero: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [DustyTheme.gold.opacity(0.28), .clear],
                            center: .center, startRadius: 2, endRadius: 56
                        )
                    )
                    .frame(width: 112, height: 112)
                Image(systemName: "sparkles")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(DustyTheme.brandGradient)
                    .scaleEffect(revealed ? 1 : 0.6)
                    .opacity(revealed ? 1 : 0)
                    .animation(.spring(response: 0.55, dampingFraction: 0.7), value: revealed)
            }
            .padding(.top, 6)
            .accessibilityHidden(true)

            Text("Welcome to Dusty")
                .font(.title2.weight(.bold))
            Text("A disk cleaner that shows its work.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 18)
        .padding(.bottom, 18)
    }

    private func trustRow(index: Int, icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(DustyTheme.gold)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(DustyTheme.gold.opacity(0.12))
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed ? 0 : 14)
        .animation(
            .spring(response: 0.5, dampingFraction: 0.8).delay(0.12 + Double(index) * 0.09),
            value: revealed
        )
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button(action: onScan) {
                Text("Run my first Safe scan")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DustyTheme.onGold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(DustyTheme.brandGradient)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .accessibilityHint("Scans for reclaimable space. Nothing is deleted.")

            Button("I'll look around first", action: onSkip)
                .buttonStyle(.link)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 18)
        .opacity(revealed ? 1 : 0)
        .animation(.easeOut(duration: 0.35).delay(0.4), value: revealed)
    }
}
