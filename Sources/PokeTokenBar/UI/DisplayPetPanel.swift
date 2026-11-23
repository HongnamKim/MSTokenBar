import AppKit
import Observation
import SwiftUI

/// The second floating pet: the machine the player chose in the hangar, shown beside the raised one.
/// It follows the main pet's on/off, size and flip settings, sits in its own draggable panel (position
/// saved), opens the popover on click, and right-click offers Open / Hide (Hide switches it off).
@MainActor
final class DisplayPetController: NSObject, NSWindowDelegate {
    static let originXKey = "displayPetOriginX"
    static let originYKey = "displayPetOriginY"

    private let store: UsageStore
    private let companion: CompanionStore
    private let defaults: UserDefaults
    private let onOpenPopover: () -> Void
    private var panel: NSPanel?
    private var builtAnimated: Bool?
    private var displayAwake = true
    private var powerObserver: NSObjectProtocol?

    init(store: UsageStore, companion: CompanionStore, defaults: UserDefaults = .standard,
         onOpenPopover: @escaping () -> Void = {}) {
        self.store = store
        self.companion = companion
        self.defaults = defaults
        self.onOpenPopover = onOpenPopover
        super.init()
        observeSettings()
        powerObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.sync() }
        }
        sync()
    }

    /// Visible only while the floating pet is on, a machine is chosen and switched on, and the display is awake.
    static func shouldShow(floatingPetEnabled: Bool, subject: CompanionStore.RepresentativeSubject?,
                           displayAwake: Bool) -> Bool {
        floatingPetEnabled && subject?.speciesID != nil && displayAwake
    }

    /// Default spot: just left of the main pet's default corner, so the two stand side by side.
    static func defaultOrigin(petSize: CGFloat, visible: NSRect?) -> NSPoint {
        guard let visible else { return NSPoint(x: 120, y: 120) }
        return NSPoint(x: visible.maxX - petSize * 2 - 40, y: visible.minY + 24)
    }

    var isVisible: Bool { panel?.isVisible == true }

    func setDisplayAwake(_ awake: Bool) {
        displayAwake = awake
        sync()
    }

    private func observeSettings() {
        withObservationTracking {
            _ = store.floatingPetEnabled
            _ = store.floatingPetSize
            _ = companion.displayPetSubject
            _ = companion.language   // the hover name is localized
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.sync()
                self.observeSettings()
            }
        }
    }

    private func sync() {
        guard Self.shouldShow(floatingPetEnabled: store.floatingPetEnabled, subject: companion.displayPetSubject,
                              displayAwake: displayAwake) else { hide(); return }
        show()
    }

    private func show() {
        let p = panel ?? makePanel()
        panel = p
        let wantAnimated = FloatingPetController.shouldAnimate(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        if p.contentView == nil || builtAnimated != wantAnimated {
            p.contentView = makeHostingView(animated: wantAnimated)
            builtAnimated = wantAnimated
        }
        // Hovering names the suit, like the main pet's first hover line.
        p.contentView?.toolTip = companion.hoverTitle(speciesID: companion.displayPetSubject?.speciesID)
        let size = CGFloat(store.floatingPetSize)
        p.setFrame(NSRect(origin: savedOrigin(petSize: size), size: NSSize(width: size, height: size)), display: true)
        p.orderFrontRegardless()
    }

    private func hide() {
        guard let p = panel else { return }
        p.orderOut(nil)
        p.contentView = nil   // drop the hosting tree so the GIF loop stops
        builtAnimated = nil
    }

    private func savedOrigin(petSize: CGFloat) -> NSPoint {
        if let x = defaults.object(forKey: Self.originXKey) as? Double,
           let y = defaults.object(forKey: Self.originYKey) as? Double {
            let point = NSPoint(x: x, y: y)
            if NSScreen.screens.contains(where: { $0.frame.contains(point) }) { return point }
        }
        return Self.defaultOrigin(petSize: petSize, visible: NSScreen.main?.visibleFrame)
    }

    private func makeHostingView(animated: Bool) -> PetHostingView {
        let hosting = PetHostingView(rootView: AnyView(
            DisplayPetView(animated: animated).environment(store).environment(companion)))
        hosting.onClick = { [weak self] in self?.onOpenPopover() }
        hosting.onOpenPopover = { [weak self] in self?.onOpenPopover() }
        hosting.onHide = { [weak self] in self?.companion.setDisplayPetEnabled(false) }
        hosting.languageProvider = { [weak self] in self?.companion.language ?? .systemDefault }
        return hosting
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.becomesKeyOnlyIfNeeded = true
        p.animationBehavior = .none
        p.delegate = self
        return p
    }

    func windowDidMove(_ notification: Notification) {
        guard let p = panel, p.isVisible, (p.contentView as? PetHostingView)?.isDragging == true else { return }
        defaults.set(Double(p.frame.origin.x), forKey: Self.originXKey)
        defaults.set(Double(p.frame.origin.y), forKey: Self.originYKey)
    }
}

/// The chosen machine, at the floating pet's size, with its grade mark in the corner.
@MainActor
struct DisplayPetView: View {
    var animated: Bool = true
    @Environment(UsageStore.self) private var store
    @Environment(CompanionStore.self) private var companion

    var body: some View {
        let size = CGFloat(store.floatingPetSize)
        if let subject = companion.displayPetSubject, let speciesID = subject.speciesID {
            SpriteView(speciesID: speciesID, size: size, animated: animated, shiny: subject.isShiny,
                       minFrameDelay: store.animationQuality.frameFloor, showsGradeBadge: false,
                       mirrored: store.floatingPetMirrored)
                .frame(width: size, height: size)
                .overlay(alignment: .bottomTrailing) {
                    if let grade = GunplaID.decode(speciesID)?.grade {
                        GunplaGradeBadge(grade: grade, spriteSize: size, isFloatingMark: true)
                    }
                }
        }
    }
}
