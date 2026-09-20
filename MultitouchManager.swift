import Foundation
import CoreGraphics
import AppKit

// Swift wrapper for Multitouch framework
class MultitouchManager {
    private var devices: [MTDeviceRef] = []
    private var tapDetector = TapDetector(tapTimeThreshold: 0.22, tapMovementThreshold: 0.08)
    private var twoFingerTapDetector = TwoFingerTapDetector(tapTimeThreshold: 0.35, movementThreshold: 0.12)
    private var isEnabled = true
    private var isSelectionDragAvailable = false
    private var activeTouch: Int32 = -1
    private var touchStartX: Float = 0.0
    private var touchStartY: Float = 0.0
    private var surfaceMovementThreshold: Float = 0.04  // 4% of surface; scrolling must never become a tap
    private var suppressSingleTouchUntilLift = false
    private let doubleTapTimeThreshold: TimeInterval = 0.40
    private let doubleTapCursorDistanceThreshold: CGFloat = 30.0
    private var lastSingleTapTimestamp: TimeInterval?
    private var lastSingleTapLocation: CGPoint?
    private let scrollStateLock = NSLock()
    private var scrollEventGeneration: UInt64 = 0
    private var lastScrollEventUptime: TimeInterval = -.infinity
    private var touchStartScrollGeneration: UInt64 = 0
    private var touchStartedDuringScroll = false
    private let scrollStopTapWindow: TimeInterval = 0.35
    private let pendingClickLock = NSLock()
    private var pendingClickSerial: UInt64 = 0
    private var pendingSingleClick: (serial: UInt64, location: CGPoint, scrollGeneration: UInt64)?
    private let postReleaseScrollGuardDelay: TimeInterval = 0.12

    /// Taps with a normalized x above this are right clicks. Configurable from the menu bar.
    var rightClickThreshold: Float = Preferences.rightClickThreshold {
        didSet {
            rightClickThreshold = Preferences.clamp(rightClickThreshold)
        }
    }

    fileprivate static var sharedInstance: MultitouchManager?

    var onClickSynthesized: ((CGPoint, Bool, Int64) -> Void)?
    var onSelectionDragChanged: ((CGPoint, Bool) -> Void)?
    var onDeviceCountChanged: ((Int) -> Void)?
    var onTouchInputDetected: (() -> Void)?
    private(set) var isSelectionDragging = false
    private var hasReportedTouchInput = false

    init() {
        MultitouchManager.sharedInstance = self
    }

    func start() {
        guard let deviceList = MTDeviceCreateList() else {
            DiagnosticLog.write("MTDeviceCreateList returned nil")
            onDeviceCountChanged?(0)
            return
        }

        let deviceArray = deviceList.takeRetainedValue() as NSArray
        let count = CFArrayGetCount(deviceArray)

        for i in 0..<count {
            let device = unsafeBitCast(CFArrayGetValueAtIndex(deviceArray, i), to: MTDeviceRef.self)

            // Only monitor external devices (Magic Mouse), skip built-in trackpads
            let isBuiltIn = MTDeviceIsBuiltIn(device)

            if !isBuiltIn {
                devices.append(device)
                MTRegisterContactFrameCallback(device, touchCallback)
                MTDeviceStart(device, 0)
            }
        }
        DiagnosticLog.write("multitouch started; external devices=\(devices.count), total devices=\(count)")
        onDeviceCountChanged?(devices.count)
    }

    func stop() {
        releaseSelectionDrag()
        resetTouchTracking()

        for device in devices {
            MTUnregisterContactFrameCallback(device, touchCallback)
            MTDeviceStop(device)
        }
        devices.removeAll()
    }

    func setEnabled(_ enabled: Bool) {
        if !enabled {
            releaseSelectionDrag()
            resetTouchTracking()
        }
        isEnabled = enabled
    }

    func setSelectionDragAvailable(_ available: Bool) {
        if !available {
            DiagnosticLog.write("mouse-move drag transformer unavailable; using button-hold fallback")
        }
        isSelectionDragAvailable = available
    }

