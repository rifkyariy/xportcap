import SwiftUI

extension View {
    /// macOS 26 lets scrolling content show through the toolbar and window buttons; give it a solid edge.
    @ViewBuilder func solidTopEdge() -> some View {
        if #available(macOS 26, *) { scrollEdgeEffectStyle(.hard, for: .top) } else { self }
    }
}
