// tools/smoke-test.swift — applies the converted rules in a real WKWebView and checks that ad requests are blocked and ad elements hidden.
// Usage: swiftc -O -o tools/smoke-test tools/smoke-test.swift -framework WebKit && tools/smoke-test rules/Ads.json
import Foundation
import WebKit

func log(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }

let rulesPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "rules/Ads.json"
let json = try! String(contentsOfFile: rulesPath, encoding: .utf8)

let html = """
<html><body>
<div id="AD_300" style="width:10px;height:10px">ad</div>
<div id="control-box" style="width:10px;height:10px">ok</div>
<script>
window.results = {};
function mark(name, v) { window.results[name] = v; }
</script>
<script src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js" onload="mark('googlesyndication','loaded')" onerror="mark('googlesyndication','blocked')"></script>
<img src="https://ad.doubleclick.net/ddm/ad/N1.gif" onload="mark('doubleclick','loaded')" onerror="mark('doubleclick','blocked')">
<img src="https://www.google.com/favicon.ico" onload="mark('control','loaded')" onerror="mark('control','blocked')">
</body></html>
"""

final class Delegate: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            let js = """
            (function(){
              var r = Object.assign({}, window.results);
              r.ad_display = getComputedStyle(document.getElementById('AD_300')).display;
              r.control_display = getComputedStyle(document.getElementById('control-box')).display;
              return JSON.stringify(r);
            })()
            """
            webView.evaluateJavaScript(js) { value, error in
                print(value as? String ?? "JavaScript error: \(error?.localizedDescription ?? "?")")
                exit(0)
            }
        }
    }
}

let delegate = Delegate()
var webView: WKWebView!
let store = WKContentRuleListStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("smoke-\(getpid())"))!
let start = Date()
store.compileContentRuleList(forIdentifier: "ads", encodedContentRuleList: json) { list, error in
    guard let list = list else { log("compile failed: \(error!.localizedDescription)"); exit(1) }
    log(String(format: "compiled in %.1f s", Date().timeIntervalSince(start)))
    let config = WKWebViewConfiguration()
    config.userContentController.add(list)
    webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
    webView.navigationDelegate = delegate
    webView.loadHTMLString(html, baseURL: URL(string: "https://example.com/")!)
}
DispatchQueue.main.asyncAfter(deadline: .now() + 30) { log("timed out"); exit(2) }
RunLoop.main.run()