    /// Called by the always-on scroll-wheel event tap. Any native scroll generated during a
    /// contact sequence disqualifies that sequence from becoming a click.
    func noteScrollEvent() {
        scrollStateLock.lock()
        scrollEventGeneration &+= 1
        lastScrollEventUptime = ProcessInfo.processInfo.systemUptime
        scrollStateLock.unlock()
    }

    func processTouches(_ touches: UnsafeMutablePointer<MTTouch>, numTouches: Int, timestamp: Double) {
        guard isEnabled else { return }

        // The callback comes from a private framework; don't trust a negative count.
        guard numTouches >= 0 else { return }

        if numTouches > 0 && !hasReportedTouchInput {
            hasReportedTouchInput = true
            DiagnosticLog.write("first touch frame received; touches=\(numTouches)")
            onTouchInputDetected?()
        }

        let surfaceTouches = (0..<numTouches).map { index in
            let touch = touches[index]
            return SurfaceTouch(
                identifier: touch.identifier,
                position: CGPoint(
                    x: CGFloat(touch.normalized.position.x),
                    y: CGFloat(touch.normalized.position.y)
                )
            )
        }
        let twoFingerResult = twoFingerTapDetector.process(
            touches: surfaceTouches,
            timestamp: timestamp
        )

        switch twoFingerResult {
        case .recognized:
            cancelSingleTouchTracking()
            lastSingleTapTimestamp = nil
            lastSingleTapLocation = nil
            let location = CGEvent(source: nil)?.location ?? CGPoint.zero
            DiagnosticLog.write("two-finger tap recognized; right click")
            onClickSynthesized?(location, true, 1)
            return
        case .rejectedMultiTouchGesture:
            cancelSingleTouchTracking()
            return
        case .none:
            break
        }

        // During the second touch of a double-tap, keep the primary button held until that
        // finger lifts. Physical mouse movement is converted to leftMouseDragged by AppDelegate.
        if isSelectionDragging {
            if numTouches == 0 {
                finishSelectionDrag()
                cancelSingleTouchTracking()
            } else if numTouches > 1 {
                // Never leave the synthetic button held if another finger joins the gesture.
                finishSelectionDrag()
                twoFingerTapDetector.reset()
                cancelSingleTouchTracking()
            }
            return
        }

        // Once a second finger has participated, wait for every finger to lift. Otherwise the
        // last remaining finger could be mistaken for a fresh one-finger click.
        if twoFingerTapDetector.suppressesSingleFingerTap {
            cancelSingleTouchTracking()
            return
        }

        if numTouches == 0 {
            if activeTouch != -1 {
                // Get cursor position directly from CGEvent (already in correct coordinate space)
                let cgLocation = CGEvent(source: nil)?.location ?? CGPoint.zero

                if let tapLocation = tapDetector.touchEnded(at: cgLocation) {
                    guard !touchStartedDuringScroll,
                          !nativeScrollOccurred(since: touchStartScrollGeneration) else {
                        DiagnosticLog.write("tap rejected because it occurred during or stopped scrolling")
                        lastSingleTapTimestamp = nil
                        lastSingleTapLocation = nil
                        activeTouch = -1
                        touchStartX = 0.0
                        touchStartY = 0.0
                        touchStartedDuringScroll = false
                        suppressSingleTouchUntilLift = false
                        return
                    }
                    recordSingleTap(at: tapLocation, timestamp: timestamp)
                    scheduleSingleClick(at: tapLocation)
                }
                activeTouch = -1
                touchStartX = 0.0
                touchStartY = 0.0
            }
            touchStartedDuringScroll = false
            suppressSingleTouchUntilLift = false
            return
        }

        if numTouches == 1 {
            // A scrolling/moving finger remains suppressed for its whole contact sequence. Without
            // this latch, later frames from the same finger could be mistaken for a fresh tap.
            guard !suppressSingleTouchUntilLift else { return }

            let touch = touches[0]
            // Get cursor position directly from CGEvent (already in correct coordinate space)
            let cgLocation = CGEvent(source: nil)?.location ?? CGPoint.zero

            if touch.state == 4 || touch.state == 7 {
                if activeTouch == -1 {
                    // New touch started - record starting position on surface
                    activeTouch = touch.identifier
                    touchStartX = touch.normalized.position.x
                    touchStartY = touch.normalized.position.y
                    touchStartScrollGeneration = currentScrollGeneration()
                    touchStartedDuringScroll = wasScrollingRecently()
                    if touchStartedDuringScroll {
                        DiagnosticLog.write("touch began during scroll cooldown; it will only stop scrolling")
                    }
                    if isSecondTapCandidate(at: cgLocation, timestamp: timestamp) {
                        beginSelectionDrag(at: cgLocation)
                    } else {
                        tapDetector.touchBegan(at: cgLocation)
                    }
                } else if activeTouch == touch.identifier {
                    if isSelectionDragging {
                        return
                    }
                    // Same touch continuing - check if finger moved too much on surface (scrolling)
                    let deltaX = abs(touch.normalized.position.x - touchStartX)
                    let deltaY = abs(touch.normalized.position.y - touchStartY)
                    let surfaceMovement = max(deltaX, deltaY)

                    if surfaceMovement > surfaceMovementThreshold {
                        // Finger moved too much on surface - likely scrolling, cancel tap
                        DiagnosticLog.write("single-finger gesture suppressed until lift; surface movement=\(surfaceMovement)")
                        suppressSingleTouchUntilLift = true
                        tapDetector.reset()
                        activeTouch = -1
                        touchStartX = 0.0
                        touchStartY = 0.0
                    } else {
                        // Check cursor movement too (physical mouse movement cancels tap)
                        let moved = tapDetector.touchMoved(to: cgLocation)
                        if moved {
                            DiagnosticLog.write("single-finger gesture suppressed until lift; cursor moved")
                            suppressSingleTouchUntilLift = true
                            activeTouch = -1
                            touchStartX = 0.0
                            touchStartY = 0.0
                        }
                    }
                }
            }
        } else if numTouches > 1 {
            cancelSingleTouchTracking()
        }
    }

