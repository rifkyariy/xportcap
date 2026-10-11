import SwiftUI
import AppKit

struct Cover: View {
    let url: URL?

    /// Decoded once per launch: re-decoding on every layout pass made the sidebar animation flicker.
    private static let cache = NSCache<NSURL, NSImage>()

    private var image: NSImage? {
        guard let url else { return nil }
        if let img = Self.cache.object(forKey: url as NSURL) { return img }
        guard let img = NSImage(contentsOf: url) else { return nil }
        Self.cache.setObject(img, forKey: url as NSURL)
        return img
    }

    var body: some View {
        if let image {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                LinearGradient(colors: [Color(white: 0.16), Color(white: 0.07)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "film").font(.title2).foregroundStyle(Brand.gradient)
            }
        }
    }
}
