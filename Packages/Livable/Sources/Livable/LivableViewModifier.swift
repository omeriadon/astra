import SwiftUI

/// Astra's procedural variant: the input view supplies only its silhouette.
struct LivableViewModifier: ViewModifier {
    let palette: [Float]
    let isAnimated: Bool
    let speed: Float
    @State private var phase: Float = 0
    @State private var runningSince: Date?

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: !isAnimated)) { context in
            let time = phase + (runningSince.map { Float(max(0, context.date.timeIntervalSince($0))) * speed } ?? 0)
            let uniforms = ShaderUniforms.build(time: time)
            content.colorEffect(
                ShaderLibrary.bundle(.module).astraLivable(
                    .boundingRect, .float(time), .floatArray(uniforms), .floatArray(palette)
                )
            )
        }
        .onChange(of: isAnimated, initial: true) { _, running in
            let now = Date()
            if let start = runningSince { phase += Float(max(0, now.timeIntervalSince(start))) * speed }
            runningSince = running ? now : nil
        }
    }
}
