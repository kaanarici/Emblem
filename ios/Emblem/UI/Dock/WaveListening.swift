import SwiftUI

struct WaveListening: View {
    let glass: ListeningGlass
    let source: UIImage?
    let frosted: UIImage?

    var body: some View {
        ZStack(alignment: .bottom) {
            if let source {
                glass.layer(source, reach: 104, maxOffset: CGSize(width: 76, height: 56),
                            shader: ShaderLibrary.waveMeniscus)
            }
            if let lens = frosted ?? source {
                glass.layer(lens, reach: 48, maxOffset: CGSize(width: 8, height: 8),
                            shader: ShaderLibrary.waveLens)
                    .id(frosted == nil)
                    .transition(.opacity.animation(.easeOut(duration: 0.18)))
            }
        }
    }

    static func transcriptLens(_ frame: LiquidLensFrame) -> Shader {
        ShaderLibrary.waveTranscript(
            .float2(frame.size), frame.circle, .float(Float(frame.time)),
            .float(Float(frame.breathe)), .float(Float(frame.calm)), .float(Float(frame.progress)))
    }
}
