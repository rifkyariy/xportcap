import SwiftUI

struct SplashView: View {
    @State private var shown = false
    @State private var fill = false
    @State private var start = Date()

    var body: some View {
        ZStack {
            TimelineView(.animation) { ctx in
                let t = Float(ctx.date.timeIntervalSince(start))
                MeshGradient(width: 3, height: 3, points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.5 + 0.18 * sin(t * 0.9), 0.5 + 0.15 * cos(t * 0.7)], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ], colors: [
                    Color(white: 0.03), Color(white: 0.06), Color(white: 0.03),
                    Color(white: 0.07), Color(white: 0.19), Color(white: 0.09),
                    Color(white: 0.03), Color(white: 0.08), Color(white: 0.03),
                ])
            }
            .ignoresSafeArea()

            VStack(spacing: 22) {
                ZStack {
                    TimelineView(.animation) { ctx in
                        Circle()
                            .strokeBorder(AngularGradient(colors: [.white, Brand.steel.opacity(0.4), .clear, .clear, .white], center: .center),
                                          lineWidth: 2)
                            .rotationEffect(.degrees(ctx.date.timeIntervalSince(start) * 120))
                    }
                    .frame(width: 200, height: 200)
                    .opacity(shown ? 0.9 : 0).scaleEffect(shown ? 1 : 0.7)
                    LogoView(size: 160)
                        .scaleEffect(shown ? 1 : 0.6)
                        .opacity(shown ? 1 : 0)
                }
                VStack(spacing: 6) {
                    Text("Xportcap")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.75)], startPoint: .top, endPoint: .bottom))
                    Text("Unlock your CapCut drafts")
                        .font(.title3).foregroundStyle(.white.opacity(0.55))
                }
                .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 14)
                .animation(.spring(duration: 0.7).delay(0.3), value: shown)

                Capsule().fill(.white.opacity(0.1)).frame(width: 160, height: 4)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Brand.gradient).frame(width: fill ? 160 : 0, height: 4)
                    }
                    .opacity(shown ? 1 : 0)
                    .animation(.easeIn.delay(0.5), value: shown)
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            start = Date()
            withAnimation(.spring(duration: 0.8, bounce: 0.35)) { shown = true }
            withAnimation(.easeInOut(duration: 1.6).delay(0.5)) { fill = true }
        }
    }
}
