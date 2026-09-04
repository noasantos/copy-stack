import SwiftUI

/// 37 pt, transparent. The leading zone ends before x 663 and the trailing zone starts after x 849,
/// so nothing ever sits under the camera housing. Reports the status item's midX to the scene.
struct MenuBarMock: View {
    let appName: String
    let statusItemHighlighted: Bool

    var body: some View {
        HStack(spacing: 0) {
            leading.frame(maxWidth: 620, alignment: .leading)
            Spacer(minLength: 0)
            trailing.frame(maxWidth: 640, alignment: .trailing)
        }
        .font(.system(size: 13.5))
        .foregroundStyle(SceneTheme.menuBarForeground)
        .shadow(color: menuBarShadow, radius: 1, y: 1)
        .padding(.horizontal, 18)
        .frame(width: DemoGeometry.screen.width, height: 37)
    }

    @Environment(\.colorScheme) private var colorScheme

    private var menuBarShadow: Color {
        colorScheme == .dark ? .black.opacity(0.35) : .clear
    }

    private var leading: some View {
        HStack(spacing: 22) {
            Image(systemName: "apple.logo").font(.system(size: 14))
            Text(appName).fontWeight(.bold)
            Text(verbatim: "File")
            Text(verbatim: "Edit")
            Text(verbatim: "View")
            Text(verbatim: "Window")
            Text(verbatim: "Help")
        }
        .fixedSize()
    }

    private var trailing: some View {
        HStack(spacing: 18) {
            statusItem
            Image(systemName: "wifi").font(.system(size: 14))
            Image(systemName: "battery.75").font(.system(size: 15))
            Text(verbatim: "Thu Sep 4  10:52 AM").fontWeight(.medium)
        }
        .fixedSize()
    }

    private var statusItem: some View {
        Image(systemName: "clipboard")
            .font(.system(size: 15))
            .frame(width: 30, height: 24)
            .background(statusItemHighlighted ? SceneTheme.menuBarHighlight : .clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .animation(.easeOut(duration: 0.15), value: statusItemHighlighted)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: StatusItemMidXPreference.self,
                                           value: proxy.frame(in: .named(DemoGeometry.spaceName)).midX)
                }
            }
    }
}
