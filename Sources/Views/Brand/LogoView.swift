import SwiftUI

struct LogoView: View {
    var size: CGFloat = 128

    var body: some View {
        // one tile, one glyph
        RoundedRectangle(cornerRadius: size * 0.185, style: .continuous)
            .fill(Color(white: 0.09))
            .overlay {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: size * 0.82, height: size * 0.82)  // macOS icon grid: art inset within the canvas
            .shadow(color: .black.opacity(0.3), radius: size * 0.025, y: size * 0.015)
            .frame(width: size, height: size)
    }
}
