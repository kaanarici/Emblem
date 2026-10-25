import SwiftUI

struct CalendarBrowserView<Response: View>: View {
    @Bindable var selection: CalendarBrowserSelection
    @Environment(\.colorScheme) private var colorScheme
    let onMenu: () -> Void
    let onSelect: (CalendarBrowserIntent) -> Bool
    private let response: (CalendarBrowserSnapshot) -> Response
    @State private var visiblePeriod: CalendarBrowserSnapshot?
    @State private var isUserPaging = false
    @State private var anchor: CalendarBrowserDay?
    @State private var pager = CalendarPagerTrack()
    @Namespace private var highlight
    private static var reach: Int { 30 }
    private static var pageGap: CGFloat { 0 }

    init(selection: CalendarBrowserSelection, onMenu: @escaping () -> Void,
         onSelect: @escaping (CalendarBrowserIntent) -> Bool,
         @ViewBuilder response: @escaping (CalendarBrowserSnapshot) -> Response) {
        self.selection = selection
        self.onMenu = onMenu
        self.onSelect = onSelect
        self.response = response
        _visiblePeriod = State(initialValue: selection.snapshot)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                if selection.mode == .daily {
                    CalendarDayStrip(selection: selection, pager: pager,
                                     anchor: anchor ?? selection.selectedDate,
                                     reach: Self.reach, onSelect: onSelect)
                } else {
                    weeklyStrip
                }
            }
            .padding(.bottom, 50.0 / 3)
            .background {
                headerSurface.ignoresSafeArea(edges: .top)
            }
            .overlay(alignment: .bottom) {
                if colorScheme != .dark {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.white.opacity(0), .white.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 6)
                        Color.white.opacity(0.85).frame(height: 1)
                        Color.black.opacity(0.25).frame(height: 1.0 / 3)
                    }
                    .allowsHitTesting(false)
                }
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.12), radius: 16, y: 8)
            .zIndex(1)
            periodPager
        }
        .foregroundStyle(Theme.ink)
        .background(Theme.sidebarBackground)
    }

    private var periods: [CalendarBrowserSnapshot] {
        let base = anchor.flatMap { $0.date(in: selection.zone) } ?? selection.selectedInstant
        return (-Self.reach...Self.reach).compactMap { offset in
            guard let instant = selection.calendar.date(
                byAdding: selection.mode == .daily ? .day : .weekOfYear,
                value: offset, to: base),
                  let neighbor = try? CalendarBrowserSelection(
                    date: CalendarBrowserDay(date: instant, timeZone: selection.zone),
                    mode: selection.mode, timeZone: selection.timeZone) else { return nil }
            return neighbor.snapshot
        }
    }

    private var periodPager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(periods, id: \.self) { period in
                    response(period)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.horizontal, Self.pageGap / 2)
                        .containerRelativeFrame(.horizontal)
                        .visualEffect { content, proxy in
                            let travel = min(1, abs(proxy.frame(in: .scrollView(axis: .horizontal)).minX)
                                / max(1, proxy.size.width))
                            return content
                                .scaleEffect(1 - 0.045 * travel)
                                .opacity(1 - 0.18 * travel)
                        }
                        .id(period)
                }
            }
            .scrollTargetLayout()
        }
        .padding(.horizontal, -Self.pageGap / 2)
        .onScrollGeometryChange(for: CGPoint.self) { geometry in
            CGPoint(x: geometry.contentOffset.x, y: geometry.containerSize.width)
        } action: { _, value in
            guard value.y > 0 else { return }
            if !pager.tracking {
                guard abs(value.x / value.y - CGFloat(Self.reach) - selectedPage) < 0.5 else { return }
                pager.tracking = true
            }
            pager.offset = value.x
            pager.stride = value.y
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .defaultScrollAnchor(.center, for: .initialOffset)
        .scrollPosition(id: $visiblePeriod, anchor: .center)
        .accessibilityIdentifier("calendar-period-pager")
        .onScrollPhaseChange { _, phase in
            if phase == .tracking || phase == .interacting { isUserPaging = true }
            if phase == .idle && isUserPaging {
                isUserPaging = false
                selectVisiblePeriod()
            }
        }
        .onAppear {
            if anchor == nil {
                anchor = selection.selectedDate
                pager.tracking = false
            }
        }
        .onChange(of: selection.snapshot) { old, next in
            let edge = nearEdge(next)
            guard visiblePeriod != next || edge else { return }
            if old.mode == next.mode, !edge {
                withAnimation(.smooth(duration: 0.34)) { visiblePeriod = next }
            } else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    anchor = next.selectedDate
                    pager.tracking = false
                    visiblePeriod = next
                }
            }
        }
    }

    private var selectedPage: CGFloat {
        let base = anchor.flatMap { $0.date(in: selection.zone) } ?? selection.selectedInstant
        let component: Calendar.Component = selection.mode == .daily ? .day : .weekOfYear
        return CGFloat(selection.calendar.dateComponents([component], from: base, to: selection.selectedInstant)
            .value(for: component) ?? 0)
    }

    private func nearEdge(_ period: CalendarBrowserSnapshot) -> Bool {
        guard let index = periods.firstIndex(of: period) else { return true }
        return index < 3 || index > 2 * Self.reach - 3
    }

    private func selectVisiblePeriod() {
        guard let period = visiblePeriod, period != selection.snapshot,
              period.mode == selection.mode, period.timeZone == selection.timeZone else { return }
        let accepted = selection.propose({ candidate in
            if candidate.mode == .daily { return try candidate.chooseDay(period.selectedDate) }
            guard let instant = period.selectedDate.date(in: candidate.zone),
                  let days = candidate.calendar.dateComponents(
                    [.day], from: candidate.selectedInstant, to: instant).day
            else { throw CalendarBrowserSelectionError.invalidDate }
            return try candidate.chooseWeek(offset: days / 7)
        }, accepting: onSelect)
        if !accepted { visiblePeriod = selection.snapshot }
    }

    private var headerSurface: Color {
        colorScheme == .dark ? Theme.surface : Color(white: 0.98)
    }

    private var todayRed: Color {
        colorScheme == .dark ? .red : Color(.sRGB, red: 1, green: 0, blue: 0)
    }

    private var selectedPillFill: Color {
        colorScheme == .dark ? Theme.ink.opacity(0.12) : Theme.surface
    }

    private var header: some View {
        HStack(spacing: 0) {
            NavigationCircleButton(action: onMenu) { ChromeGlyph(symbol: .menu) }
                .accessibilityLabel("Menu")
            Spacer(minLength: 12)
            HStack(spacing: 16) {
                Button { selection.propose({ $0.today() }, accepting: onSelect) } label: {
                    ZStack {
                        CalendarTodayOutline().stroke(style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round)).frame(width: 24, height: 24)
                        Text(String(CalendarBrowserDay(date: .now, timeZone: selection.zone).day))
                            .font(.system(size: 11, weight: .semibold)).offset(y: 3)
                    }.frame(width: 38, height: 36)
                }
                .accessibilityLabel("Go to today")
                .accessibilityIdentifier("calendar-go-to-today")
                Menu {
                    Button { selection.propose({ $0.today() }, accepting: onSelect) } label: {
                        Label { Text("Today") } icon: { CalendarMenuGlyph.image(.today) }
                    }
                    Button { selection.propose({ $0.chooseMode(.daily) }, accepting: onSelect) } label: {
                        Label { Text("Daily") } icon: { CalendarMenuGlyph.image(.daily) }
                    }
                    Button { selection.propose({ $0.chooseMode(.weekly) }, accepting: onSelect) } label: {
                        Label { Text("Weekly") } icon: { CalendarMenuGlyph.image(.weekly) }
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 20, weight: .medium))
                        .frame(width: 38, height: 36)
                }
                .accessibilityLabel("Calendar view options")
                .accessibilityIdentifier("calendar-view-menu")
            }
            .padding(4)
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .overlay { Text("Calendar").font(.system(size: 17, weight: .semibold)).accessibilityAddTraits(.isHeader).allowsHitTesting(false) }
        .padding(.horizontal, 20).padding(.bottom, 55.0 / 3)
    }

    private var weeklyStrip: some View {
        HStack(spacing: 0) {
            ForEach(-1...1, id: \.self) { offset in
                let date = selection.calendar.date(byAdding: .weekOfYear, value: offset, to: selection.selectedInstant)!
                let interval = selection.calendar.dateInterval(of: .weekOfYear, for: date)!
                let start = CalendarBrowserDay(date: interval.start, timeZone: selection.zone)
                let last = CalendarBrowserDay(date: interval.end.addingTimeInterval(-1), timeZone: selection.zone)
                Button {
                    selection.propose({ try $0.chooseWeek(offset: offset) }, accepting: onSelect)
                } label: {
                    VStack(spacing: 5) {
                        Text("Week \(selection.calendar.component(.weekOfYear, from: date))")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(offset == 0 ? todayRed : Theme.inkSecondary)
                        Text(weekRange(start, last)).font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity).frame(height: 140.0 / 3)
                    .background {
                        if offset == 0 {
                            RoundedRectangle(cornerRadius: 16).fill(selectedPillFill)
                                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                                .matchedGeometryEffect(id: "selected-week", in: highlight)
                        }
                    }
                    .padding(.horizontal, 4)
                    .frame(height: 158.0 / 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Week of " + selection.text(start, format: "MMMM d, yyyy"))
                .accessibilityAddTraits(offset == 0 ? .isSelected : [])
                .accessibilityIdentifier("calendar-week-\(offset)")
            }
        }
    }

    private func weekRange(_ start: CalendarBrowserDay, _ last: CalendarBrowserDay) -> String {
        let tail = start.month == last.month ? String(last.day) : selection.text(last, format: "MMM d")
        return selection.text(start, format: "MMM d") + "–" + tail
    }
}

private struct CalendarTodayOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 16, y: 2))
        path.addLine(to: CGPoint(x: 16, y: 6))
        path.move(to: CGPoint(x: 8, y: 2))
        path.addLine(to: CGPoint(x: 8, y: 6))
        path.move(to: CGPoint(x: 13, y: 4))
        path.addLine(to: CGPoint(x: 11, y: 4))
        path.addCurve(to: CGPoint(x: 4.17157, y: 5.17157), control1: CGPoint(x: 7.22876, y: 4), control2: CGPoint(x: 5.34315, y: 4))
        path.addCurve(to: CGPoint(x: 3, y: 12), control1: CGPoint(x: 3, y: 6.34315), control2: CGPoint(x: 3, y: 8.22876))
        path.addLine(to: CGPoint(x: 3, y: 14))
        path.addCurve(to: CGPoint(x: 4.17157, y: 20.8284), control1: CGPoint(x: 3, y: 17.7712), control2: CGPoint(x: 3, y: 19.6569))
        path.addCurve(to: CGPoint(x: 11, y: 22), control1: CGPoint(x: 5.34315, y: 22), control2: CGPoint(x: 7.22876, y: 22))
        path.addLine(to: CGPoint(x: 13, y: 22))
        path.addCurve(to: CGPoint(x: 19.8284, y: 20.8284), control1: CGPoint(x: 16.7712, y: 22), control2: CGPoint(x: 18.6569, y: 22))
        path.addCurve(to: CGPoint(x: 21, y: 14), control1: CGPoint(x: 21, y: 19.6569), control2: CGPoint(x: 21, y: 17.7712))
        path.addLine(to: CGPoint(x: 21, y: 12))
        path.addCurve(to: CGPoint(x: 19.8284, y: 5.17157), control1: CGPoint(x: 21, y: 8.22876), control2: CGPoint(x: 21, y: 6.34315))
        path.addCurve(to: CGPoint(x: 13, y: 4), control1: CGPoint(x: 18.6569, y: 4), control2: CGPoint(x: 16.7712, y: 4))
        path.closeSubpath()
        path.move(to: CGPoint(x: 3, y: 10))
        path.addLine(to: CGPoint(x: 21, y: 10))
        return path.applying(CGAffineTransform(a: rect.width / 24, b: 0, c: 0, d: rect.height / 24, tx: rect.minX, ty: rect.minY))
    }
}

