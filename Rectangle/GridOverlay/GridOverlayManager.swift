//
//  GridOverlayManager.swift
//  Rectangle
//
//  Copyright © 2026 Ryan Hanson. All rights reserved.
//

import Cocoa
import Carbon

class GridOverlayManager {

    private static var panel: GridOverlayPanel?
    private static var keyboardMonitor: PassiveEventMonitor?
    private static var clickMonitor: PassiveEventMonitor?
    private static var capturedWindow: AccessibilityElement?
    private static var capturedWindowId: CGWindowID?
    private static var capturedScreen: NSScreen?
    private static var originalFrame: CGRect?

    // MARK: - Interceptor

    static func execute(parameters: ExecutionParameters) -> Bool {
        guard parameters.action == .gridOverlay else { return false }

        if panel != nil {
            dismiss()
            return true
        }

        guard let windowElement = parameters.windowElement ?? AccessibilityElement.getFrontWindowElement(),
              let windowId = parameters.windowId ?? windowElement.getWindowId()
        else {
            Logger.log("Grid overlay: no frontmost window found")
            NSSound.beep()
            return true
        }

        let screen: NSScreen
        if let paramScreen = parameters.screen {
            screen = paramScreen
        } else if Defaults.useCursorScreenDetection.enabled {
            screen = ScreenDetection().detectScreensAtCursor()?.currentScreen ?? NSScreen.main ?? NSScreen.screens[0]
        } else {
            screen = ScreenDetection().detectScreens(using: windowElement)?.currentScreen ?? NSScreen.main ?? NSScreen.screens[0]
        }

        Logger.log("Grid overlay: showing on \(screen.localizedName)")
        show(on: screen, windowElement: windowElement, windowId: windowId)
        return true
    }

    // MARK: - Lifecycle

    private static func show(on screen: NSScreen, windowElement: AccessibilityElement, windowId: CGWindowID) {
        if let existingPanel = panel {
            removeMonitors()
            existingPanel.orderOut(nil)
            panel = nil
        }

        capturedWindow = windowElement
        capturedWindowId = windowId
        capturedScreen = screen
        originalFrame = windowElement.frame

        let rows = max(2, Defaults.gridOverlayRows.value)
        let cols = max(2, Defaults.gridOverlayCols.value)

        let newPanel = GridOverlayPanel(rows: rows, cols: cols)
        newPanel.gridView.onSelection = { selection in
            applySelection(selection, rows: newPanel.gridView.rows, cols: newPanel.gridView.cols)
        }
        newPanel.gridView.onDragChanged = { selection in
            updateStatusLabel(selection: selection, rows: newPanel.gridView.rows, cols: newPanel.gridView.cols)
            livePreview(selection: selection, rows: newPanel.gridView.rows, cols: newPanel.gridView.cols)
        }
        newPanel.gridView.onDragCancelled = {
            restoreOriginalFrame()
        }

        panel = newPanel
        newPanel.showCentered(on: screen)

        installMonitors()
    }

    /// Dismisses the overlay. Restores the window to its original position
    /// unless `originalFrame` was already cleared by a successful commit.
    static func dismiss() {
        restoreOriginalFrame()

        // Prevent stale mouseUp from firing onSelection after teardown
        panel?.gridView.resetDragState()

        removeMonitors()

        let dyingPanel = panel
        panel = nil
        capturedWindow = nil
        capturedWindowId = nil
        capturedScreen = nil
        originalFrame = nil

        dyingPanel?.dismissAnimated()
    }

    /// Dismisses without restoring — used after a successful commit where the
    /// window is already at its target position.
    private static func dismissWithoutRestore() {
        originalFrame = nil
        dismiss()
    }

    // MARK: - Status Label

    private static func updateStatusLabel(selection: GridSelection?, rows: Int, cols: Int) {
        guard let panel = panel else { return }

        if let sel = selection {
            let widthPct = Int(round(Double(sel.colSpan) / Double(cols) * 100))
            let heightPct = Int(round(Double(sel.rowSpan) / Double(rows) * 100))
            panel.updateStatus("\(sel.colSpan)×\(sel.rowSpan) cells  ·  \(widthPct)% × \(heightPct)%")
        } else {
            panel.updateStatus("\(cols) × \(rows)")
        }
    }

