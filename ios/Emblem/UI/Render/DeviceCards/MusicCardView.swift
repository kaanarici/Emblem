import AVFoundation
import MediaPlayer
import SwiftUI
import EmblemCore

@Observable @MainActor
final class MusicPreviewPlayer {
    static let shared = MusicPreviewPlayer()

    private(set) var playing: URL?
    private(set) var progress: Double = 0
    private var player: AVPlayer?
    private var observer: Any?
    private var endObserver: NSObjectProtocol?

    func toggle(_ url: URL) {
        if playing == url {
            stop()
            return
        }
        stop()
        VoiceOutput.shared.stop()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        let player = AVPlayer(url: url)
        observer = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, let duration = self.player?.currentItem?.duration.seconds,
                      duration.isFinite, duration > 0 else { return }
                self.progress = time.seconds / duration
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: player.currentItem, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        self.player = player
        playing = url
        progress = 0
        player.play()
    }

    func stop() {
        if let observer { player?.removeTimeObserver(observer) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        observer = nil
        endObserver = nil
        player?.pause()
        player = nil
        guard playing != nil else { return }
        playing = nil
        progress = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

struct MusicCardView: View {
    let block: MusicBlock
    @Environment(\.blockInteraction) private var blockInteraction
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    private let player = MusicPreviewPlayer.shared

    var body: some View {
        VStack(spacing: 12) {
            if let title = block.title, !title.isEmpty {
                Text(title)
                    .font(Theme.cardTitle())
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 5.5) {
                ForEach(Array(block.tracks.enumerated()), id: \.offset) { index, track in
                    row(track)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(GroupedRowShape(index: index, count: block.tracks.count).fill(Theme.rowFill))
                }
            }
            .groupedRowShadow()
        }
        .padding(.horizontal, 28)
    }

    private func row(_ track: MusicBlock.Track) -> some View {
        let isPlaying = track.preview != nil && player.playing == track.preview
        return HStack(spacing: 12) {
            Button {
                guard blockInteraction.allowsActivation, let preview = track.preview else { return }
                player.toggle(preview)
            } label: {
                MusicArtwork(url: track.art)
                    .overlay {
                        if track.preview != nil {
                            ZStack {
                                Circle().fill(.black.opacity(0.35)).frame(width: 30, height: 30)
                                if isPlaying {
                                    Circle().trim(from: 0, to: player.progress)
                                        .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                        .frame(width: 30, height: 30)
                                }
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                        }
                    }
            }
            .buttonStyle(.pressable)
            .blockActivationControl()
            .disabled(track.preview == nil)
            .accessibilityLabel(isPlaying ? "Pause preview of \(track.name)" : "Play preview of \(track.name)")
            .accessibilityIdentifier("music-preview")

            VStack(alignment: .leading, spacing: 3) {
                Text(track.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text([track.artist, track.album].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                if let id = storeID(track), DeviceAccess.shared.canUse(.music) {
                    Button("Play in Apple Music", systemImage: "play.fill") {
                        player.stop()
                        let music = MPMusicPlayerController.systemMusicPlayer
                        music.setQueue(with: [id])
                        music.play()
                    }
                }
                if let url = track.url {
                    Button("Open in Apple Music", systemImage: "music.note") { openURL(url) }
                }
                if let spotify = spotifySearch(track) {
                    Button("Open in Spotify", systemImage: "arrow.up.right") { openURL(spotify) }
                }
            } label: {
                HStack(spacing: 6) {
                    ConnectorLogo(slug: "applemusic", size: 18)
                    Text("Open")
                }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 11)
                    .frame(minWidth: 56, minHeight: 36)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.rowButtonStroke, lineWidth: 1.2))
            }
            .blockActivationControl()
            .accessibilityLabel("Open \(track.name)")
        }
        .onDisappear {
            if isPlaying { player.stop() }
        }
    }

    private func storeID(_ track: MusicBlock.Track) -> String? {
        guard let url = track.url else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "i" }?.value
    }

    private func spotifySearch(_ track: MusicBlock.Track) -> URL? {
        var components = URLComponents(string: "https://open.spotify.com/search")
        components?.path += "/" + "\(track.name) \(track.artist)"
        return components?.url
    }
}

private struct MusicArtwork: View {
    let url: URL?
    @State private var image: UIImage?
    @State private var settled = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        ZStack {
            shape.fill(Theme.chip)
            if let image {
                Image(uiImage: image).resizable().scaledToFill().transition(.imageArrival)
            } else if url == nil || settled {
                Image(systemName: "music.note").font(.system(size: 20)).foregroundStyle(Theme.inkSecondary)
            } else {
                ShimmerTile()
            }
        }
        .frame(width: 54, height: 54)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.black.opacity(0.06), lineWidth: 0.5))
        .task(id: url) {
            guard let url, image == nil else { return }
            let loaded = await ImageLoader.shared.image(at: url, maxPixelSize: 180)
            guard !Task.isCancelled else { return }
            withAnimation(.imageArrival) {
                image = loaded
                settled = true
            }
        }
    }
}
