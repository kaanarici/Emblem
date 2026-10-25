import Contacts
import CoreLocation
import EventKit
#if EMBLEM_HOMEKIT
import HomeKit
#endif
import MusicKit
import Observation
import UIKit
import EmblemCore

@Observable @MainActor
final class DeviceAccess: NSObject, CLLocationManagerDelegate {
    static let shared = DeviceAccess()

    enum Kind: String, CaseIterable, Identifiable {
        case location, calendar, reminders, contacts, home, music
        var id: String { rawValue }

        static var available: [Kind] {
            #if EMBLEM_HOMEKIT
            allCases
            #else
            allCases.filter { $0 != .home }
            #endif
        }
    }

    enum State: Equatable {
        case notAsked
        case allowed
        case limited
        case addOnly
        case denied
    }

    private(set) var states: [Kind: State] = [:]
    private(set) var requesting: Kind?
    private var answered: [Kind: Bool] = [:]
    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
        for kind in Kind.allCases {
            UserDefaults.standard.removeObject(forKey: "device.off.\(kind.rawValue)")
        }
        refresh()
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in DeviceAccess.shared.refresh() }
        }
    }

    func state(_ kind: Kind) -> State { states[kind] ?? .notAsked }

    func canUse(_ kind: Kind) -> Bool {
        let state = state(kind)
        return state == .allowed || state == .limited
    }

    nonisolated static var advertisedSources: [String]? {
        #if EMBLEM_HOMEKIT
        ["home"]
        #else
        nil
        #endif
    }

    func refresh() {
        for kind in Kind.allCases {
            var system = systemState(kind)
            if system == .notAsked, let answer = answered[kind] { system = answer ? .allowed : .denied }
            states[kind] = system
        }
    }

    func request(_ kind: Kind) async {
        guard requesting == nil else { return }
        switch state(kind) {
        case .allowed, .limited, .denied:
            openSettings()
            return
        case .notAsked, .addOnly:
            break
        }
        requesting = kind
        defer {
            requesting = nil
            refresh()
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                refresh()
            }
        }
        switch kind {
        case .location:
            locationManager.requestWhenInUseAuthorization()
        case .calendar:
            answered[kind] = (try? await EKEventStore().requestFullAccessToEvents()) ?? false
        case .reminders:
            answered[kind] = await RemindersService.shared.requestAccess()
        case .contacts:
            _ = try? await CNContactStore().requestAccess(for: .contacts)
        case .home:
            #if EMBLEM_HOMEKIT
            await HomeService.shared.requestAccess()
            #endif
        case .music:
            _ = await MusicAuthorization.request()
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func systemState(_ kind: Kind) -> State {
        switch kind {
        case .location:
            switch locationManager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse: return .allowed
            case .denied, .restricted: return .denied
            default: return .notAsked
            }
        case .calendar:
            return Self.eventKitState(.event)
        case .reminders:
            return Self.eventKitState(.reminder)
        case .contacts:
            switch CNContactStore.authorizationStatus(for: .contacts) {
            case .authorized: return .allowed
            case .limited: return .limited
            case .denied, .restricted: return .denied
            default: return .notAsked
            }
        case .home:
            #if EMBLEM_HOMEKIT
            return HomeService.shared.systemState
            #else
            return .notAsked
            #endif
        case .music:
            switch MusicAuthorization.currentStatus {
            case .authorized: return .allowed
            case .denied, .restricted: return .denied
            default: return .notAsked
            }
        }
    }

    private static func eventKitState(_ entity: EKEntityType) -> State {
        switch EKEventStore.authorizationStatus(for: entity) {
        case .fullAccess: .allowed
        case .writeOnly: .addOnly
        case .denied, .restricted: .denied
        default: .notAsked
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.refresh() }
    }
}

@MainActor
final class RemindersService {
    static let shared = RemindersService()

    struct Item: Identifiable, Hashable, Sendable {
        var id: String
        var title: String
        var due: Date?
        var list: String
        var done = false
    }

    private let store = EKEventStore()

