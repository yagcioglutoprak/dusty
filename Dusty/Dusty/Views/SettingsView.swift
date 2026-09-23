import SwiftUI
import AppKit
import CleanerEngine

/// Settings as a full screen of the panel, grouped the way people look for
/// things: how Dusty shows up, what it does on its own, how it cleans.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var updater: Updater
    @ObservedObject var viewModel: DustyViewModel
    @ObservedObject private var stats = CleanStatsStore.shared

    /// Seeded from what the app launched with, so switching the picker leaves a
    /// visible "restart to apply" affordance instead of silently doing nothing.
    @State private var language = AppLanguage.current

    var body: some View {
        VStack(spacing: 0) {
            NavHeader(title: L10n.t("common.settings", "Settings"), onBack: { viewModel.goHome() })
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    general
                    menuBar
                    automation
                    cleaning
                    if stats.cleanCount > 0 {
                        statistics
                    }
                    updates
                    safety
                    about
                }
                .padding(.horizontal, DustyTheme.gutter)
                .padding(.vertical, 16)
            }
        }
    }

    // MARK: - General

    private var general: some View {
        SettingsGroup(title: L10n.t("settings.section.general", "General")) {
            SettingRow(symbol: "power", tint: DustyTheme.usedSpace,
                       title: L10n.t("settings.launchAtLogin", "Launch at login")) {
                SettingSwitch(title: L10n.t("settings.launchAtLogin", "Launch at login"), isOn: $settings.launchAtLogin)
            }
            Hairline(leading: 50)
            SettingRow(symbol: "globe", tint: DustyTheme.azure,
                       title: L10n.t("settings.language", "Panel language")) {
                Picker(L10n.t("settings.language", "Panel language"), selection: $language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .onChange(of: language) { newValue in AppLanguage.apply(newValue) }
            }
            // Bundle localizations are chosen once, at launch. Rather than pretend
            // otherwise, say so and offer the restart.
            if language != AppLanguage.launchLanguage {
                Hairline(leading: 50)
                HStack(spacing: 10) {
                    Text(L10n.t("settings.language.restartNote", "Dusty has to restart to change language."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button(L10n.t("settings.language.restart", "Restart Dusty")) { AppLanguage.relaunch() }
                        .buttonStyle(DustySecondaryButtonStyle(tint: DustyTheme.accent))
                }
                .padding(.leading, 50)
                .padding(.trailing, 12)
                .padding(.vertical, 9)
            }
        }
    }

    // MARK: - Menu bar

    private var menuBar: some View {
        SettingsGroup(title: L10n.t("settings.section.menuBar", "Menu bar")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    IconTile(symbol: "menubar.rectangle", tint: DustyTheme.indigo, size: 26)
                    Text(L10n.t("settings.menuBarStyle", "Show beside the icon"))
                        .font(.subheadline)
                    Spacer()
                }
                Picker(L10n.t("settings.menuBarStyle", "Show beside the icon"), selection: $settings.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .padding(.leading, 38)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Hairline(leading: 50)
            SettingRow(symbol: "sparkles", tint: DustyTheme.accent,
                       title: L10n.t("settings.menuBarReclaimable", "Show reclaimable space in the menu bar")) {
                SettingSwitch(title: L10n.t("settings.menuBarReclaimable", "Show reclaimable space in the menu bar"),
                              isOn: $settings.menuBarShowsReclaimable)
            }
            .disabled(settings.menuBarStyle == .iconOnly)
            Hairline(leading: 50)
            SettingRow(symbol: "timer", tint: DustyTheme.usedSpace,
                       title: L10n.t("settings.refresh.title", "Update free space every")) {
                SettingStepper(title: L10n.t("settings.refresh.title", "Update free space every"),
                               value: $settings.refreshIntervalSeconds, range: 10...300, step: 10,
                               label: L10n.f("settings.value.seconds", "%d s", Int(settings.refreshIntervalSeconds)))
            }
        }
    }

    // MARK: - Automation

    private var automation: some View {
        SettingsGroup(title: L10n.t("settings.section.automation", "Automation"),
                      footer: settings.dryRunDefault
                        ? L10n.t("settings.autoCleanDryRunNote", "Off while dry run is the default: nothing is deleted unattended.")
                        : autoCleanCaption) {
            SettingRow(symbol: "magnifyingglass", tint: DustyTheme.azure,
                       title: L10n.t("settings.autoScanEnabled", "Scan in the background"),
                       caption: L10n.t("settings.autoScanCaption",
                                       "Quietly keeps the menu bar figure current. Never deletes anything on its own.")) {
                SettingSwitch(title: L10n.t("settings.autoScanEnabled", "Scan in the background"),
                              isOn: $settings.autoScanEnabled)
            }
            if settings.autoScanEnabled {
                Hairline(leading: 50)
                SettingRow(symbol: "clock", tint: DustyTheme.usedSpace,
                           title: L10n.t("settings.autoScanFrequency", "How often")) {
                    SettingStepper(title: L10n.t("settings.autoScanFrequency", "How often"),
                                   value: $settings.autoScanIntervalHours, range: 1...24, step: 1,
                                   label: L10n.f("settings.autoScanInterval", "Every %d hours", settings.autoScanIntervalHours))
                }
            }
            Hairline(leading: 50)
            SettingRow(symbol: "calendar", tint: DustyTheme.safe,
                       title: L10n.t("settings.autoCleanEnabled", "Clean Safe items on a schedule")) {
                SettingSwitch(title: L10n.t("settings.autoCleanEnabled", "Clean Safe items on a schedule"),
                              isOn: $settings.autoCleanEnabled)
            }
            .disabled(settings.dryRunDefault)
            if settings.autoCleanEnabled && !settings.dryRunDefault {
                Hairline(leading: 50)
                SettingRow(symbol: "repeat", tint: DustyTheme.usedSpace,
                           title: L10n.t("settings.autoCleanFrequency", "Frequency")) {
                    Picker(L10n.t("settings.autoCleanFrequency", "Frequency"), selection: $settings.autoCleanFrequencyDays) {
                        Text(L10n.t("settings.frequency.daily", "Every day")).tag(1)
                        Text(L10n.t("settings.frequency.weekly", "Every week")).tag(7)
                        Text(L10n.t("settings.frequency.biweekly", "Every two weeks")).tag(14)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }
            Hairline(leading: 50)
            SettingRow(symbol: "externaldrive.badge.exclamationmark", tint: DustyTheme.warn,
                       title: L10n.t("settings.autoCleanLowDisk", "Also clean when free space runs low")) {
                SettingSwitch(title: L10n.t("settings.autoCleanLowDisk", "Also clean when free space runs low"),
                              isOn: $settings.autoCleanWhenLowDisk)
            }
            .disabled(settings.dryRunDefault)
            if settings.autoCleanWhenLowDisk && !settings.dryRunDefault {
                Hairline(leading: 50)
                SettingRow(symbol: "gauge.with.dots.needle.33percent", tint: DustyTheme.usedSpace,
                           title: L10n.t("settings.threshold", "Threshold")) {
                    SettingStepper(title: L10n.t("settings.threshold", "Threshold"),
                                   value: $settings.autoCleanLowDiskThresholdGB, range: 5...100, step: 5,
                                   label: L10n.f("settings.autoCleanThreshold", "Below %d GB free",
                                                 settings.autoCleanLowDiskThresholdGB))
                }
            }
            if (settings.autoCleanEnabled || settings.autoCleanWhenLowDisk) && !settings.dryRunDefault {
                Hairline(leading: 50)
                SettingRow(symbol: CleanupLevel.developer.symbol, tint: DustyTheme.developer,
                           title: L10n.t("settings.autoCleanDeveloper", "Include Developer caches")) {
                    SettingSwitch(title: L10n.t("settings.autoCleanDeveloper", "Include Developer caches"),
                                  isOn: $settings.autoCleanIncludesDeveloper)
                }
            }
        }
    }

    private var autoCleanCaption: String {
        let scope = settings.autoCleanIncludesDeveloper
            ? L10n.t("settings.autoCleanScope.developer",
                     "Safe caches plus Developer caches (DerivedData, package managers)")
            : L10n.t("settings.autoCleanScope.safe", "Safe-level caches only")
        return L10n.f(
            "settings.autoCleanCaption",
            "%@. Apps that are open are skipped, a notification reports what was reclaimed, and every path lands in the deletion log.",
            scope
        )
    }

    // MARK: - Cleaning

    private var cleaning: some View {
        SettingsGroup(title: L10n.t("settings.section.cleanupDefaults", "Cleanup defaults")) {
            SettingRow(symbol: "eye", tint: DustyTheme.accent,
                       title: L10n.t("settings.dryRunDefault", "Dry run by default"),
                       caption: L10n.t("settings.dryRunCaption", "Cleans report what they would delete, and delete nothing.")) {
                SettingSwitch(title: L10n.t("settings.dryRunDefault", "Dry run by default"), isOn: $settings.dryRunDefault)
            }
            Hairline(leading: 50)
            SettingRow(symbol: "trash", tint: DustyTheme.usedSpace,
                       title: L10n.t("settings.moveToTrash", "Keep Developer & Deep items in Trash"),
                       caption: L10n.t("settings.moveToTrashCaption", "Empty the Trash yourself to reclaim the space.")) {
                SettingSwitch(title: L10n.t("settings.moveToTrash", "Keep Developer & Deep items in Trash"),
                              isOn: $settings.moveToTrashDefault)
            }
            Hairline(leading: 50)
            SettingRow(symbol: "doc.text.magnifyingglass", tint: DustyTheme.deep,
                       title: L10n.t("settings.logAge.title", "Offer system logs older than")) {
                SettingStepper(title: L10n.t("settings.logAge.title", "Offer system logs older than"),
                               value: $settings.logAgeThresholdDays, range: 7...365, step: 7,
                               label: L10n.f("settings.value.days", "%d days", settings.logAgeThresholdDays))
            }
        }
    }

    // MARK: - Statistics

    private var statistics: some View {
        SettingsGroup(title: L10n.t("settings.section.stats", "Statistics")) {
            HStack(spacing: 0) {
                statTile(value: Bytes.format(stats.lifetimeBytes), label: L10n.t("settings.stats.lifetime", "Reclaimed all-time"))
                Rectangle().fill(DustyTheme.hairline).frame(width: 1)
                statTile(value: "\(stats.cleanCount)", label: L10n.t("settings.stats.cleans", "Cleans"))
                if let since = stats.firstCleanAt {
                    Rectangle().fill(DustyTheme.hairline).frame(width: 1)
                    statTile(value: since.formatted(.dateTime.month(.abbreviated).year()),
                             label: L10n.t("settings.stats.since", "Since"))
                }
            }
            .frame(height: 64)
            if !stats.recent.isEmpty {
                Hairline()
                VStack(alignment: .leading, spacing: 0) {
                    Text(L10n.t("settings.stats.recent", "Recent cleans"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DustyTheme.faint)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                    ForEach(stats.recent) { record in
                        HStack(spacing: 8) {
                            let level = CleanupLevel(rawValue: record.level)
                            Circle()
                                .fill(level?.tint ?? DustyTheme.usedSpace)
                                .frame(width: 7, height: 7)
                            Text(level?.name ?? L10n.f("settings.stats.level", "Level %d", record.level))
                                .foregroundStyle(.secondary)
                            Text(RelativeTime.label(for: record.date))
                                .foregroundStyle(DustyTheme.faint)
                            Spacer()
                            Text(Bytes.format(record.bytes))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Updates

    private var updates: some View {
        SettingsGroup(title: L10n.t("settings.section.updates", "Updates")) {
            SettingRow(symbol: "arrow.triangle.2.circlepath", tint: DustyTheme.azure,
                       title: L10n.t("settings.updates.auto", "Check for updates automatically")) {
                SettingSwitch(title: L10n.t("settings.updates.auto", "Check for updates automatically"), isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))
            }
            Hairline(leading: 50)
            SettingRow(symbol: "arrow.down.circle", tint: DustyTheme.azure,
                       title: L10n.t("settings.updates.autoInstall", "Download and install automatically")) {
                SettingSwitch(title: L10n.t("settings.updates.autoInstall", "Download and install automatically"), isOn: Binding(
                    get: { updater.automaticallyDownloadsUpdates },
                    set: { updater.automaticallyDownloadsUpdates = $0 }
                ))
            }
            Hairline(leading: 50)
            HStack {
                Text(verbatim: "Dusty \(Bundle.main.shortVersion) (\(Bundle.main.buildVersion))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.t("settings.updates.checkNow", "Check for Updates Now")) {
                    updater.checkForUpdates()
                }
                .buttonStyle(DustySecondaryButtonStyle())
                .disabled(!updater.canCheckForUpdates)
            }
            .padding(.leading, 50)
            .padding(.trailing, 12)
            .padding(.vertical, 9)
        }
    }

    // MARK: - Safety and about

    private var safety: some View {
        SettingsGroup(title: L10n.t("settings.section.safety", "Safety")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    IconTile(symbol: "checkmark.shield.fill", tint: DustyTheme.safe, size: 26)
                    Text(L10n.t("settings.safety.body", "Dusty uses a strict allowlist: only paths in CleanupTargetRegistry can be deleted, and never through a symlink. No sudo, no SIP-protected paths. The one system folder it can touch, /Library/Logs/DiagnosticReports, is opt-in and age-filtered."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Text(L10n.t("settings.safety.logPath", "Deletion log: ~/Library/Application Support/Dusty/"))
                        .font(.caption)
                        .foregroundStyle(DustyTheme.faint)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button(L10n.t("common.open", "Open")) { viewModel.openDeletionLog() }
                        .buttonStyle(DustySecondaryButtonStyle())
                }
                .padding(.leading, 38)
            }
            .padding(12)
        }
    }

    private var about: some View {
        VStack(spacing: 6) {
            BrandMark(size: 28)
            HStack(spacing: 4) {
                Text(L10n.t("settings.about.tagline", "Free and open source."))
                    .foregroundStyle(.secondary)
                Link(destination: URL(string: "https://github.com/yagcioglutoprak/dusty")!) {
                    Text(L10n.t("settings.about.source", "View the source"))
                }
            }
            .font(.caption)
            HStack(spacing: 3) {
                Text(L10n.t("panel.footer.madeBy", "made by"))
                    .foregroundStyle(DustyTheme.faint)
                Link(destination: URL(string: "https://toprak.sh")!) {
                    Text(verbatim: "toprak.sh")
                }
                .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}

// MARK: - Building blocks

/// A titled card of settings rows, with an optional note underneath.
private struct SettingsGroup<Content: View>: View {
    let title: String
    let footer: String?
    let content: Content

    init(title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: title)
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .dustyCard()
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(DustyTheme.faint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// One setting: icon tile, title (and caption), and its control on the right.
private struct SettingRow<Accessory: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let caption: String?
    let accessory: Accessory
    @Environment(\.isEnabled) private var isEnabled

    init(symbol: String, tint: Color, title: String, caption: String? = nil,
         @ViewBuilder accessory: () -> Accessory) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.caption = caption
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, tint: tint, size: 26)
                .saturation(isEnabled ? 1 : 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            accessory
        }
        .opacity(isEnabled ? 1 : 0.5)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(minHeight: 44)
    }
}

/// A small switch whose accessibility label is the setting's title.
private struct SettingSwitch: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(title, isOn: $isOn)
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
    }
}

/// Current value on the left, stepper arrows on the right.
private struct SettingStepper<Value: Strideable>: View {
    let title: String
    @Binding var value: Value
    let range: ClosedRange<Value>
    let step: Value.Stride
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Stepper(title, value: $value, in: range, step: step)
                .labelsHidden()
        }
    }
}
