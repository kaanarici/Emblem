import CoreImage
import SwiftUI
import UIKit

@MainActor
enum ListeningTintClock {
    static var start = Date()
    static var offset = 0.0
    static var elapsed: Float { Float(Date().timeIntervalSince(start)) }
    static var fade: (start: Date, delay: Double, duration: Double, easeInOut: Bool)?

    static var level: Float {
        guard let fade else { return 1 }
        let t = min(1, max(0, (Date().timeIntervalSince(fade.start) - fade.delay) / fade.duration))
        let eased = fade.easeInOut ? t * t * (3 - 2 * t) : 1 - (1 - t) * (1 - t)
        return Float(1 - eased)
    }
}

struct LiquidLensFrame {
    let size: CGSize
    let progress: Double
    let breathe: Double
    let center: CGPoint
    let radius: CGFloat
    var time: Double = 0

    var apex: CGFloat { center.y - radius }
    var circle: Shader.Argument { .float3(Float(center.x), Float(center.y), Float(radius)) }

    @MainActor @ViewBuilder
    func transcriptMask(_ style: ListeningStyle) -> some View {
        switch style {
        case .wave: WaveListening.transcriptMask(self)
        case .dome: DomeListening.transcriptMask(self)
        }
    }

    func layerTop(reach: CGFloat) -> CGFloat {
        let top = max(0, min(size.height, apex - reach))
        return (top / 16).rounded(.down) * 16
    }
}

final class DomeMotion {
    private var lastTime = 0.0
    private var speech = 0.0
    private var easedSpeech = 0.0
    private var settledRadius = 0.0
    private var releaseRadius = 0.0
    private(set) var radius = 0.0

    func reset() {
        lastTime = 0
        speech = 0
        easedSpeech = 0
        settledRadius = 0
        radius = 0
    }

    func beginRelease() { releaseRadius = radius }

    func advance(now: TimeInterval, size: CGSize, sinceStart: TimeInterval,
                 sinceRelease: TimeInterval?, raw: Double, micY: CGFloat) -> LiquidLensFrame {
        let h = Double(size.height), w = Double(size.width)
        let dt = lastTime == 0 ? 1.0 / 60 : min(0.1, max(0.001, now - lastTime))
        lastTime = now

        let target = min(1, raw * 2.4)
        speech += (target - speech) * (1 - exp(-dt / (target > speech ? 1.2 : 1.0)))
        easedSpeech += (speech - easedSpeech) * (1 - exp(-dt / 0.2))

        let t = max(0, sinceStart)
        let breath = Self.breath(at: t + 0.4)
        let birthRadius = 0.38 * h
        let restRadius = h / 956 * breath.radius + 0.07 * h * easedSpeech
        if settledRadius == 0 { settledRadius = birthRadius }
        settledRadius += (restRadius - settledRadius) * (1 - exp(-dt / 0.12))

        let birth = min(1, pow(t / 0.1, 1.2))
        let blend = Self.smoothstep(0.08, 0.25, t)
        var r = birthRadius * birth * (1 - blend) + settledRadius * blend
        let restY = h + h / 956 * breath.dy
        let cy = Double(micY) + (restY - Double(micY)) * birth
        let cx = w / 2 + w / 440 * breath.dx * Self.smoothstep(0, 0.4, t)

        if let sinceRelease {
            let k = min(1, max(0, sinceRelease / 0.3))
            r = releaseRadius * (1 - k * k * k)
        }
        radius = r
        let progress = min(1, r / 40)
        return LiquidLensFrame(size: size, progress: progress, breathe: easedSpeech,
                               center: CGPoint(x: cx, y: cy), radius: r, time: t)
    }

    static func breath(at t: Double) -> (dx: Double, dy: Double, radius: Double) {
        let w0 = 2 * Double.pi / 14.05
        let s1 = sin(w0 * t), c1 = cos(w0 * t)
        let s2 = sin(2 * w0 * t), c2 = cos(2 * w0 * t)
        let s3 = sin(3 * w0 * t), c3 = cos(3 * w0 * t)
        let dx = 0.67 + 19.13 * s1 - 21.32 * c1 - 5.74 * s2 + 12.18 * c2 - 2.31 * s3 + 6.76 * c3
        let dy = 4.5 + 1.75 * s1 + 8.44 * c1 - 15.64 * s2 + 13.88 * c2 - 2.67 * s3 + 6.92 * c3
        let radius = 435.5 + 1.33 * s1 + 6.08 * c1 - 4.09 * s2 + 8.29 * c2 + 17.43 * s3 + 11.3 * c3
        return (dx, dy, radius)
    }

    static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }
}

struct LiquidLensBackdrop<Foreground: View>: View {
    let sourceImage: UIImage?
    let frosted: UIImage?
    let active: Bool
    var audioLevel: () -> Float
    let foreground: (LiquidLensFrame) -> Foreground

