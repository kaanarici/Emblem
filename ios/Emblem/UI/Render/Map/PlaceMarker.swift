import SwiftUI
import MapKit
import CoreLocation
import EmblemCore

struct MapCardShape: ViewModifier {
    let thin: Bool

    func body(content: Content) -> some View {
        if thin {
            content.frame(maxWidth: .infinity).frame(height: 80)
        } else {
            content.aspectRatio(1, contentMode: .fit)
        }
    }
}

struct ListViewMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for y in [rect.minY + 0.75, rect.midY, rect.maxY - 0.75] {
            path.move(to: CGPoint(x: rect.minX + 0.75, y: y))
            path.addLine(to: CGPoint(x: rect.maxX - 0.75, y: y))
        }
        return path
    }
}

struct PlaceDot: View {
    var body: some View {
        Circle().fill(markerOrange)
            .frame(width: 9, height: 9)
            .padding(2)
            .background(Circle().fill(.white))
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            .frame(width: 30, height: 30)
            .contentShape(Circle())
    }
}

extension PlaceMapLayout {
    init(_ pins: [MapBlockViewModel.Pin], at points: [String: CGPoint], selectedID: String?) {
        self.init(pins.map { Entry(id: $0.id, name: $0.place.displayName, category: $0.place.category) },
                  at: points, selectedID: selectedID)
    }
}

enum PlaceMarkerArtwork {
    case card(CardCarousel.Card)
    case object(Icon)
}

struct PlaceMarker: View {
    let name: String
    let category: String?
    let icon: Icon?
    let artwork: PlaceMarkerArtwork?
    let selected: Bool
    let showsLabel: Bool
    var role: PlaceMapLayout.Role = .marker
    var absorbed = 0
    var balloonDiameter = PlaceMapLayout.balloonDiameter
    var labelScale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var diameter: CGFloat { selected ? balloonDiameter : PlaceMapLayout.markerDiameter }
    private var tail: CGFloat { selected ? PlaceMapLayout.balloonTail : 0 }
    private var centerY: CGFloat { selected ? -(tail + diameter / 2) : 0 }
    private var clusterCount: Int? { if case .cluster(let count) = role { count } else { nil } }
    private var hidden: Bool { role == .hidden && !selected }

    var body: some View {
        ZStack {
            ZStack {
                BalloonTail()
                    .fill(Theme.surface)
                    .frame(width: 18, height: max(tail + 4, 0.1))
                    .offset(y: diameter / 2 + tail / 2 - 2)
                    .opacity(selected ? 1 : 0)
                Circle().fill(selected ? Theme.surface : .white)
                    .frame(width: diameter, height: diameter)
                ZStack {
                    Circle().fill(markerOrange).opacity(selected && artwork != nil ? 0 : 1)
                    glyph.opacity(selected || clusterCount != nil ? 0 : 1)
                    Text("\(clusterCount ?? absorbed + 1)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .opacity(selected || clusterCount == nil ? 0 : 1)
                    switch artwork {
                    case .card(let card):
                        CardArtworkView(card: card, maxPixelSize: 400)
                            .clipShape(Circle())
                            .opacity(selected ? 1 : 0)
                    case .object(let object):
                        Color.clear.overlay {
                            IconView(icon: object, size: balloonDiameter * 0.68)
                                .scaleEffect(selected ? 1 : 0.4)
                                .opacity(selected ? 1 : 0)
                        }
                    case nil:
                        EmptyView()
                    }
                }
                .frame(width: diameter - (selected ? 8 : 4), height: diameter - (selected ? 8 : 4))
                if selected, absorbed > 0 {
                    Text("+\(absorbed)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Capsule().fill(markerOrange))
                        .background(Capsule().inset(by: -1.5).fill(Theme.surface))
                        .offset(x: diameter * 0.36, y: -diameter * 0.36)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .compositingGroup()
            .shadow(color: .black.opacity(selected ? 0.2 : 0.16), radius: selected ? 6 : 2.5, y: selected ? 2 : 1)
            .contentShape(Circle().scale(selected ? 1.2 : 1.4))
            .offset(y: centerY)
            label
                .opacity(showsLabel || selected ? 1 : 0)
                .scaleEffect((selected ? PlaceMapLayout.selectedLabelScale : 1) * labelScale, anchor: .top)
                .frame(width: 140, height: 44, alignment: .top)
                .offset(y: (selected ? 3 : diameter / 2 + 3) + 22)
                .allowsHitTesting(false)
        }
        .frame(width: 140, height: 190)
        .scaleEffect(hidden ? 0.4 : 1)
        .opacity(hidden ? 0 : 1)
        .animation(reduceMotion ? .easeOut(duration: 0.16) : .spring(duration: 0.36, bounce: 0.14), value: selected)
        .animation(.easeOut(duration: 0.2), value: role)
        .animation(.easeOut(duration: 0.16), value: showsLabel)
        .frame(width: hidden ? 0 : 44, height: hidden ? 0 : 44)
        .allowsHitTesting(!hidden)
        .accessibilityHidden(hidden)
    }

    private var pinSymbol: String {
        let symbol = icon?.sfSymbol ?? "mappin"
        return symbol.hasPrefix("bed") || symbol == "building" || symbol.hasPrefix("building.2") ? "hotel" : symbol
    }

    @ViewBuilder private var glyph: some View {
        if let emoji = icon?.emoji, icon?.sfSymbol == nil {
            Text(emoji).font(.system(size: 15))
        } else {
            GlyphImage(symbol: pinSymbol, size: 15, weight: .regular)
                .foregroundStyle(.white)
        }
    }

    private var label: some View {
        VStack(spacing: 0) {
            Text(name).font(Font(PlaceMapLayout.nameFont)).lineLimit(2)
            if let category { Text(category).font(Font(PlaceMapLayout.categoryFont)).lineLimit(1) }
        }
        .foregroundStyle(Theme.ink)
        .multilineTextAlignment(.center)
        .frame(maxWidth: PlaceMapLayout.labelWidth)
        .shadow(color: Theme.responsePaper, radius: 0.6)
        .shadow(color: Theme.responsePaper, radius: 1.2)
        .shadow(color: Theme.responsePaper, radius: 2)
    }
}

extension PlaceMarker {
    init(pin: MapBlockViewModel.Pin, card: CardCarousel.Card?, selected: Bool, showsLabel: Bool,
         role: PlaceMapLayout.Role = .marker, absorbed: Int = 0) {
        self.init(name: pin.place.displayName, category: pin.place.category, icon: pin.place.icon,
                  artwork: card.map { .card($0) }, selected: selected, showsLabel: showsLabel,
                  role: role, absorbed: absorbed)
    }
}

private struct BalloonTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.midX + 1.5, y: rect.maxY - 1),
                          control: CGPoint(x: rect.midX + 3, y: rect.midY))
        path.addQuadCurve(to: CGPoint(x: rect.midX - 1.5, y: rect.maxY - 1),
                          control: CGPoint(x: rect.midX, y: rect.maxY + 0.5))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY),
                          control: CGPoint(x: rect.midX - 3, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

extension MKCoordinateRegion {
    func stripCrop(latitude: Double) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: center.longitude),
            span: MKCoordinateSpan(latitudeDelta: span.latitudeDelta * 0.01, longitudeDelta: span.longitudeDelta * 3.4))
    }
}
