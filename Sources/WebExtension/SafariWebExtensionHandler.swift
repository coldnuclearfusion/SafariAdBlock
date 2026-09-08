// Native side of the Video Ad Skipper web extension. The real work happens in WebExtension/main.js and content.js;
// this is the minimal implementation Safari requires (message response). AppKit must be linked, or requests never arrive.
import AppKit
import Foundation
import SafariServices

@objc(SafariWebExtensionHandler)
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: ["ok": true]]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