    var isAllowed: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToReminders()) ?? false
    }

    func fetch(scope: RemindersBlock.Scope, list: String?) async -> [Item] {
        guard isAllowed else { return [] }
        let calendars = store.calendars(for: .reminder).filter { calendar in
            guard let list, !list.isEmpty else { return true }
            return calendar.title.localizedCaseInsensitiveCompare(list) == .orderedSame
        }
        guard !calendars.isEmpty else { return [] }
        let dayStart = Calendar.current.startOfDay(for: Date())
        let end: Date? = switch scope {
        case .today: Calendar.current.date(byAdding: .day, value: 1, to: dayStart)
        case .upcoming: Calendar.current.date(byAdding: .day, value: 8, to: dayStart)
        case .all: nil
        }
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: end, calendars: calendars)
        let items: [Item] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let items = (reminders ?? []).prefix(40).map { reminder in
                    Item(
                        id: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "",
                        due: reminder.dueDateComponents?.date,
                        list: reminder.calendar?.title ?? "")
                }
                continuation.resume(returning: Array(items))
            }
        }
        return items.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }

    func setDone(_ id: String, _ done: Bool) -> Bool {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return false }
        reminder.isCompleted = done
        return (try? store.save(reminder, commit: true)) != nil
    }

    func add(_ title: String, list: String?, dueToday: Bool) -> Item? {
        guard isAllowed else { return nil }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = store.calendars(for: .reminder).first {
            $0.title.localizedCaseInsensitiveCompare(list ?? "") == .orderedSame
        } ?? store.defaultCalendarForNewReminders()
        if dueToday {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day], from: Date())
        }
        guard reminder.calendar != nil, (try? store.save(reminder, commit: true)) != nil else { return nil }
        return Item(id: reminder.calendarItemIdentifier, title: title,
                    due: reminder.dueDateComponents?.date, list: reminder.calendar.title)
    }
}

enum ContactsService {
    struct Match: Identifiable, Hashable, Sendable {
        struct Channel: Hashable, Sendable {
            var label: String
            var value: String
        }
        var id: String
        var name: String
        var phones: [Channel]
        var emails: [Channel]
        var thumbnail: Data?
    }

    static func lookup(_ name: String) async -> [Match] {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status == .authorized || status == .limited else { return [] }
        return await Task.detached(priority: .userInitiated) {
            let keys: [CNKeyDescriptor] = [
                CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                CNContactPhoneNumbersKey as CNKeyDescriptor,
                CNContactEmailAddressesKey as CNKeyDescriptor,
                CNContactThumbnailImageDataKey as CNKeyDescriptor,
            ]
            let contacts = (try? CNContactStore().unifiedContacts(
                matching: CNContact.predicateForContacts(matchingName: name),
                keysToFetch: keys)) ?? []
            return contacts.prefix(3).map { contact in
                Match(
                    id: contact.identifier,
                    name: CNContactFormatter.string(from: contact, style: .fullName) ?? name,
                    phones: contact.phoneNumbers.map {
                        Match.Channel(label: Self.label($0.label), value: $0.value.stringValue)
                    },
                    emails: contact.emailAddresses.map {
                        Match.Channel(label: Self.label($0.label), value: $0.value as String)
                    },
                    thumbnail: contact.thumbnailImageData)
            }
        }.value
    }

    nonisolated private static func label(_ raw: String?) -> String {
        raw.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) } ?? ""
    }
}

#if EMBLEM_HOMEKIT

@Observable @MainActor
final class HomeService: NSObject, HMHomeManagerDelegate {
    static let shared = HomeService()

    struct Accessory: Identifiable, Hashable {
        var id: UUID
        var name: String
        var room: String
        var symbol: String
        var isOn: Bool?
        var reachable: Bool
    }

    struct Scene: Identifiable, Hashable {
        var id: UUID
        var name: String
    }

    private(set) var accessories: [Accessory] = []
    private(set) var scenes: [Scene] = []
    private(set) var hasHome = false
    private(set) var loaded = false
    private var manager: HMHomeManager?
    private var askedKey: String { "device.home.asked" }

    var systemState: DeviceAccess.State {
        guard UserDefaults.standard.bool(forKey: askedKey) else { return .notAsked }
        let status = startedManager().authorizationStatus
        if status.contains(.authorized) { return .allowed }
        return status.contains(.determined) ? .denied : .notAsked
    }

