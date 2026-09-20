import Cocoa
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var multitouchManager: MultitouchManager?
    var isEnabled = true
    private var dragEventTap: CFMachPort?
    private var dragEventTapRunLoopSource: CFRunLoopSource?
    private let dragEventSource: CGEventSource? = {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return nil }

        // Let physical mouse and keyboard input through immediately while the synthetic button
        // is held. This source is used only by drag lock; ordinary tap-to-click keeps its old
        // event path.
        source.localEventsSuppressionInterval = 0
        let permitAllLocalEvents: CGEventFilterMask = [
            .permitLocalMouseEvents,
            .permitLocalKeyboardEvents,
            .permitSystemDefinedEvents
        ]
        source.setLocalEventsFilterDuringSuppressionState(
            permitAllLocalEvents,
            state: .eventSuppressionStateSuppressionInterval
        )
        source.setLocalEventsFilterDuringSuppressionState(
            permitAllLocalEvents,
            state: .eventSuppressionStateRemoteMouseDrag
        )
        return source
    }()
    private var hasStartedMultitouch = false
    private var hasRequestedAccessibilityPrompt = false
    private var hasShownAccessibilityInstructions = false
    private weak var dragLockStatusItem: NSMenuItem?
    private weak var diagnosticsStatusItem: NSMenuItem?
    private var pendingWakeRestart: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DiagnosticLog.reset()
        setupMenuBar()

        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        workspaceNotifications.addObserver(
            self,
            selector: #selector(scheduleListenerRestartAfterWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        workspaceNotifications.addObserver(
            self,
            selector: #selector(scheduleListenerRestartAfterWake),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )

        ensureAccessibilityAndStart()
    }

    @objc func showAccessibilityInstructions() {
        guard !hasShownAccessibilityInstructions else { return }
        hasShownAccessibilityInstructions = true
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Magic Mouse Tap needs Accessibility permission to simulate clicks.\n\nGrant it in System Settings > Privacy & Security > Accessibility. The app will begin working as soon as permission is granted."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        } else if response == .alertSecondButtonReturn {
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pendingWakeRestart?.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        multitouchManager?.stop()
        tearDownDragEventTap()
    }

    @objc private func scheduleListenerRestartAfterWake() {
        pendingWakeRestart?.cancel()
        let restart = DispatchWorkItem { [weak self] in
            self?.restartMultitouchListener()
        }
        pendingWakeRestart = restart
        // Give Bluetooth enough time to publish the reconnected Magic Mouse device.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: restart)
    }

    private func restartMultitouchListener() {
        guard CGPreflightPostEventAccess() else { return }
        DiagnosticLog.write("system woke/session activated; refreshing multitouch devices")
        multitouchManager?.stop()
        multitouchManager = nil
        tearDownDragEventTap()
        hasStartedMultitouch = false
        startMultitouchManager()
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: "Magic Mouse Tap")
        }

        let menu = NSMenu()

        let enabledItem = NSMenuItem(title: "Tap to Click: Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.state = isEnabled ? .on : .off
        menu.addItem(enabledItem)

        let diagnosticItem = NSMenuItem(title: "Status: Checking Accessibility…", action: nil, keyEquivalent: "")
        diagnosticItem.isEnabled = false
        menu.addItem(diagnosticItem)
        diagnosticsStatusItem = diagnosticItem

        let testClickItem = NSMenuItem(title: "Test Click in 2 Seconds", action: #selector(testClick), keyEquivalent: "")
        testClickItem.target = self
        menu.addItem(testClickItem)

        let gesturesItem = NSMenuItem(title: "Double Tap + Hold: Select/Drag • Swipe: Zoom • Two-Finger Tap: Right Click", action: nil, keyEquivalent: "")
        gesturesItem.isEnabled = false
        menu.addItem(gesturesItem)

        menu.addItem(NSMenuItem.separator())
        let accessibilityItem = NSMenuItem(title: "Accessibility Instructions…", action: #selector(showAccessibilityInstructions), keyEquivalent: "")
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "About Magic Mouse Tap", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Magic Mouse Tap", action: #selector(quit), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc func toggleEnabled() {
        isEnabled.toggle()
        if let menu = statusItem?.menu,
           let item = menu.items.first {
            item.state = isEnabled ? .on : .off
            item.title = isEnabled ? "Tap to Click: Enabled" : "Tap to Click: Disabled"
        }
        multitouchManager?.setEnabled(isEnabled)
    }

    @objc func testClick() {
        diagnosticsStatusItem?.title = "Status: Test click scheduled…"
        DiagnosticLog.write("manual test click scheduled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            let location = CGEvent(source: nil)?.location ?? .zero
            self.synthesizeClick(at: location, isRightClick: false, clickCount: 1)
            self.diagnosticsStatusItem?.title = "Status: Test click sent"
            DiagnosticLog.write("manual test click sent at \(location.x),\(location.y)")
        }
    }

    /// Submenu letting the user pick where the left/right click boundary sits on the mouse surface.
    private func buildRightClickZoneItem() -> NSMenuItem {
        let parentItem = NSMenuItem(title: "Right Click Zone", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        var choices = Preferences.rightClickThresholdChoices
        let current = Preferences.rightClickThreshold
        // Surface a value set outside the app (e.g. via `defaults write`) so it's still selectable.
        if !choices.contains(current) {
            choices.append(current)
            choices.sort()
        }

        for choice in choices {
            let percent = Int((choice * 100).rounded())
            let item = NSMenuItem(
                title: "Right side starts at \(percent)%",
                action: #selector(selectRightClickThreshold(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = choice
            item.state = choice == current ? .on : .off
            submenu.addItem(item)
        }

        parentItem.submenu = submenu
        return parentItem
    }

    @objc func selectRightClickThreshold(_ sender: NSMenuItem) {
        guard let threshold = sender.representedObject as? Float else { return }

        Preferences.rightClickThreshold = threshold
        multitouchManager?.rightClickThreshold = Preferences.rightClickThreshold

        guard let submenu = sender.menu else { return }
        for item in submenu.items {
            item.state = (item.representedObject as? Float) == Preferences.rightClickThreshold ? .on : .off
        }
    }

    @objc func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let alert = NSAlert()
        alert.messageText = "Magic Mouse Tap"
        alert.informativeText = """
        Tap-to-click for Magic Mouse

        • One-finger tap for left click
        • Double tap to select; hold the second tap to select/drag
        • Two-finger tap for right click

        Version \(version)

        Uses private MultitouchSupport framework
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func quit() {
        multitouchManager?.stop()
        NSApplication.shared.terminate(nil)
    }

    private func ensureAccessibilityAndStart() {
        let canPostEvents = CGPreflightPostEventAccess()
        let isAXTrusted = AXIsProcessTrusted()
        DiagnosticLog.write("permission preflight; PostEvent=\(canPostEvents), AX=\(isAXTrusted)")

        if canPostEvents {
            DiagnosticLog.write("PostEvent access granted at launch")
            startMultitouchManager()
            return
        }

        DiagnosticLog.write("PostEvent access not granted at launch")
        diagnosticsStatusItem?.title = "Status: Click permission missing"

        requestAccessibilityPermissionIfNeeded()
        waitForAccessibilityPermission()
    }

    private func startMultitouchManager() {
        guard !hasStartedMultitouch else { return }
        hasStartedMultitouch = true

        let canTransformDragEvents = setUpDragEventTap()
        let manager = MultitouchManager()
        manager.setSelectionDragAvailable(canTransformDragEvents)
        multitouchManager = manager

        manager.onClickSynthesized = { [weak self] location, isRightClick, clickCount in
            DispatchQueue.main.async {
                if isRightClick {
                    self?.diagnosticsStatusItem?.title = "Status: Two-finger right click sent"
                } else if clickCount == 2 {
                    self?.diagnosticsStatusItem?.title = "Status: Double tap • selection click sent"
                } else {
                    self?.diagnosticsStatusItem?.title = "Status: Tap recognized • click sent"
                }
                self?.synthesizeClick(at: location, isRightClick: isRightClick, clickCount: clickCount)
            }
        }
        manager.onDeviceCountChanged = { [weak self] count in
            DispatchQueue.main.async {
                self?.diagnosticsStatusItem?.title = count > 0
                    ? "Status: Ready • Magic Mouse connected"
                    : "Status: No external touch mouse found"
            }
        }
        manager.onTouchInputDetected = { [weak self] in
            DispatchQueue.main.async {
                self?.diagnosticsStatusItem?.title = "Status: Ready • touch input detected"
            }
        }
        manager.onSelectionDragChanged = { [weak self] location, isDragging in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if isDragging {
                    self.setDragEventTapEnabled(true)
                    self.synthesizeSelectionDrag(at: location, isDragging: true)
                    self.diagnosticsStatusItem?.title = "Status: Selection/drag active"
                } else {
                    self.synthesizeSelectionDrag(at: location, isDragging: false)
                    self.setDragEventTapEnabled(false)
                    self.diagnosticsStatusItem?.title = "Status: Selection/drag released"
                }
            }
        }
        manager.onZoomGesture = { [weak self] zoomIn in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.synthesizeZoom(zoomIn: zoomIn)
                self.diagnosticsStatusItem?.title = zoomIn
                    ? "Status: Zoom in sent"
                    : "Status: Zoom out sent"
            }
        }
        manager.start()
    }

    /// Creates a session-level event transformer and leaves it disabled until drag lock starts.
    /// Session-level conversion delivers drag semantics to applications without intercepting the
    /// HID input path used by Magic Mouse touch detection.
    private func setUpDragEventTap() -> Bool {
        guard dragEventTap == nil else { return true }

        let eventMask = (CGEventMask(1) << CGEventType.mouseMoved.rawValue)
            | (CGEventMask(1) << CGEventType.scrollWheel.rawValue)
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: dragEventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        // Keep the tap enabled continuously so native scroll-wheel events can veto clicks.
        // Mouse-move events are transformed only while selection dragging is active.
        CGEvent.tapEnable(tap: eventTap, enable: true)
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        dragEventTap = eventTap
        dragEventTapRunLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        return true
    }

    private func setDragEventTapEnabled(_ enabled: Bool) {
        guard let eventTap = dragEventTap else { return }
        // The event tap must remain active to observe scroll-wheel events. The manager's
        // isSelectionDragging flag controls whether mouse movement is transformed.
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func tearDownDragEventTap() {
        if let runLoopSource = dragEventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap = dragEventTap {
            CFMachPortInvalidate(eventTap)
        }
        dragEventTapRunLoopSource = nil
        dragEventTap = nil
    }

    fileprivate func handleDragEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            setDragEventTapEnabled(true)
            return Unmanaged.passUnretained(event)
        }

        if type == .scrollWheel {
            if multitouchManager?.isSelectionDragging == true ||
                multitouchManager?.isSecondTapPending == true ||
                multitouchManager?.isZoomGestureActive == true {
                return nil
            }
            multitouchManager?.noteScrollEvent()
            return Unmanaged.passUnretained(event)
        }

        guard type == .mouseMoved else {
            return Unmanaged.passUnretained(event)
        }

        if let location = multitouchManager?.promotePendingSecondTapToSelectionDrag(
            currentLocation: event.location
        ) {
            setDragEventTapEnabled(true)
            synthesizeSelectionDrag(at: location, isDragging: true)
            diagnosticsStatusItem?.title = "Status: Selection/drag active"
        }

        guard multitouchManager?.isSelectionDragging == true else {
            return Unmanaged.passUnretained(event)
        }

        event.type = .leftMouseDragged
        event.setIntegerValueField(
            .mouseEventButtonNumber,
            value: Int64(CGMouseButton.left.rawValue)
        )
        event.setIntegerValueField(.mouseEventClickState, value: 2)
        event.setDoubleValueField(.mouseEventPressure, value: 1.0)
        return Unmanaged.passUnretained(event)
    }

    private func requestAccessibilityPermissionIfNeeded() {
        guard !hasRequestedAccessibilityPrompt else { return }
        hasRequestedAccessibilityPrompt = true

        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        let granted = CGRequestPostEventAccess()
        DiagnosticLog.write("requested PostEvent access; immediate result=\(granted)")
    }

    private func waitForAccessibilityPermission() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }

            if CGPreflightPostEventAccess() {
                DiagnosticLog.write("PostEvent access became trusted")
                self.startMultitouchManager()
            } else {
                self.waitForAccessibilityPermission()
            }
        }
    }

    /// True if the point falls on an active display. Coordinates here are in Quartz global
    /// space (origin top-left), which is what `CGEvent.location` reports — so this must not be
    /// compared against `NSScreen.frame`, which uses Cocoa's bottom-left origin.
    private func isOnActiveDisplay(_ location: CGPoint) -> Bool {
        guard location.x.isFinite, location.y.isFinite else { return false }

        var matchingDisplayCount: UInt32 = 0
        // Fail open: if the query itself fails, don't silently swallow the click.
        guard CGGetDisplaysWithPoint(location, 0, nil, &matchingDisplayCount) == .success else {
            return true
        }
        return matchingDisplayCount > 0
    }

    func synthesizeClick(at location: CGPoint, isRightClick: Bool, clickCount: Int64 = 1) {
        guard isOnActiveDisplay(location) else { return }

        if isRightClick {
            if let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: location, mouseButton: .right) {
                mouseDown.setIntegerValueField(.mouseEventClickState, value: clickCount)
                mouseDown.post(tap: .cghidEventTap)
            }
            if let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: location, mouseButton: .right) {
                mouseUp.setIntegerValueField(.mouseEventClickState, value: clickCount)
                mouseUp.post(tap: .cghidEventTap)
            }
        } else {
            if let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: location, mouseButton: .left) {
                mouseDown.setIntegerValueField(.mouseEventClickState, value: clickCount)
                mouseDown.post(tap: .cghidEventTap)
            }
            if let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: location, mouseButton: .left) {
                mouseUp.setIntegerValueField(.mouseEventClickState, value: clickCount)
                mouseUp.post(tap: .cghidEventTap)
            }
        }
    }

    /// Holds or releases the primary mouse button. Pointer movement produced by the physical
    /// mouse while the button is held is interpreted by macOS as dragging.
    func synthesizeSelectionDrag(at location: CGPoint, isDragging: Bool) {
        // When locking, verify location is on an active display.
        // When unlocking, always post leftMouseUp unconditionally so the primary mouse button
        // is never permanently stuck down.
        if isDragging {
            guard isOnActiveDisplay(location) else { return }
        }

        let eventType: CGEventType = isDragging ? .leftMouseDown : .leftMouseUp
        if let event = CGEvent(
            mouseEventSource: dragEventSource,
            mouseType: eventType,
            mouseCursorPosition: location,
            mouseButton: .left
        ) {
            event.setIntegerValueField(.mouseEventClickState, value: 2)
            event.post(tap: .cghidEventTap)
        }
    }

    /// Sends the standard macOS application zoom shortcuts: Command-minus to zoom out and
    /// Command-plus (Command-Shift-equals) to zoom in.
    func synthesizeZoom(zoomIn: Bool) {
        let keyCode: CGKeyCode = zoomIn ? 24 : 27
        var flags: CGEventFlags = .maskCommand
        if zoomIn {
            flags.insert(.maskShift)
        }

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            return
        }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func updateDragLockStatus(isLocked: Bool) {
        dragLockStatusItem?.title = isLocked
            ? "Drag Lock: Locked (Two-Finger Tap to Release)"
            : "Drag Lock: Unlocked (Two-Finger Tap)"
    }
}

private let dragEventCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
    return appDelegate.handleDragEvent(type: type, event: event)
}
