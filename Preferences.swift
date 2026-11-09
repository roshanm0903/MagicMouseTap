import Foundation

/// User-adjustable settings, persisted in UserDefaults.
enum Preferences {
    static let rightClickThresholdKey = "rightClickThreshold"

    private static let tapDurationKey = "tapDuration"
    private static let tapSensitivityKey = "tapSensitivity"
    private static let cursorMovementToleranceKey = "cursorMovementTolerance"
    private static let surfaceMovementToleranceKey = "surfaceMovementTolerance"
    private static let doubleTapIntervalKey = "doubleTapInterval"
    private static let zoomSwipeDistanceKey = "zoomSwipeDistance"
    private static let dragStartDistanceKey = "dragStartDistance"
    private static let scrollStopWindowKey = "scrollStopWindow"

    static let defaultTapDuration = 0.30
    static let defaultTapSensitivity = 0.35
    static let defaultCursorMovementTolerance = 0.75
    static let defaultSurfaceMovementTolerance = 0.04
    static let defaultDoubleTapInterval = 0.55
    static let defaultZoomSwipeDistance = 0.035
    static let defaultDragStartDistance = 6.0
    static let defaultScrollStopWindow = 0.35

    /// Fraction of the mouse surface (0-1) to the left of which taps count as a left click.
    /// A tap with normalized x above this value is a right click.
    static let defaultRightClickThreshold: Float = 0.6

    /// Values offered in the menu bar. Anything set outside this list (e.g. via
    /// `defaults write com.mousetoucher.app rightClickThreshold 0.75`) is still honoured.
    static let rightClickThresholdChoices: [Float] = [0.4, 0.5, 0.6, 0.7, 0.8, 0.9]

    static let minRightClickThreshold: Float = 0.1
    static let maxRightClickThreshold: Float = 0.95

    static var rightClickThreshold: Float {
        get {
            guard UserDefaults.standard.object(forKey: rightClickThresholdKey) != nil else {
                return defaultRightClickThreshold
            }
            return clamp(UserDefaults.standard.float(forKey: rightClickThresholdKey))
        }
        set {
            UserDefaults.standard.set(clamp(newValue), forKey: rightClickThresholdKey)
        }
    }

    static func clamp(_ value: Float) -> Float {
        guard value.isFinite else { return defaultRightClickThreshold }
        return min(max(value, minRightClickThreshold), maxRightClickThreshold)
    }

    static var tapDuration: Double {
        get { stored(tapDurationKey, defaultTapDuration, 0.15...0.50) }
        set { store(newValue, tapDurationKey, 0.15...0.50) }
    }

    /// A single human-friendly control layered over the detailed tap thresholds. Lower values
    /// tighten duration and movement allowances; higher values make taps easier to recognize.
    static var tapSensitivity: Double {
        get { stored(tapSensitivityKey, defaultTapSensitivity, 0.0...1.0) }
        set { store(newValue, tapSensitivityKey, 0.0...1.0) }
    }

    static var tapSensitivityMultiplier: Double {
        0.55 + (tapSensitivity * 0.90)
    }

    static var effectiveTapDuration: Double {
        tapDuration * tapSensitivityMultiplier
    }

    static var effectiveCursorMovementTolerance: Double {
        cursorMovementTolerance * tapSensitivityMultiplier
    }

    static var effectiveSurfaceMovementTolerance: Double {
        surfaceMovementTolerance * tapSensitivityMultiplier
    }

    static var cursorMovementTolerance: Double {
        get { stored(cursorMovementToleranceKey, defaultCursorMovementTolerance, 0.25...8.0) }
        set { store(newValue, cursorMovementToleranceKey, 0.25...8.0) }
    }

    static var surfaceMovementTolerance: Double {
        get { stored(surfaceMovementToleranceKey, defaultSurfaceMovementTolerance, 0.02...0.10) }
        set { store(newValue, surfaceMovementToleranceKey, 0.02...0.10) }
    }

    static var doubleTapInterval: Double {
        get { stored(doubleTapIntervalKey, defaultDoubleTapInterval, 0.25...0.85) }
        set { store(newValue, doubleTapIntervalKey, 0.25...0.85) }
    }

    static var zoomSwipeDistance: Double {
        get { stored(zoomSwipeDistanceKey, defaultZoomSwipeDistance, 0.015...0.10) }
        set { store(newValue, zoomSwipeDistanceKey, 0.015...0.10) }
    }

    static var dragStartDistance: Double {
        get { stored(dragStartDistanceKey, defaultDragStartDistance, 2.0...20.0) }
        set { store(newValue, dragStartDistanceKey, 2.0...20.0) }
    }

    static var scrollStopWindow: Double {
        get { stored(scrollStopWindowKey, defaultScrollStopWindow, 0.15...0.70) }
        set { store(newValue, scrollStopWindowKey, 0.15...0.70) }
    }

    static func resetGestureSensitivity() {
        tapSensitivity = defaultTapSensitivity
        tapDuration = defaultTapDuration
        cursorMovementTolerance = defaultCursorMovementTolerance
        surfaceMovementTolerance = defaultSurfaceMovementTolerance
        doubleTapInterval = defaultDoubleTapInterval
        zoomSwipeDistance = defaultZoomSwipeDistance
        dragStartDistance = defaultDragStartDistance
        scrollStopWindow = defaultScrollStopWindow
    }

    private static func stored(
        _ key: String,
        _ defaultValue: Double,
        _ range: ClosedRange<Double>
    ) -> Double {
        guard UserDefaults.standard.object(forKey: key) != nil else { return defaultValue }
        return min(max(UserDefaults.standard.double(forKey: key), range.lowerBound), range.upperBound)
    }

    private static func store(
        _ value: Double,
        _ key: String,
        _ range: ClosedRange<Double>
    ) {
        guard value.isFinite else { return }
        UserDefaults.standard.set(min(max(value, range.lowerBound), range.upperBound), forKey: key)
    }
}
