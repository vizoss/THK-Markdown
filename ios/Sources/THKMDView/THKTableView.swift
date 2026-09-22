import UIKit

/// Renders a `THKTableModel` as a real, column-aligned, horizontally scrollable table — not a
/// plain-text fallback. Layout is manual (frame-based): each column's width is the natural
/// width of its widest cell (measured via `UILabel.sizeThatFits`), capped at `maxColumnWidth`
/// so one huge cell can't blow out the whole table, and the content view is sized to the sum
/// of column widths so `UIScrollView` scrolls horizontally whenever that exceeds the view's
/// own width. `intrinsicContentSize` reports the actual rendered height so the table sizes
/// correctly inside the containing (vertical) `UIStackView` — a bare `UIScrollView`'s
/// intrinsic size is otherwise ambiguous.
public final class THKTableView: UIScrollView {
    private let contentContainer = UIView()
    private let cellPadding = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
    private let maxColumnWidth: CGFloat = 240
    private let minRowHeight: CGFloat = 32
    private var renderedHeight: CGFloat = 0

    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        translatesAutoresizingMaskIntoConstraints = false
        showsHorizontalScrollIndicator = true
        showsVerticalScrollIndicator = false
        addSubview(contentContainer)
    }

    public func configure(model: THKTableModel, theme: THKMDTheme) {
        contentContainer.subviews.forEach { $0.removeFromSuperview() }

        let allRows = [model.headerCells] + model.rows
        let columnCount = max(model.alignments.count, allRows.map(\.count).max() ?? 0)
        guard columnCount > 0 else {
            renderedHeight = 0
            contentSize = .zero
            invalidateIntrinsicContentSize()
            return
        }

        var labelGrid: [[UILabel]] = []
        var columnWidths = [CGFloat](repeating: 0, count: columnCount)

        for row in allRows {
            var rowLabels: [UILabel] = []
            for column in 0..<columnCount {
                let label = UILabel()
                label.numberOfLines = 0
                label.attributedText = column < row.count ? row[column] : NSAttributedString(string: "")
                let alignment = column < model.alignments.count ? model.alignments[column] : .leading
                label.textAlignment = alignment.textAlignment
                rowLabels.append(label)

                let natural = label.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
                let cellWidth = min(natural.width + cellPadding.left + cellPadding.right, maxColumnWidth)
                columnWidths[column] = max(columnWidths[column], cellWidth)
            }
            labelGrid.append(rowLabels)
        }

        var rowHeights: [CGFloat] = []
        for rowLabels in labelGrid {
            var rowHeight: CGFloat = minRowHeight
            for (column, label) in rowLabels.enumerated() {
                let textWidth = columnWidths[column] - cellPadding.left - cellPadding.right
                let fit = label.sizeThatFits(CGSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude))
                rowHeight = max(rowHeight, fit.height + cellPadding.top + cellPadding.bottom)
            }
            rowHeights.append(rowHeight)
        }

        let hairline = 1.0 / max(UIScreen.main.scale, 1)
        var currentY: CGFloat = 0
        for (rowIndex, rowLabels) in labelGrid.enumerated() {
            let isHeader = rowIndex == 0
            let rowHeight = rowHeights[rowIndex]
            var currentX: CGFloat = 0
            for (column, label) in rowLabels.enumerated() {
                let width = columnWidths[column]
                let cellView = UIView(frame: CGRect(x: currentX, y: currentY, width: width, height: rowHeight))
                cellView.backgroundColor = isHeader ? theme.tableHeaderBackgroundColor : .clear
                cellView.layer.borderWidth = hairline
                cellView.layer.borderColor = theme.tableBorderColor.cgColor
                label.frame = CGRect(
                    x: cellPadding.left,
                    y: cellPadding.top,
                    width: width - cellPadding.left - cellPadding.right,
                    height: rowHeight - cellPadding.top - cellPadding.bottom
                )
                cellView.addSubview(label)
                contentContainer.addSubview(cellView)
                currentX += width
            }
            currentY += rowHeight
        }

        let totalWidth = columnWidths.reduce(0, +)
        contentContainer.frame = CGRect(x: 0, y: 0, width: totalWidth, height: currentY)
        contentSize = CGSize(width: totalWidth, height: currentY)
        renderedHeight = currentY
        invalidateIntrinsicContentSize()
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: renderedHeight)
    }
}

private extension THKTableColumnAlignment {
    var textAlignment: NSTextAlignment {
        switch self {
        case .leading: return .left
        case .center: return .center
        case .trailing: return .right
        }
    }
}
