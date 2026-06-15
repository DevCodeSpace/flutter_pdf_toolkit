import Flutter
import UIKit
import PDFKit

public class FlutterPdfToolkitPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    // Register global method channel
    let channel = FlutterMethodChannel(name: "flutter_pdf_toolkit", binaryMessenger: registrar.messenger())
    let instance = FlutterPdfToolkitPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)

    // Register view factory
    let factory = PdfNativeViewFactory(messenger: registrar.messenger())
    registrar.register(factory, withId: "flutter_pdf_toolkit/native_view")
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "mergePdfs":
      guard let args = call.arguments as? [String: Any],
            let paths = args["paths"] as? [String],
            let outputPath = args["outputPath"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "paths and outputPath are required", details: nil))
        return
      }
      
      DispatchQueue.global(qos: .userInitiated).async {
        let success = self.mergePDFs(paths: paths, outputPath: outputPath)
        DispatchQueue.main.async {
          if success {
            result(outputPath)
          } else {
            result(nil)
          }
        }
      }
      
    case "getPdfPageCount":
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "path is required", details: nil))
        return
      }

      DispatchQueue.global(qos: .userInitiated).async {
        let url = URL(fileURLWithPath: path)
        let pageCount = PDFDocument(url: url)?.pageCount
        DispatchQueue.main.async {
          result(pageCount)
        }
      }

    case "splitPdf":
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String,
            let outputDirectory = args["outputDirectory"] as? String,
            let pageRanges = args["pageRanges"] as? [[Int]] else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "path, outputDirectory and pageRanges are required", details: nil))
        return
      }
      let prefix = (args["outputFileNamePrefix"] as? String) ?? "split"

      DispatchQueue.global(qos: .userInitiated).async {
        let outputPaths = self.splitPDF(path: path, outputDirectory: outputDirectory, pageRanges: pageRanges, prefix: prefix)
        DispatchQueue.main.async {
          result(outputPaths)
        }
      }

    case "reorderPdf":
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String,
            let outputPath = args["outputPath"] as? String,
            let pageOrder = args["pageOrder"] as? [Int] else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "path, outputPath and pageOrder are required", details: nil))
        return
      }

      DispatchQueue.global(qos: .userInitiated).async {
        let success = self.reorderPDF(path: path, outputPath: outputPath, pageOrder: pageOrder)
        DispatchQueue.main.async {
          result(success ? outputPath : nil)
        }
      }

    case "downloadPdf":
      guard let args = call.arguments as? [String: Any],
            let sourcePath = args["sourcePath"] as? String,
            let fileName = args["fileName"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "sourcePath and fileName are required", details: nil))
        return
      }

      presentShareSheet(sourcePath: sourcePath, fileName: fileName, result: result)

    case "signPdf":
      guard let args = call.arguments as? [String: Any],
            let sourcePath = args["sourcePath"] as? String,
            let outputPath = args["outputPath"] as? String,
            let signatureBytes = args["signatureBytes"] as? FlutterStandardTypedData,
            let pageNumber = args["pageNumber"] as? Int,
            let xRatio = args["xRatio"] as? Double,
            let yRatio = args["yRatio"] as? Double,
            let widthRatio = args["widthRatio"] as? Double,
            let heightRatio = args["heightRatio"] as? Double else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "sourcePath, outputPath, signatureBytes, pageNumber, xRatio, yRatio, widthRatio and heightRatio are required", details: nil))
        return
      }

      DispatchQueue.global(qos: .userInitiated).async {
        let success = self.signPDF(
          sourcePath: sourcePath,
          outputPath: outputPath,
          signatureData: signatureBytes.data,
          pageNumber: pageNumber,
          xRatio: xRatio,
          yRatio: yRatio,
          widthRatio: widthRatio,
          heightRatio: heightRatio
        )
        DispatchQueue.main.async {
          result(success ? outputPath : nil)
        }
      }

    case "addImageToPdf":
      guard let args = call.arguments as? [String: Any],
            let sourcePath = args["sourcePath"] as? String,
            let outputPath = args["outputPath"] as? String,
            let imageBytes = args["imageBytes"] as? FlutterStandardTypedData,
            let pageNumber = args["pageNumber"] as? Int,
            let xRatio = args["xRatio"] as? Double,
            let yRatio = args["yRatio"] as? Double,
            let widthRatio = args["widthRatio"] as? Double,
            let heightRatio = args["heightRatio"] as? Double else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "sourcePath, outputPath, imageBytes, pageNumber, xRatio, yRatio, widthRatio and heightRatio are required", details: nil))
        return
      }

      DispatchQueue.global(qos: .userInitiated).async {
        let success = self.signPDF(
          sourcePath: sourcePath,
          outputPath: outputPath,
          signatureData: imageBytes.data,
          pageNumber: pageNumber,
          xRatio: xRatio,
          yRatio: yRatio,
          widthRatio: widthRatio,
          heightRatio: heightRatio
        )
        DispatchQueue.main.async {
          result(success ? outputPath : nil)
        }
      }

    case "imagesToPdf":
      guard let args = call.arguments as? [String: Any],
            let imagePaths = args["imagePaths"] as? [String],
            let outputPath = args["outputPath"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "imagePaths and outputPath are required", details: nil))
        return
      }

      DispatchQueue.global(qos: .userInitiated).async {
        let success = self.imagesToPDF(imagePaths: imagePaths, outputPath: outputPath)
        DispatchQueue.main.async {
          result(success ? outputPath : nil)
        }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func mergePDFs(paths: [String], outputPath: String) -> Bool {
    let mergedDocument = PDFDocument()
    var pageIndex = 0
    
    for path in paths {
      let url: URL
      if path.hasPrefix("file://") {
        url = URL(string: path) ?? URL(fileURLWithPath: path)
      } else {
        url = URL(fileURLWithPath: path)
      }
      
      guard let doc = PDFDocument(url: url) else {
        return false
      }
      
      for i in 0..<doc.pageCount {
        if let page = doc.page(at: i) {
          mergedDocument.insert(page, at: pageIndex)
          pageIndex += 1
        }
      }
    }
    
    let outputURL = URL(fileURLWithPath: outputPath)
    // Make sure parent directories exist
    let parentDir = outputURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
    
    return mergedDocument.write(to: outputURL)
  }

  private func splitPDF(path: String, outputDirectory: String, pageRanges: [[Int]], prefix: String) -> [String]? {
    let sourceURL = URL(fileURLWithPath: path)
    guard let sourceDocument = PDFDocument(url: sourceURL) else {
      return nil
    }

    let pageCount = sourceDocument.pageCount
    guard pageCount > 0 else {
      return nil
    }

    let outputDirURL = URL(fileURLWithPath: outputDirectory)
    try? FileManager.default.createDirectory(at: outputDirURL, withIntermediateDirectories: true, attributes: nil)

    var outputPaths: [String] = []
    for (index, range) in pageRanges.enumerated() {
      let start = max(1, min(range.first ?? 1, pageCount))
      let end = max(start, min(range.count > 1 ? range[1] : pageCount, pageCount))

      let splitDocument = PDFDocument()
      var insertIndex = 0
      for pageIndex in (start - 1)..<end {
        guard let page = sourceDocument.page(at: pageIndex) else { continue }
        splitDocument.insert(page, at: insertIndex)
        insertIndex += 1
      }

      let outputURL = outputDirURL.appendingPathComponent("\(prefix)_\(index + 1).pdf")
      guard splitDocument.write(to: outputURL) else {
        return nil
      }
      outputPaths.append(outputURL.path)
    }
    return outputPaths
  }

  private func reorderPDF(path: String, outputPath: String, pageOrder: [Int]) -> Bool {
    let sourceURL = URL(fileURLWithPath: path)
    guard let sourceDocument = PDFDocument(url: sourceURL) else {
      return false
    }

    let pageCount = sourceDocument.pageCount
    guard pageCount > 0 else {
      return false
    }

    let reorderedDocument = PDFDocument()
    var insertIndex = 0
    for pageNumber in pageOrder {
      let pageIndex = max(0, min(pageNumber - 1, pageCount - 1))
      guard let page = sourceDocument.page(at: pageIndex) else { continue }
      reorderedDocument.insert(page, at: insertIndex)
      insertIndex += 1
    }

    let outputURL = URL(fileURLWithPath: outputPath)
    let parentDir = outputURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)

    return reorderedDocument.write(to: outputURL)
  }

  private func signPDF(sourcePath: String, outputPath: String, signatureData: Data, pageNumber: Int, xRatio: Double, yRatio: Double, widthRatio: Double, heightRatio: Double) -> Bool {
    guard let signatureImage = UIImage(data: signatureData), let cgSignatureImage = signatureImage.cgImage else {
      return false
    }
    guard let pdfDocument = CGPDFDocument(URL(fileURLWithPath: sourcePath) as CFURL) else {
      return false
    }

    let pageCount = pdfDocument.numberOfPages
    guard pageCount > 0 else {
      return false
    }
    let targetPageNumber = max(1, min(pageNumber, pageCount))

    let outputURL = URL(fileURLWithPath: outputPath)
    let parentDir = outputURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)

    let pdfData = NSMutableData()
    guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
          let pdfContext = CGContext(consumer: consumer, mediaBox: nil, nil) else {
      return false
    }

    for pageIndex in 1...pageCount {
      guard let page = pdfDocument.page(at: pageIndex) else { continue }
      var mediaBox = page.getBoxRect(.mediaBox)

      pdfContext.beginPage(mediaBox: &mediaBox)
      pdfContext.drawPDFPage(page)

      if pageIndex == targetPageNumber {
        let pageWidth = mediaBox.width
        let pageHeight = mediaBox.height
        let w = CGFloat(widthRatio) * pageWidth
        let h = CGFloat(heightRatio) * pageHeight
        let x = CGFloat(xRatio) * pageWidth
        let y = pageHeight - (CGFloat(yRatio) * pageHeight) - h

        pdfContext.saveGState()
        pdfContext.draw(cgSignatureImage, in: CGRect(x: x, y: y, width: w, height: h))
        pdfContext.restoreGState()
      }

      pdfContext.endPage()
    }
    pdfContext.closePDF()

    return pdfData.write(to: outputURL, atomically: true)
  }

  private func imagesToPDF(imagePaths: [String], outputPath: String) -> Bool {
    guard !imagePaths.isEmpty else { return false }

    let outputURL = URL(fileURLWithPath: outputPath)
    let parentDir = outputURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)

    let pdfData = NSMutableData()
    guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
          let pdfContext = CGContext(consumer: consumer, mediaBox: nil, nil) else {
      return false
    }

    for imagePath in imagePaths {
      guard let image = UIImage(contentsOfFile: imagePath), let cgImage = image.cgImage else {
        return false
      }

      var mediaBox = CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
      pdfContext.beginPage(mediaBox: &mediaBox)
      pdfContext.draw(cgImage, in: mediaBox)
      pdfContext.endPage()
    }
    pdfContext.closePDF()

    return pdfData.write(to: outputURL, atomically: true)
  }

  private func presentShareSheet(sourcePath: String, fileName: String, result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      // Resolve source path to URL
      let sourceURL = URL(fileURLWithPath: sourcePath)
      
      guard FileManager.default.fileExists(atPath: sourcePath) else {
        result(FlutterError(code: "FILE_NOT_FOUND", message: "Source file not found", details: nil))
        return
      }
      
      // Copy to temporary location with the user-friendly fileName so the share dialog shows it correctly
      let tempDir = NSTemporaryDirectory()
      let destinationURL = URL(fileURLWithPath: tempDir).appendingPathComponent(fileName)
      
      try? FileManager.default.removeItem(at: destinationURL)
      do {
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
      } catch {
        // Fallback to source URL if copy fails
        print("Failed to copy file for sharing: \(error)")
      }
      
      let finalShareURL = FileManager.default.fileExists(atPath: destinationURL.path) ? destinationURL : sourceURL
      let activityViewController = UIActivityViewController(activityItems: [finalShareURL], applicationActivities: nil)
      
      guard let topViewController = self.getTopViewController() else {
        result(FlutterError(code: "NO_VIEW_CONTROLLER", message: "Could not find root view controller", details: nil))
        return
      }
      
      // iPad safety popover settings
      if let popover = activityViewController.popoverPresentationController {
        popover.sourceView = topViewController.view
        popover.sourceRect = CGRect(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height - 100, width: 0, height: 0)
        popover.permittedArrowDirections = []
      }
      
      activityViewController.completionWithItemsHandler = { (activityType, completed, returnedItems, error) in
        result(completed)
      }
      
      topViewController.present(activityViewController, animated: true, completion: nil)
    }
  }

  private func getTopViewController() -> UIViewController? {
    var keyWindow: UIWindow?
    if #available(iOS 13.0, *) {
      keyWindow = UIApplication.shared.connectedScenes
          .filter { $0.activationState == .foregroundActive }
          .compactMap { $0 as? UIWindowScene }
          .first?.windows
          .first { $0.isKeyWindow }
    }
    if keyWindow == nil {
      keyWindow = UIApplication.shared.keyWindow
    }
    
    var topController = keyWindow?.rootViewController
    while let presented = topController?.presentedViewController {
      topController = presented
    }
    return topController
  }
}
