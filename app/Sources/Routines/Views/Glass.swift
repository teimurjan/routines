import SwiftUI

extension View {
    /// Liquid Glass on macOS 26, and a thin material on older systems.
    /// A frosted surface adds a material and a shade under the content, so the background blurs more and the glass is darker.
    @ViewBuilder
    func glassSurface<S: InsettableShape>(_ shape: S, interactive: Bool = false, frosted: Bool = false) -> some View {
        let content = frost(frosted, in: shape)
        if #available(macOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Theme.cardBorder))
                .shadow(Tokens.Shadow.float)
        }
    }

    @ViewBuilder
    private func frost<S: Shape>(_ on: Bool, in shape: S) -> some View {
        if on {
            background(Theme.glassDim, in: shape).background(.thinMaterial, in: shape)
        } else {
            self
        }
    }

    /// Two views with the same id in one `GlassGroup` morph into each other.
    @ViewBuilder
    func glassID(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(macOS 26.0, *) {
            glassEffectID(id, in: namespace)
        } else {
            self
        }
    }
}

/// Lets the glass shapes inside it blend and morph on macOS 26.
struct GlassGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer { content }
        } else {
            content
        }
    }
}

/// A short sweep of light over the view, for text that waits on the agent.
struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -0.6

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geometry in
                    LinearGradient(colors: [.clear, Theme.text, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geometry.size.width * 0.5)
                        .offset(x: phase * geometry.size.width)
                }
                .mask(content)
                .allowsHitTesting(false)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { phase = 1.1 }
            }
    }
}