    func requestAccess() async {
        UserDefaults.standard.set(true, forKey: askedKey)
        _ = startedManager()
        for _ in 0..<60 where !loaded {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    func load() {
        guard UserDefaults.standard.bool(forKey: askedKey) else { return }
        _ = startedManager()
    }

    func matching(_ query: String?) -> (accessories: [Accessory], scenes: [Scene]) {
        let words = (query ?? "").lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !["the", "all", "my", "in", "and", "turn", "on", "off", "lights", "light"].contains($0) }
        let wantsLights = (query ?? "").localizedCaseInsensitiveContains("light")
        let filtered = accessories.filter { accessory in
            let haystack = "\(accessory.name) \(accessory.room)".lowercased()
            let matchesWords = words.allSatisfy { haystack.contains($0) }
            return matchesWords && (!wantsLights || accessory.symbol.hasPrefix("lightbulb"))
        }
        let sceneMatches = words.isEmpty ? scenes : scenes.filter { scene in
            words.contains { scene.name.lowercased().contains($0) }
        }
        return (filtered.isEmpty && words.isEmpty ? accessories : filtered, sceneMatches)
    }

    func setPower(_ id: UUID, on: Bool) async -> Bool {
        guard let characteristic = powerCharacteristic(id) else { return false }
        let ok = await withCheckedContinuation { continuation in
            characteristic.writeValue(on) { error in continuation.resume(returning: error == nil) }
        }
        if ok { update(id) { $0.isOn = on } }
        return ok
    }

    func run(_ sceneID: UUID) async -> Bool {
        guard let home = manager?.homes.first(where: { $0.actionSets.contains { $0.uniqueIdentifier == sceneID } }),
              let scene = home.actionSets.first(where: { $0.uniqueIdentifier == sceneID })
        else { return false }
        let ok = await withCheckedContinuation { continuation in
            home.executeActionSet(scene) { error in continuation.resume(returning: error == nil) }
        }
        if ok { reload() }
        return ok
    }

    private func startedManager() -> HMHomeManager {
        if let manager { return manager }
        let manager = HMHomeManager()
        manager.delegate = self
        self.manager = manager
        return manager
    }

    private func update(_ id: UUID, _ change: (inout Accessory) -> Void) {
        guard let index = accessories.firstIndex(where: { $0.id == id }) else { return }
        change(&accessories[index])
    }

    private func powerCharacteristic(_ id: UUID) -> HMCharacteristic? {
        manager?.homes.lazy.flatMap(\.accessories)
            .first { $0.uniqueIdentifier == id }?
            .services.lazy.flatMap(\.characteristics)
            .first { $0.characteristicType == HMCharacteristicTypePowerState }
    }

    private func reload() {
        let homes = manager?.homes ?? []
        hasHome = !homes.isEmpty
        accessories = homes.flatMap(\.accessories).compactMap { accessory in
            let services = accessory.services
            guard let power = services.lazy.flatMap(\.characteristics)
                .first(where: { $0.characteristicType == HMCharacteristicTypePowerState })
            else { return nil }
            let type = power.service?.serviceType
            let symbol = switch type {
            case HMServiceTypeLightbulb: "lightbulb.fill"
            case HMServiceTypeOutlet: "poweroutlet.type.b.fill"
            case HMServiceTypeFan: "fan.fill"
            default: "switch.2"
            }
            return Accessory(
                id: accessory.uniqueIdentifier, name: accessory.name,
                room: accessory.room?.name ?? "", symbol: symbol,
                isOn: power.value as? Bool, reachable: accessory.isReachable)
        }
        scenes = homes.flatMap(\.actionSets).map { Scene(id: $0.uniqueIdentifier, name: $0.name) }
        loaded = true
        DeviceAccess.shared.refresh()
    }

    nonisolated func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        Task { @MainActor in self.reload() }
    }

    nonisolated func homeManager(_ manager: HMHomeManager, didUpdate status: HMHomeManagerAuthorizationStatus) {
        Task { @MainActor in self.reload() }
    }
}
#endif
