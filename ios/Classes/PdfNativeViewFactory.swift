import Flutter
import UIKit

final class PdfNativeViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> any FlutterPlatformView {
    let creationParams = args as? [String: Any]
    return PdfNativeView(
      frame: frame,
      viewId: viewId,
      messenger: messenger,
      creationParams: creationParams
    )
  }
}
