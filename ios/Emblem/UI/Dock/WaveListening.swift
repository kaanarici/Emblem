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
            if let frosted {
                glass.layer(frosted, reach: 48, maxOffset: CGSize(width: 8, height: 8),
                            shader: ShaderLibrary.waveLens)
            }
        }
    }

    static func transcriptMask(_ frame: LiquidLensFrame) -> some View {
        Rectangle()
            .fill(.white)
            .colorEffect(ShaderLibrary.waveTranscriptMask(
                .float2(frame.size), frame.circle, .float(Float(frame.time)),
                .float(Float(frame.breathe)), .float(Float(frame.progress))))
    }
}
