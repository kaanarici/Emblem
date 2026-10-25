import SwiftUI

struct DomeListening: View {
    let glass: ListeningGlass
    let source: UIImage?
    let frosted: UIImage?

    var body: some View {
        ZStack(alignment: .bottom) {
            if let source {
                glass.layer(source, reach: 48, maxOffset: CGSize(width: 24, height: 30),
                            shader: ShaderLibrary.domeRim)
            }
            if let lens = frosted ?? source {
                glass.layer(lens, reach: 40, maxOffset: CGSize(width: 16, height: 16),
                            shader: ShaderLibrary.domeLens)
                    .id(frosted == nil)
                    .transition(.opacity.animation(.easeOut(duration: 0.18)))
            }
        }
    }

    static func transcriptMask(_ frame: LiquidLensFrame) -> some View {
        Circle()
            .frame(width: frame.radius * 2, height: frame.radius * 2)
            .position(frame.center)
            .frame(width: frame.size.width, height: frame.size.height)
            .opacity(frame.progress > 0.001 ? 1 : 0)
    }
}
