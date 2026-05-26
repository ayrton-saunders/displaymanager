import SwiftUI
import AppKit

/// SwiftUI rendering for one menu row, styled like a Control Center entry: an
/// icon tile (accent-filled when active, faint when not) beside the title, with
/// a soft full-row highlight on hover. Stateless — all state is passed in.
struct DisplayMenuRow: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let isEnabled: Bool
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(iconBackground)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(iconForeground)
            }
            .frame(width: 28, height: 28)

            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(isEnabled ? Color.primary : Color.primary.opacity(0.35))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity((isHovered && isEnabled) ? 0.12 : 0))
                .padding(.horizontal, 5)
        )
        .contentShape(Rectangle())
    }

    private var iconForeground: Color {
        if !isEnabled { return Color.primary.opacity(0.3) }
        return isSelected ? Color.white : Color.primary.opacity(0.9)
    }

    private var iconBackground: Color {
        if !isEnabled { return Color.primary.opacity(0.05) }
        return isSelected ? Color.accentColor : Color.primary.opacity(0.1)
    }
}

/// Hosts a `DisplayMenuRow` as an `NSMenuItem.view`. NSMenu doesn't highlight
/// custom-view items or forward clicks to embedded SwiftUI controls during its
/// tracking loop, so this NSView owns the interaction: a tracking area drives
/// the hover highlight, and `mouseUp` activates the row and dismisses the menu.
final class MenuRowItemView: NSView {
    private let icon: String
    private let title: String
    private let onSelect: () -> Void
    private let hostingView: NSHostingView<DisplayMenuRow>

    var isSelected = false { didSet { refresh() } }
    var isRowEnabled = true { didSet { refresh() } }
    private var isHovered = false { didSet { refresh() } }

    init(icon: String, title: String, width: CGFloat, onSelect: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.onSelect = onSelect
        self.hostingView = NSHostingView(rootView: DisplayMenuRow(
            icon: icon, title: title, isSelected: false, isEnabled: true, isHovered: false
        ))
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 34))

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func refresh() {
        hostingView.rootView = DisplayMenuRow(
            icon: icon, title: title,
            isSelected: isSelected, isEnabled: isRowEnabled, isHovered: isHovered
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { if isRowEnabled { isHovered = true } }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func mouseUp(with event: NSEvent) {
        guard isRowEnabled else { return }
        isHovered = false
        enclosingMenuItem?.menu?.cancelTracking()
        onSelect()
    }
}