    private func isSecondTapCandidate(at location: CGPoint, timestamp: TimeInterval) -> Bool {
        if let previousTimestamp = lastSingleTapTimestamp,
           let previousLocation = lastSingleTapLocation {
            let elapsed = timestamp - previousTimestamp
            let distance = hypot(location.x - previousLocation.x, location.y - previousLocation.y)
            if elapsed >= 0,
               elapsed <= doubleTapTimeThreshold,
               distance <= doubleTapCursorDistanceThreshold {
                return true
            }
        }
        return false
    }

    private func currentScrollGeneration() -> UInt64 {
        scrollStateLock.lock()
        defer { scrollStateLock.unlock() }
        return scrollEventGeneration
    }

    private func nativeScrollOccurred(since generation: UInt64) -> Bool {
        scrollStateLock.lock()
        defer { scrollStateLock.unlock() }
        let occurredDuringTouch = scrollEventGeneration != generation
        let occurredNearRelease = ProcessInfo.processInfo.systemUptime - lastScrollEventUptime < 0.12
        return occurredDuringTouch || occurredNearRelease
    }

    private func wasScrollingRecently() -> Bool {
        scrollStateLock.lock()
        defer { scrollStateLock.unlock() }
        return ProcessInfo.processInfo.systemUptime - lastScrollEventUptime < scrollStopTapWindow
    }

    private func recordSingleTap(at location: CGPoint, timestamp: TimeInterval) {
        lastSingleTapTimestamp = timestamp
        lastSingleTapLocation = location
    }

