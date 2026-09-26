require 'minitest/autorun'
require_relative 'normalize-swift-interfaces'

class SwiftInterfacesTest < Minitest::Test
  def test_only_self_module_type_qualification_is_removed
    source = <<~SWIFT
      import UIKit
      public struct THKMDTheme : Swift.Equatable {
        public static func == (a: THKMDView.THKMDTheme, b: THKMDView.THKMDTheme) -> Swift.Bool
      }
      @objc final public class THKMDView : UIKit.UIView {}
      extension THKMDView.THKMDTheme : Swift.Hashable {}
      // THKMDView.THKMDTheme must remain in comments.
      public let message = "THKMDView.THKMDTheme"
      public let view = THKMDView.defaultView
      public let foreign: OtherKit.THKMDTheme
    SWIFT
    result = THKSwiftInterfaces.normalize(source)
    assert_includes result, '(a: THKMDTheme, b: THKMDTheme)'
    assert_includes result, 'extension THKMDTheme : Swift.Hashable'
    assert_includes result, '// THKMDView.THKMDTheme'
    assert_includes result, '"THKMDView.THKMDTheme"'
    assert_includes result, 'THKMDView.defaultView'
    assert_includes result, 'OtherKit.THKMDTheme'
    assert_equal result, THKSwiftInterfaces.normalize(result)
  end

  def test_wrong_module_is_rejected
    assert_raises(RuntimeError) { THKSwiftInterfaces.normalize('public struct Other {}') }
  end
end
