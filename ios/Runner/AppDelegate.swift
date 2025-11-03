import Flutter
import UIKit
import SafariServices

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Set up method channel for certificate installation
    let controller = window?.rootViewController as! FlutterViewController
    let certificateChannel = FlutterMethodChannel(
      name: "com.example.certificate_install_demo/certificate",
      binaryMessenger: controller.binaryMessenger
    )
    
    certificateChannel.setMethodCallHandler { [weak self] (call, result) in
      switch call.method {
      case "installCertificate":
        if let args = call.arguments as? [String: Any],
           let urlString = args["url"] as? String,
           let url = URL(string: urlString) {
          self?.presentSafariViewController(url: url, result: result)
        } else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid URL", details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  private func presentSafariViewController(url: URL, result: @escaping FlutterResult) {
    guard let rootViewController = window?.rootViewController else {
      result(FlutterError(code: "NO_CONTROLLER", message: "No root view controller", details: nil))
      return
    }
    
    let safariViewController = SFSafariViewController(url: url)
    safariViewController.preferredBarTintColor = UIColor.systemBlue
    safariViewController.preferredControlTintColor = UIColor.white
    safariViewController.dismissButtonStyle = .close
    
    // Present the Safari view controller
    rootViewController.present(safariViewController, animated: true) {
      result("success")
    }
  }
}