    /// macOS can emit the scroll-wheel event a few milliseconds after the final touch frame.
    /// Hold an ordinary click briefly so that late event can veto it before anything is posted.
    private func scheduleSingleClick(at location: CGPoint) {
        let scrollGeneration = currentScrollGeneration()
        pendingClickLock.lock()
        pendingClickSerial &+= 1
        let serial = pendingClickSerial
        pendingSingleClick = (serial, location, scrollGeneration)
        pendingClickLock.unlock()

        DiagnosticLog.write("one-finger tap pending post-release scroll guard")
        DispatchQueue.main.asyncAfter(deadline: .now() + postReleaseScrollGuardDelay) { [weak self] in
            self?.deliverPendingSingleClick(serial: serial)
        }
    }

    private func deliverPendingSingleClick(serial: UInt64) {
        pendingClickLock.lock()
        guard let pending = pendingSingleClick, pending.serial == serial else {
            pendingClickLock.unlock()
            return
        }
        pendingSingleClick = nil
        pendingClickLock.unlock()

        guard !nativeScrollOccurred(since: pending.scrollGeneration) else {
            DiagnosticLog.write("pending tap rejected because macOS generated a post-release scroll event")
            lastSingleTapTimestamp = nil
            lastSingleTapLocation = nil
            return
        }

        DiagnosticLog.write("one-finger tap recognized after scroll guard; clickCount=1")
        onClickSynthesized?(pending.location, false, 1)
    }

    /// A fast second tap may arrive before the short guard delay expires. Deliver the first
    /// click before starting selection mode so event order remains click, then held mouse-down.
    private func flushPendingSingleClick() {
        pendingClickLock.lock()
        guard let pending = pendingSingleClick else {
            pendingClickLock.unlock()
            return
        }
        pendingSingleClick = nil
        pendingClickLock.unlock()

        guard !nativeScrollOccurred(since: pending.scrollGeneration) else {
            DiagnosticLog.write("pending first tap rejected before double tap because of scrolling")
            return
        }
        DiagnosticLog.write("pending first tap delivered before selection/drag")
        onClickSynthesized?(pending.location, false, 1)
    }

    private func cancelPendingSingleClick() {
        pendingClickLock.lock()
        pendingSingleClick = nil
        pendingClickSerial &+= 1
        pendingClickLock.unlock()
    }

    private func beginSelectionDrag(at location: CGPoint) {
        flushPendingSingleClick()
        lastSingleTapTimestamp = nil
        lastSingleTapLocation = nil
        tapDetector.reset()
        isSelectionDragging = true
        DiagnosticLog.write("double tap second touch began; selection/drag mouse-down")
        onSelectionDragChanged?(location, true)
    }

    private func finishSelectionDrag() {
        guard isSelectionDragging else { return }
        isSelectionDragging = false
        let location = CGEvent(source: nil)?.location ?? CGPoint.zero
        DiagnosticLog.write("double tap second touch released; selection/drag mouse-up")
        onSelectionDragChanged?(location, false)
    }

    private func releaseSelectionDrag() {
        finishSelectionDrag()
    }

    private func resetTouchTracking() {
        cancelPendingSingleClick()
        twoFingerTapDetector.reset()
        cancelSingleTouchTracking()
        lastSingleTapTimestamp = nil
        lastSingleTapLocation = nil
        touchStartedDuringScroll = false
        suppressSingleTouchUntilLift = false
    }

    private func cancelSingleTouchTracking() {
        tapDetector.reset()
        activeTouch = -1
        touchStartX = 0.0
        touchStartY = 0.0
        touchStartedDuringScroll = false
    }

    deinit {
        stop()
    }
}

private func touchCallback(device: Int32, touches: UnsafeMutablePointer<MTTouch>?, numTouches: Int32, timestamp: Double, frame: Int32) -> Int32 {
    if let manager = MultitouchManager.sharedInstance, let touches = touches {
        manager.processTouches(touches, numTouches: Int(numTouches), timestamp: timestamp)
    }
    return 0
}
