import UIKit

/// A scrollable table with TextKit cells, sharing text, link and image behavior with body segments.
public final class THKTableView: UIScrollView, UITextViewDelegate {
    public var onLinkTap: ((URL) -> Bool)?
    public var onImageTap: ((URL) -> Bool)?
    public var onSizeChange: (() -> Void)?
    public var imageLoader: THKImageLoading = DefaultTHKImageLoader()
    private let contentContainer = UIView()
    private let gridLayer = CAShapeLayer()
    private let cellPadding = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
    private let maxColumnWidth: CGFloat = 240
    /// Match Android: total cell width including 10pt padding on each side.
    private let minColumnWidth: CGFloat = 48
    private var renderedHeight: CGFloat = 0
    private var rows: [[UITextView]] = []
    private var cells: [[UIView]] = []
    private var attachments: [THKAsyncImageTextAttachment] = []

    public override init(frame: CGRect) { super.init(frame: frame); commonInit() }
    public required init?(coder: NSCoder) { super.init(coder: coder); commonInit() }
    private func commonInit() {
        translatesAutoresizingMaskIntoConstraints = false
        showsHorizontalScrollIndicator = true
        showsVerticalScrollIndicator = false
        addSubview(contentContainer)
        contentContainer.layer.addSublayer(gridLayer)
    }

    public func cancelImageLoads() {
        attachments.forEach { $0.cancelLoading() }
        attachments.removeAll()
    }

    public func configure(model: THKTableModel, theme: THKMDTheme) {
        cancelImageLoads()
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        rows.removeAll()
        cells.removeAll()
        gridLayer.path = nil
        gridLayer.fillColor = theme.tableBorderColor.cgColor
        let allRows = [model.headerCells] + model.rows
        let columns = max(model.alignments.count, allRows.map(\.count).max() ?? 0)
        guard columns > 0 else {
            renderedHeight = 0; contentSize = .zero; invalidateIntrinsicContentSize()
            return
        }
        for (rowIndex, values) in allRows.enumerated() {
            var textRow: [UITextView] = []
            var cellRow: [UIView] = []
            for column in 0..<columns {
                let storage = NSTextStorage()
                let manager = THKBackgroundLayoutManager()
                manager.inlineCodeBackgroundColor = theme.codeBackgroundColor
                let container = NSTextContainer(size: .zero)
                container.lineFragmentPadding = 0
                storage.addLayoutManager(manager)
                manager.addTextContainer(container)
                let text = UITextView(frame: .zero, textContainer: container)
                text.isScrollEnabled = false
                text.isEditable = false
                text.isSelectable = true
                text.backgroundColor = .clear
                text.textContainerInset = .zero
                text.delegate = self
                text.linkTextAttributes = [.foregroundColor: theme.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
                let value = NSMutableAttributedString(attributedString: column < values.count ? values[column] : NSAttributedString(string: ""))
                let alignment = column < model.alignments.count ? model.alignments[column] : .leading
                value.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: value.length)) { existing, range, _ in
                    let style = (existing as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                    switch alignment {
                    case .leading: style.alignment = .left
                    case .center: style.alignment = .center
                    case .trailing: style.alignment = .right
                    }
                    value.addAttribute(.paragraphStyle, value: style, range: range)
                }
                text.attributedText = value
                let cell = UIView()
                cell.backgroundColor = rowIndex == 0 ? theme.tableHeaderBackgroundColor : .clear
                cell.addSubview(text)
                contentContainer.addSubview(cell)
                textRow.append(text)
                cellRow.append(cell)
                value.enumerateAttribute(.attachment, in: NSRange(location: 0, length: value.length)) { value, _, _ in
                    guard let attachment = value as? THKAsyncImageTextAttachment else { return }
                    self.attachments.append(attachment)
                    attachment.onSizeChange = { [weak self] in
                        self?.layoutCells()
                        self?.onSizeChange?()
                    }
                    attachment.startLoading(imageLoader: self.imageLoader, into: text.textStorage)
                }
            }
            rows.append(textRow)
            cells.append(cellRow)
        }
        layoutCells()
    }

    private func layoutCells() {
        guard let first = rows.first, !first.isEmpty else { return }
        let horizontalPadding = cellPadding.left + cellPadding.right
        for attachment in attachments where attachment.bounds.width > maxColumnWidth - horizontalPadding {
            let scale = (maxColumnWidth - horizontalPadding) / attachment.bounds.width
            attachment.bounds.size = CGSize(width: attachment.bounds.width * scale, height: attachment.bounds.height * scale)
        }
        var widths = [CGFloat](repeating: minColumnWidth, count: first.count)
        for row in rows {
            for (column, text) in row.enumerated() {
                // UITextView.sizeThatFits returns the proposed width, not natural
                // text width; measuring the attributed content avoids all-wide columns.
                let fit = text.attributedText.boundingRect(
                    with: CGSize(width: maxColumnWidth - horizontalPadding, height: CGFloat.greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).size
                widths[column] = max(widths[column], min(maxColumnWidth, ceil(fit.width) + horizontalPadding))
            }
        }
        var y: CGFloat = 0
        for (rowIndex, row) in rows.enumerated() {
            let heights = row.enumerated().map { column, text in
                text.sizeThatFits(CGSize(width: widths[column] - horizontalPadding, height: CGFloat.greatestFiniteMagnitude)).height
            }
            let height = max(32, ceil(heights.max() ?? 0) + cellPadding.top + cellPadding.bottom)
            var x: CGFloat = 0
            for (column, text) in row.enumerated() {
                let cell = cells[rowIndex][column]
                cell.frame = CGRect(x: x, y: y, width: widths[column], height: height)
                text.frame = CGRect(x: cellPadding.left, y: cellPadding.top,
                                    width: widths[column] - horizontalPadding, height: height - cellPadding.top - cellPadding.bottom)
                x += widths[column]
            }
            y += height
        }
        let width = widths.reduce(0, +)
        renderedHeight = y
        contentContainer.frame = CGRect(x: 0, y: 0, width: width, height: y)
        // Paint each grid edge once, on physical pixels; adjacent cells must not
        // double the internal border while the outside border remains single-width.
        let pixel = 1 / max(UIScreen.main.scale, 1)
        let path = UIBezierPath()
        for row in cells {
            if let cell = row.first { path.append(UIBezierPath(rect: CGRect(x: 0, y: cell.frame.minY, width: width, height: pixel))) }
        }
        path.append(UIBezierPath(rect: CGRect(x: 0, y: max(0, y - pixel), width: width, height: pixel)))
        for cell in cells.first ?? [] {
            path.append(UIBezierPath(rect: CGRect(x: cell.frame.minX, y: 0, width: pixel, height: y)))
        }
        path.append(UIBezierPath(rect: CGRect(x: max(0, width - pixel), y: 0, width: pixel, height: y)))
        gridLayer.frame = contentContainer.bounds
        gridLayer.path = path.cgPath
        gridLayer.zPosition = 1
        contentSize = CGSize(width: width, height: y)
        invalidateIntrinsicContentSize()
    }

    public override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: renderedHeight) }

    public func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        !(onLinkTap?(URL) ?? false)
    }

    public func textView(_ textView: UITextView, shouldInteractWith textAttachment: NSTextAttachment, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        guard let image = textAttachment as? THKAsyncImageTextAttachment else { return false }
        if image.url.scheme == "thk-math" { return false }
        return !((onImageTap ?? onLinkTap)?(image.url) ?? false)
    }
}
