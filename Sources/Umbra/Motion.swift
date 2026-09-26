import SwiftUI

/// One motion language for the whole app: springs with a tiny overshoot at most,
/// and content that swaps with a short blur while its container morphs.
extension Animation {
    /// Default UI spring. Damping 0.88 matches `Spring` in Spring.swift (about 0.3% overshoot).
    static let umbra = Animation.spring(response: 0.38, dampingFraction: 0.88)
    /// Faster spring for small things like a selection pill.
    static let umbraQuick = Animation.spring(response: 0.28, dampingFraction: 0.9)
}

private struct BlurFade: ViewModifier {
    let radius: CGFloat
    let opacity: Double
    let scale: CGFloat
    func body(content: Content) -> some View {
        content.blur(radius: radius).opacity(opacity).scaleEffect(scale)
    }
}

extension AnyTransition {
    /// Content swap: the old content blurs out while the new one sharpens in.
    static let blurSwap = AnyTransition.modifier(
        active: BlurFade(radius: 6, opacity: 0, scale: 0.97),
        identity: BlurFade(radius: 0, opacity: 1, scale: 1)
    )

    /// A row that grows out of the card above it.
    static let blurReveal = AnyTransition.blurSwap.combined(with: .move(edge: .top))
}

/// Segmented control where the selection is one pill that morphs between segments.
struct ModePicker: View {
    let selection: AdaptiveMode
    let onSelect: (AdaptiveMode) -> Void
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AdaptiveMode.allCases) { m in
                let on = m == selection
                Button { onSelect(m) } label: {
                    Text(m.label)
                        .font(.system(size: 12, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                    .shadow(color: .black.opacity(0.12), radius: 1.5, y: 0.5)
                                    .matchedGeometryEffect(id: "pill", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(m.label)
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(.umbraQuick, value: selection)
    }
}
