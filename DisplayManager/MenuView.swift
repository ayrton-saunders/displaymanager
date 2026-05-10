import SwiftUI

struct MenuView: View {
    @StateObject private var displayManager = DisplayManager()
    var closeAction: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Current mode status - styled like native menu section header
            HStack(spacing: 6) {
                Image(systemName: displayManager.currentMode == .mirrored ? "rectangle.on.rectangle" : 
                               displayManager.currentMode == .extended ? "rectangle.split.2x1" : "questionmark.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.7))
                Text(displayManager.currentMode == .mirrored ? "Mirrored" :
                     displayManager.currentMode == .extended ? "Extended" : "Unknown")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.7))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 5)
            .padding(.bottom, 4)
            
            Divider()
                .background(Color.primary.opacity(0.08))
            
            // Mirrored Mode Button
            MenuItemButton(
                icon: "rectangle.on.rectangle",
                title: "Mirrored Mode",
                isSelected: displayManager.currentMode == .mirrored,
                action: {
                    displayManager.setMirroredMode()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        closeAction()
                    }
                }
            )
            .padding(.top, 2)
            
            // Extended Mode Button
            MenuItemButton(
                icon: "rectangle.split.2x1",
                title: "Extended Mode",
                isSelected: displayManager.currentMode == .extended,
                action: {
                    displayManager.setExtendedMode()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        closeAction()
                    }
                }
            )
            
            Divider()
                .background(Color.primary.opacity(0.08))
                .padding(.vertical, 2)
            
            // Quit Button
            MenuItemButton(
                icon: "power",
                title: "Quit",
                isSelected: false,
                action: {
                    NSApplication.shared.terminate(nil)
                }
            )
            .padding(.bottom, 2)
        }
        .frame(width: 200)
        .background(
            VisualEffectView(material: .menu, blendingMode: .behindWindow)
        )
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.25), Color.white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
        .shadow(color: Color.black.opacity(0.28), radius: 12, x: 0, y: 4)
        .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
    }
}

struct MenuItemButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 16)
                    .foregroundColor(isHovered ? .primary : .primary.opacity(0.85))
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(isHovered ? .primary : .primary.opacity(0.95))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        isHovered ?
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.18), Color.accentColor.opacity(0.14)],
                                startPoint: .top,
                                endPoint: .bottom
                            ) :
                            LinearGradient(
                                colors: [Color.clear, Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                    )
            )
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 6
        view.layer?.masksToBounds = true

        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
