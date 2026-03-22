//
//  GridOverlayPanel.swift
//  Rectangle
//
//  Copyright © 2026 Ryan Hanson. All rights reserved.
//

import Cocoa

class GridOverlayPanel: NSPanel {

    let gridView: GridView
    private let statusLabel: NSTextField

    private static let gridInset: CGFloat = 12
    private static let verticalPadding: CGFloat = 8
    private static let statusLabelHeight: CGFloat = 14
    private static let statusLabelFontSize: CGFloat = 11
    private static let gridCornerRadius: CGFloat = 6
    private static let animationDuration: TimeInterval = 0.15

    init(rows: Int, cols: Int) {
        gridView = GridView(rows: rows, cols: cols)

        statusLabel = NSTextField(labelWithString: "\(cols) × \(rows)")
        statusLabel.font = .systemFont(ofSize: GridOverlayPanel.statusLabelFontSize, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center

        let gridSize = GridView.size(rows: rows, cols: cols)
        let totalWidth = gridSize.width + GridOverlayPanel.gridInset * 2
        let contentHeight = GridOverlayPanel.verticalPadding
            + gridSize.height
            + GridOverlayPanel.verticalPadding
            + GridOverlayPanel.statusLabelHeight
            + GridOverlayPanel.verticalPadding

        let initialRect = NSRect(x: 0, y: 0, width: totalWidth, height: contentHeight)
        super.init(
            contentRect: initialRect,
            styleMask: [.nonactivatingPanel, .titled],
            backing: .buffered,
            defer: false
        )

        title = "Rectangle"
        level = .modalPanel
        isOpaque = false
        hasShadow = true
        isReleasedWhenClosed = false
        isMovable = true
        isMovableByWindowBackground = true
        collectionBehavior.insert(.transient)
        becomesKeyOnlyIfNeeded = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        let container = NSVisualEffectView(frame: initialRect)
        container.material = .popover
        container.state = .active
        container.wantsLayer = true
        container.autoresizingMask = [.width, .height]

        gridView.wantsLayer = true
        gridView.layer?.cornerRadius = GridOverlayPanel.gridCornerRadius
        gridView.layer?.masksToBounds = true

        gridView.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(gridView)
        container.addSubview(statusLabel)
        contentView = container

        // The title bar is a standard opaque bar above the content view.
        // Layout is anchored to the container (which is the content view,
        // positioned below the title bar by AppKit).
        NSLayoutConstraint.activate([
            gridView.topAnchor.constraint(equalTo: container.topAnchor, constant: GridOverlayPanel.verticalPadding),
            gridView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: GridOverlayPanel.gridInset),
            gridView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -GridOverlayPanel.gridInset),
            gridView.heightAnchor.constraint(equalToConstant: gridSize.height),

            statusLabel.topAnchor.constraint(equalTo: gridView.bottomAnchor, constant: GridOverlayPanel.verticalPadding),
            statusLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: GridOverlayPanel.gridInset),
            statusLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -GridOverlayPanel.gridInset),
            statusLabel.heightAnchor.constraint(equalToConstant: GridOverlayPanel.statusLabelHeight),
        ])
    }

    func updateStatus(_ text: String) {
        statusLabel.stringValue = text
    }

    func showCentered(on screen: NSScreen) {
        let screenFrame = screen.adjustedVisibleFrame()
        let panelFrame = frame
        let x = screenFrame.midX - panelFrame.width / 2
        let y = screenFrame.midY - panelFrame.height / 2
        setFrameOrigin(NSPoint(x: x, y: y))

        alphaValue = 0
        orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = GridOverlayPanel.animationDuration
            animator().alphaValue = 1
        }
    }

    func dismissAnimated(completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = GridOverlayPanel.animationDuration
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            completion?()
        })
    }
}
