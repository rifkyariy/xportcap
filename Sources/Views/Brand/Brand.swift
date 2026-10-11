import SwiftUI

enum Brand {  // graphite + silver; UI highlights follow the system accent colour
    static let silver = Color(white: 0.92)
    static let steel = Color(white: 0.62)
    static let gradient = LinearGradient(colors: [.white, silver, steel], startPoint: .topLeading, endPoint: .bottomTrailing)
}
