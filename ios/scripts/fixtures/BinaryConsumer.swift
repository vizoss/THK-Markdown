import UIKit
import THKMDView

// Compile and link only; never launch a simulator or execute this function.
@MainActor
public func makeBinaryMarkdownView() -> UIView {
    let view = THKMDView()
    var theme = THKMDTheme.default
    theme.bodyTextColor = .label
    view.theme = theme
    view.setMarkdown("# Binary consumer\n\n**Hello**")
    return view
}

public func themesEqual(_ lhs: THKMDTheme, _ rhs: THKMDTheme) -> Bool {
    lhs == rhs
}
