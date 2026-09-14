import Foundation
import SwiftUI

struct VaultCardModifier: ViewModifier {
    struct Configuration {
        enum Style {
            case prominent
            case secondary
        }

        var style: Style
        var border: Color
        var padding: EdgeInsets = .init(all: 8)
    }

    var configuration: Configuration
    func body(content: Content) -> some View {
        content
            .padding(configuration.padding)
            .background(backgroundColor)
            .clipShape(clipShape())
            .overlay(
                clipShape()
                    .stroke(borderColor, lineWidth: 2),
            )
            .contentShape([.dragPreview], clipShape())
    }

    private var backgroundColor: Color {
        switch configuration.style {
        case .prominent: Color.accentColor
        case .secondary: Color(UIColor.secondarySystemBackground)
        }
    }

    private var borderColor: Color {
        switch configuration.style {
        case .prominent: Color.clear
        case .secondary: configuration.border.opacity(0.3)
        }
    }

    private func clipShape() -> some Shape {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }
}

#Preview {
    Text("Testing")
        .modifier(VaultCardModifier(configuration: .init(style: .secondary, border: .blue)))
}