    // MARK: - Live Preview

    private static func computeTargetRect(selection: GridSelection, rows: Int, cols: Int) -> CGRect? {
        guard let screen = capturedScreen else { return nil }

        let visibleFrame = screen.adjustedVisibleFrame()
        let cellWidth = visibleFrame.width / CGFloat(cols)
        let cellHeight = visibleFrame.height / CGFloat(rows)

        // GridView is flipped (row 0 = top), NSScreen has origin at bottom-left
        let targetRect = CGRect(
            x: visibleFrame.origin.x + CGFloat(selection.minCol) * cellWidth,
            y: visibleFrame.maxY - CGFloat(selection.maxRow + 1) * cellHeight,
            width: CGFloat(selection.maxCol - selection.minCol + 1) * cellWidth,
            height: CGFloat(selection.maxRow - selection.minRow + 1) * cellHeight
        )

        var sharedEdges: Edge = .none
        if selection.minCol > 0 { sharedEdges.insert(.left) }
        if selection.maxCol < cols - 1 { sharedEdges.insert(.right) }
        if selection.minRow > 0 { sharedEdges.insert(.top) }
        if selection.maxRow < rows - 1 { sharedEdges.insert(.bottom) }

        let gapSize = Defaults.gapSize.value
        return gapSize > 0
            ? GapCalculation.applyGaps(targetRect, sharedEdges: sharedEdges, gapSize: gapSize)
            : targetRect
    }

    private static func livePreview(selection: GridSelection?, rows: Int, cols: Int) {
        guard let windowElement = capturedWindow,
              let selection = selection,
              let rect = computeTargetRect(selection: selection, rows: rows, cols: cols)
        else { return }
        windowElement.setFrame(rect.screenFlipped)
    }

    private static func restoreOriginalFrame() {
        guard let windowElement = capturedWindow,
              let original = originalFrame
        else { return }
        windowElement.setFrame(original)
        originalFrame = nil
    }

    // MARK: - Selection → Resize

    private static func applySelection(_ selection: GridSelection, rows: Int, cols: Int) {
        guard let windowElement = capturedWindow,
              let windowId = capturedWindowId
        else {
            Logger.log("Grid overlay: no captured window to resize")
            dismissWithoutRestore()
            return
        }

        guard let gapped = computeTargetRect(selection: selection, rows: rows, cols: cols) else {
            Logger.log("Grid overlay: unable to compute target rect")
            dismissWithoutRestore()
            return
        }

        if let original = originalFrame {
            AppDelegate.windowHistory.restoreRects[windowId] = original
        }

        let flippedRect = gapped.screenFlipped
        windowElement.setFrame(flippedRect)

        Logger.log("Grid overlay: resized window to \(flippedRect.debugDescription)")

        AppDelegate.windowHistory.lastRectangleActions[windowId] = RectangleAction(
            action: .gridOverlay,
            subAction: nil,
            rect: flippedRect,
            count: 1
        )

        dismissWithoutRestore()
    }

    // MARK: - Event Monitors

    private static func installMonitors() {
        keyboardMonitor = PassiveEventMonitor(mask: .keyDown) { event in
            DispatchQueue.main.async { handleKeyDown(event) }
        }
        keyboardMonitor?.start()

        clickMonitor = PassiveEventMonitor(mask: .leftMouseDown) { _ in
            DispatchQueue.main.async {
                guard let panel = panel else { return }
                if !panel.frame.contains(NSEvent.mouseLocation) {
                    dismiss()
                }
            }
        }
        clickMonitor?.start()
    }

    private static func handleKeyDown(_ event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Escape:
            dismiss()
        default:
            break
        }
    }

    private static func removeMonitors() {
        keyboardMonitor?.stop()
        keyboardMonitor = nil

        clickMonitor?.stop()
        clickMonitor = nil
    }
}
