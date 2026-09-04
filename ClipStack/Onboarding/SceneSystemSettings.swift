import SwiftUI

/// System Settings › Privacy & Security, 715×640. The ClipStack row highlights while the app is
/// waiting for the grant and its toggle animates on the moment access is detected.
struct SystemSettingsMock: View {
    enum Pane { case accessibility, screenRecording }

    let pane: Pane
    let clipStackOn: Bool
    let highlightRow: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            content
        }
        .frame(width: 715, height: 640, alignment: .topLeading)
        .background(SceneTheme.windowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(SceneTheme.separator, lineWidth: 1))
        .shadow(color: .black.opacity(0.32), radius: 30, y: 22)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            TrafficLights()
                .padding(.leading, 8)
                .padding(.bottom, 12)

            HStack {
                Text(verbatim: "Search")
                Spacer(minLength: 0)
            }
            .foregroundStyle(SceneTheme.secondaryLabel)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(SceneTheme.quaternaryFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(SceneTheme.separator, lineWidth: 1))
            .padding(.bottom, 10)

            sidebarRow("General", 0x8E8E93)
            sidebarRow("Accessibility", 0x5E5CE6)
            sidebarRow("Appearance", 0x0A84FF)
            sidebarRow("Control Center", 0x8E8E93)
            sidebarRow("Privacy & Security", 0xFFFFFF, selected: true)
            sidebarRow("Desktop & Dock", 0x1C1C1E)
            sidebarRow("Displays", 0x0A84FF)
            sidebarRow("Wallpaper", 0x30D158)

            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .foregroundStyle(SceneTheme.label)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .frame(width: 215, alignment: .leading)
        .background(SceneTheme.sidebarBackground)
    }

    private func sidebarRow(_ title: String, _ iconHex: UInt32, selected: Bool = false) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(hex: iconHex, opacity: selected ? 0.9 : 1))
                .frame(width: 20, height: 20)
            Text(verbatim: title)
            Spacer(minLength: 0)
        }
        .foregroundStyle(selected ? Color.white : SceneTheme.label)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(selected ? Color.accentColor : .clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.left")
                Image(systemName: "chevron.right")
                Text(verbatim: paneTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(SceneTheme.label)
                    .padding(.leading, 6)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(SceneTheme.secondaryLabel)

            Text(verbatim: paneDescription)
                .font(.system(size: 13))
                .foregroundStyle(SceneTheme.secondaryLabel)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)

            appList.padding(.top, 12)

            segmentedAddRemove.padding(.top, 12)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var appList: some View {
        VStack(spacing: 0) {
            appRow(name: "Terminal", icon: .flat(0x1C1C1E), on: true, animated: false, highlighted: false, emphasised: false)
            divider
            appRow(name: "ClipStack", icon: .clipStack, on: clipStackOn, animated: true, highlighted: highlightRow, emphasised: true)
            divider
            appRow(name: "Script Editor", icon: .flat(0x8E8E93), on: false, animated: false, highlighted: false, emphasised: false)
        }
        .font(.system(size: 13))
        .background(SceneTheme.control)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(SceneTheme.separator, lineWidth: 1))
    }

    private var divider: some View {
        Rectangle().fill(SceneTheme.separator).frame(height: 1).padding(.leading, 48)
    }

    private enum RowIcon { case flat(UInt32), clipStack }

    private func appRow(name: String, icon: RowIcon, on: Bool, animated: Bool, highlighted: Bool, emphasised: Bool) -> some View {
        HStack(spacing: 10) {
            Group {
                switch icon {
                case .flat(let hex):
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(hex: hex))
                case .clipStack:
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(OnboardingChrome.iconGradient)
                        .overlay(Image(systemName: "clipboard")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white))
                }
            }
            .frame(width: 26, height: 26)

            Text(verbatim: name).fontWeight(emphasised ? .semibold : .regular)
            Spacer(minLength: 0)
            SettingsToggle(isOn: on, animated: animated)
        }
        .foregroundStyle(SceneTheme.label)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(highlighted ? SceneTheme.accentWash(colorScheme) : .clear)
        .animation(.easeOut(duration: 0.3), value: highlighted)
    }

    private var segmentedAddRemove: some View {
        HStack(spacing: 1) {
            segment("+", leading: true)
            segment("−", leading: false)
        }
    }

    private func segment(_ glyph: String, leading: Bool) -> some View {
        Text(verbatim: glyph)
            .font(.system(size: 15))
            .foregroundStyle(SceneTheme.label)
            .frame(width: 28, height: 22)
            .background(SceneTheme.control)
            .clipShape(UnevenRoundedRect(topLeading: leading ? 6 : 0,
                                         topTrailing: leading ? 0 : 6,
                                         bottomLeading: leading ? 6 : 0,
                                         bottomTrailing: leading ? 0 : 6))
            .overlay(UnevenRoundedRect(topLeading: leading ? 6 : 0,
                                       topTrailing: leading ? 0 : 6,
                                       bottomLeading: leading ? 6 : 0,
                                       bottomTrailing: leading ? 0 : 6)
                .strokeBorder(SceneTheme.separator, lineWidth: 1))
    }

    private var paneTitle: String {
        pane == .screenRecording ? "Screen & System Audio Recording" : "Accessibility"
    }

    private var paneDescription: String {
        pane == .screenRecording
            ? "Allow the applications below to record the contents of your screen and audio, even while using other applications."
            : "Allow the applications below to control your computer."
    }
}

/// 38×22 with an 18 pt knob — the settings switch inside the mock, not a live control.
private struct SettingsToggle: View {
    let isOn: Bool
    let animated: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Color.accentColor : SceneTheme.tertiaryFill)
            .overlay(Capsule().strokeBorder(SceneTheme.separator, lineWidth: isOn ? 0 : 1))
            .overlay(alignment: .leading) {
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                    .frame(width: 18, height: 18)
                    .padding(.leading, 2)
                    .offset(x: isOn ? 16 : 0)
            }
            .frame(width: 38, height: 22)
            .animation(animated ? .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.25) : nil, value: isOn)
    }
}