    @State private var activatedAt: Date?
    @State private var deactivatedAt: Date?
    @State private var motion = DomeMotion()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accent) private var accent
    @Environment(\.listeningStyle) private var style

    init(sourceImage: UIImage?, frosted: UIImage?, active: Bool,
         audioLevel: @escaping () -> Float = { 0 },
         @ViewBuilder foreground: @escaping (LiquidLensFrame) -> Foreground) {
        self.sourceImage = sourceImage
        self.frosted = frosted
        self.active = active
        self.audioLevel = audioLevel
        self.foreground = foreground
    }

    var body: some View {
        GeometryReader { proxy in
            if reduceMotion {
                layers(staticFrame(size: proxy.size, shown: active))
            } else if active || deactivatedAt != nil, let activatedAt {
                TimelineView(.animation(minimumInterval: nil, paused: false)) { timeline in
                    let now = timeline.date
                    let frame = motion.advance(
                        now: now.timeIntervalSinceReferenceDate,
                        size: proxy.size,
                        sinceStart: now.timeIntervalSince(activatedAt),
                        sinceRelease: deactivatedAt.map { now.timeIntervalSince($0) },
                        raw: Double(audioLevel()),
                        micY: proxy.size.height - 62)
                    layers(frame)
                        .onChange(of: frame.radius < 1 && deactivatedAt != nil, initial: true) { _, settled in
                            if settled && !active { deactivatedAt = nil }
                        }
                }
            } else {
                layers(staticFrame(size: proxy.size, shown: false))
            }
        }
        .ignoresSafeArea()
        .onAppear {
            if active { start() }
        }
        .onChange(of: active) { _, isActive in
            if isActive { start() } else if activatedAt != nil {
                motion.beginRelease()
                deactivatedAt = Date()
            }
        }
    }

    private func start() {
        motion.reset()
        activatedAt = Date()
        deactivatedAt = nil
    }

    private func staticFrame(size: CGSize, shown: Bool) -> LiquidLensFrame {
        LiquidLensFrame(size: size, progress: shown ? 1 : 0, breathe: 0,
                        center: CGPoint(x: size.width / 2, y: size.height + 10),
                        radius: shown ? size.height * 0.425 : 0)
    }

    private func layers(_ frame: LiquidLensFrame) -> some View {
        let glass = ListeningGlass(frame: frame, washLuma: scheme == .dark ? 0.13 : 1, accent: accent)
        return ZStack(alignment: .bottom) {
            if frame.progress > 0.001 {
                switch style {
                case .wave: WaveListening(glass: glass, source: sourceImage, frosted: frosted)
                case .dome: DomeListening(glass: glass, source: sourceImage, frosted: frosted)
                }
            }
            foreground(frame)
                .frame(width: frame.size.width, height: frame.size.height)
        }
    }
}

enum ListeningStyle: String, CaseIterable, Identifiable {
    case wave, dome

    static let storageKey = "theme.listening"

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var shaderIndex: Float { self == .wave ? 0 : 1 }
}

extension EnvironmentValues {
    @Entry var listeningStyle: ListeningStyle = .wave
}

@MainActor
struct ListeningGlass {
    let frame: LiquidLensFrame
    let washLuma: Double
    let accent: Accent

    func layer(_ image: UIImage, reach: CGFloat, maxOffset: CGSize, shader: ShaderFunction) -> some View {
        let top = frame.layerTop(reach: reach)
        return Image(uiImage: image)
            .resizable()
            .frame(width: frame.size.width, height: frame.size.height)
            .offset(y: -top)
            .frame(width: frame.size.width, height: frame.size.height - top, alignment: .top)
            .clipped()
            .layerEffect(
                shader(
                    .float2(frame.size),
                    frame.circle,
                    .float(Float(frame.progress)),
                    .float(Float(washLuma)),
                    .float(ListeningTintClock.elapsed),
                    .float(Float(ListeningTintClock.offset)),
                    .float(ListeningTintClock.level),
                    .float(Float(top)),
                    .float(Float(frame.time)),
                    .float(Float(frame.breathe)),
                    accent.washArgument),
                maxSampleOffset: maxOffset)
            .frame(width: frame.size.width, height: frame.size.height, alignment: .bottom)
            .allowsHitTesting(false)
    }
}

enum LensFrost {
    private static let context = CIContext()

    static func frost(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let downscale: CGFloat = 0.25
        let small = CIImage(cgImage: cgImage)
            .transformed(by: CGAffineTransform(scaleX: downscale, y: downscale))
        let sigma = 8 * image.scale * downscale
        let blurred = small.clampedToExtent()
            .applyingGaussianBlur(sigma: Double(sigma))
            .cropped(to: small.extent)
        guard let output = context.createCGImage(blurred, from: small.extent) else { return nil }
        return UIImage(cgImage: output, scale: image.scale * downscale, orientation: image.imageOrientation)
    }
}