private enum CalendarMenuGlyph {
    enum Kind { case today, daily, weekly }

    @MainActor static func image(_ kind: Kind) -> Image {
        let renderer = ImageRenderer(content: Outline(kind: kind)
            .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            .overlay { if kind == .weekly { Bar() } }
            .frame(width: 19, height: 19).padding(0.8))
        renderer.scale = 3
        guard let image = renderer.uiImage else { return Image(systemName: "calendar") }
        return Image(uiImage: image.withRenderingMode(.alwaysTemplate))
    }

    private struct Bar: View {
        var body: some View {
            GeometryReader { proxy in
                Capsule().frame(width: proxy.size.width * 0.58, height: 2.4)
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.62)
            }
        }
    }

    private struct Outline: Shape {
        let kind: Kind
        func path(in rect: CGRect) -> Path {
            var path = Path(roundedRect: rect, cornerRadius: rect.width * 0.27, style: .continuous)
            let header = rect.minY + rect.height * 0.3
            path.move(to: CGPoint(x: rect.minX, y: header))
            path.addLine(to: CGPoint(x: rect.maxX, y: header))
            if kind == .daily {
                let x = rect.minX + rect.width * 0.76
                path.move(to: CGPoint(x: x, y: rect.minY + rect.height * 0.56))
                path.addLine(to: CGPoint(x: x, y: rect.minY + rect.height * 0.7))
            }
            return path
        }
    }
}
