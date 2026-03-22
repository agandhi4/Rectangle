//
//  GridView.swift
//  Rectangle
//
//  Copyright © 2026 Ryan Hanson. All rights reserved.
//

import Cocoa

struct GridSelection {
    let startCol: Int
    let startRow: Int
    let endCol: Int
    let endRow: Int

    var minCol: Int { min(startCol, endCol) }
    var maxCol: Int { max(startCol, endCol) }
    var minRow: Int { min(startRow, endRow) }
    var maxRow: Int { max(startRow, endRow) }

    var colSpan: Int { maxCol - minCol + 1 }
    var rowSpan: Int { maxRow - minRow + 1 }
}

class GridView: NSView {

    static let defaultCellSize: CGFloat = 40
    static let cellPadding: CGFloat = 3

    let rows: Int
    let cols: Int
    var onSelection: ((GridSelection) -> Void)?
    var onDragChanged: ((GridSelection?) -> Void)?
    var onDragCancelled: (() -> Void)?

    private var dragStart: (col: Int, row: Int)?
    private var dragCurrent: (col: Int, row: Int)?

    private static let cellCornerRadius: CGFloat = 4
    private static let cellColorAlpha: CGFloat = 0.25
    private static let selectedColorAlpha: CGFloat = 0.6

    private let gapColor = NSColor.secondaryLabelColor.withAlphaComponent(0.3)

    init(rows: Int, cols: Int) {
        self.rows = rows
        self.cols = cols
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Top-left origin so row 0 draws at the top of the panel,
    // matching the user's expectation that the grid mirrors the screen.
    override var isFlipped: Bool { true }

    // Prevent clicks on the grid from dragging the panel
    override var mouseDownCanMoveWindow: Bool { false }

    /// The total size needed to draw a grid with the given dimensions.
    static func size(rows: Int, cols: Int) -> NSSize {
        let width = CGFloat(cols) * (defaultCellSize + cellPadding) + cellPadding
        let height = CGFloat(rows) * (defaultCellSize + cellPadding) + cellPadding
        return NSSize(width: width, height: height)
    }

    // MARK: - Geometry

    private var cellWidth: CGFloat {
        (bounds.width - Self.cellPadding * CGFloat(cols + 1)) / CGFloat(cols)
    }

    private var cellHeight: CGFloat {
        (bounds.height - Self.cellPadding * CGFloat(rows + 1)) / CGFloat(rows)
    }

    private func cellRect(col: Int, row: Int) -> NSRect {
        let x = Self.cellPadding + CGFloat(col) * (cellWidth + Self.cellPadding)
        let y = Self.cellPadding + CGFloat(row) * (cellHeight + Self.cellPadding)
        return NSRect(x: x, y: y, width: cellWidth, height: cellHeight)
    }

    private func isCellSelected(col: Int, row: Int) -> Bool {
        guard let start = dragStart, let current = dragCurrent else { return false }
        let minCol = min(start.col, current.col)
        let maxCol = max(start.col, current.col)
        let minRow = min(start.row, current.row)
        let maxRow = max(start.row, current.row)
        return col >= minCol && col <= maxCol && row >= minRow && row <= maxRow
    }

    private var currentSelection: GridSelection? {
        guard let start = dragStart, let current = dragCurrent else { return nil }
        return GridSelection(startCol: start.col, startRow: start.row,
                             endCol: current.col, endRow: current.row)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        gapColor.setFill()
        bounds.fill()

        for row in 0..<rows {
            for col in 0..<cols {
                let rect = cellRect(col: col, row: row)
                let selected = isCellSelected(col: col, row: row)
                let color = selected
                    ? NSColor.controlAccentColor.withAlphaComponent(Self.selectedColorAlpha)
                    : NSColor.controlBackgroundColor.withAlphaComponent(Self.cellColorAlpha)
                color.setFill()
                let path = NSBezierPath(roundedRect: rect, xRadius: Self.cellCornerRadius, yRadius: Self.cellCornerRadius)
                path.fill()
            }
        }
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let col = Swift.min(Swift.max(Int((point.x - Self.cellPadding) / (cellWidth + Self.cellPadding)), 0), cols - 1)
        let row = Swift.min(Swift.max(Int((point.y - Self.cellPadding) / (cellHeight + Self.cellPadding)), 0), rows - 1)
        dragStart = (col, row)
        dragCurrent = (col, row)
        needsDisplay = true
        onDragChanged?(currentSelection)
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragStart != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        let col = Swift.min(Swift.max(Int((point.x - Self.cellPadding) / (cellWidth + Self.cellPadding)), 0), cols - 1)
        let row = Swift.min(Swift.max(Int((point.y - Self.cellPadding) / (cellHeight + Self.cellPadding)), 0), rows - 1)
        if dragCurrent?.col == col && dragCurrent?.row == row { return }
        dragCurrent = (col, row)
        needsDisplay = true
        onDragChanged?(currentSelection)
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = dragStart, let current = dragCurrent else { return }
        let selection = GridSelection(
            startCol: start.col,
            startRow: start.row,
            endCol: current.col,
            endRow: current.row
        )
        dragStart = nil
        dragCurrent = nil
        needsDisplay = true
        onSelection?(selection)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard dragStart != nil else { return }
        resetDragState()
        onDragChanged?(nil)
        onDragCancelled?()
    }

    /// Clears in-flight drag state without firing callbacks.
    /// Used by the manager to prevent stale mouseUp events during dismiss.
    func resetDragState() {
        dragStart = nil
        dragCurrent = nil
        needsDisplay = true
    }
}
