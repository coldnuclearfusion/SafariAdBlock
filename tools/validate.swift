// tools/validate.swift
// Validates content blocker rules with the same WebKit Safari uses.
//
//   validate selectors <selectors.json>            Prints the invalid CSS selectors as a JSON array on stdout.
//                                                  WebKit drops invalid selectors silently without an error (taking every other
//                                                  selector merged into the same rule with them), so each one is checked with
//                                                  document.querySelector in a WKWebView.
//   validate compile <rules.json> [--fix <out>]    Compiles the whole list. On failure it bisects to find the offending rules and,
//                                                  with --fix, saves the list without them.
//                                                  stdout: {"total": rule count, "bad": [offending rule indices…]}
// Progress goes to stderr. (WebKit itself also prints parse errors to stderr.)
import Foundation
import WebKit

func log(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }
func fail(_ s: String) -> Never { log(s); exit(1) }

let storeDir = FileManager.default.temporaryDirectory.appendingPathComponent("SafariAdBlock-validate-\(getpid())")
try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
guard let store = WKContentRuleListStore(url: storeDir) else { fail("could not create the rule store: \(storeDir.path)") }
var compileCount = 0

/// Compiles a rule array. Returns nil on success or the error message on failure. Called from a background thread (the main run loop handles callbacks).
func compile(_ rules: [Any]) -> String? {
    compileCount += 1
    let id = "list\(compileCount)"
    guard let data = try? JSONSerialization.data(withJSONObject: rules) else { return "JSON serialization failed" }
    let json = String(decoding: data, as: UTF8.self)
    var failure: String?
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.main.async {
        store.compileContentRuleList(forIdentifier: id, encodedContentRuleList: json) { _, error in
            if let error = error as NSError? {
                failure = (error.userInfo[NSHelpAnchorErrorKey] as? String) ?? error.localizedDescription
                done.signal()
            } else {
                store.removeContentRuleList(forIdentifier: id) { _ in done.signal() }
            }
        }
    }
    done.wait()
    return failure
}

/// (index, error) of every rule that fails to compile. Bisection.
func findBad(_ rules: [Any], offset: Int = 0) -> [(Int, String)] {
    guard let error = compile(rules) else { return [] }
    if rules.count == 1 { return [(offset, error)] }
    let mid = rules.count / 2
    return findBad(Array(rules[..<mid]), offset: offset) + findBad(Array(rules[mid...]), offset: offset + mid)
}

// ---- selector check ----

final class PageLoader: NSObject, WKNavigationDelegate {
    let loaded = DispatchSemaphore(value: 0)
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded.signal() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { loaded.signal() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { loaded.signal() }
}

var webView: WKWebView?
let loader = PageLoader()

/// Checks with document.querySelector inside a WKWebView. nil if the web view could not be used.
func invalidSelectorsByWebView(_ selectors: [String]) -> [String]? {
    let ready = DispatchSemaphore(value: 0)
    DispatchQueue.main.async {
        let view = WKWebView(frame: .zero)
        view.navigationDelegate = loader
        view.loadHTMLString("<html><body></body></html>", baseURL: nil)   // no doctype = quirks mode (same parser setting the content blocker uses)
        webView = view
        ready.signal()
    }
    ready.wait()
    if loader.loaded.wait(timeout: .now() + 20) == .timedOut { return nil }

    var invalid: [String] = []
    let chunk = 5000
    var index = 0
    while index < selectors.count {
        let slice = Array(selectors[index..<min(index + chunk, selectors.count)])
        guard let json = try? JSONSerialization.data(withJSONObject: slice) else { return nil }
        let script = """
        (function (list) {
            var bad = [];
            for (var i = 0; i < list.length; i++) {
                try { document.querySelector(list[i]); } catch (e) { bad.push(list[i]); }
            }
            return bad;
        })(\(String(decoding: json, as: UTF8.self)))
        """
        var result: [String]?
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            webView!.evaluateJavaScript(script) { value, error in
                if let error = error { log("  JavaScript error: \(error.localizedDescription)") }
                result = value as? [String]
                done.signal()
            }
        }
        if done.wait(timeout: .now() + 60) == .timedOut || result == nil { return nil }
        invalid += result!
        index += chunk
        log("  Selector check \(min(index, selectors.count))/\(selectors.count) — \(invalid.count) invalid")
    }
    return invalid
}

/// Fallback: compile a one-rule list per selector. An invalid selector makes the rule get dropped, which yields an empty-list error.
func invalidSelectorsByCompile(_ selectors: [String]) -> [String] {
    var invalid: [String] = []
    for (i, s) in selectors.enumerated() {
        let rule: [String: Any] = ["trigger": ["url-filter": ".*"], "action": ["type": "css-display-none", "selector": s]]
        if compile([rule]) != nil { invalid.append(s) }
        if (i + 1) % 1000 == 0 { log("  Selector check \(i + 1)/\(selectors.count) — \(invalid.count) invalid") }
    }
    return invalid
}

func selectorsMode(_ path: String) {
    guard let data = FileManager.default.contents(atPath: path),
          let selectors = (try? JSONSerialization.jsonObject(with: data)) as? [String] else {
        fail("could not read the selector file: \(path)")
    }
    var invalid = invalidSelectorsByWebView(selectors)
    if invalid == nil {
        log("  WKWebView unavailable; falling back to compile-based checking (slow)")
        invalid = invalidSelectorsByCompile(selectors)
    }
    FileHandle.standardOutput.write(try! JSONSerialization.data(withJSONObject: invalid!))
    print()
}

func compileMode(_ path: String, fix: String?) {
    guard let data = FileManager.default.contents(atPath: path),
          let rules = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else {
        fail("could not read the rule file: \(path)")
    }
    let start = Date()
    let error = compile(rules)
    log(String(format: "  Full compile (%d rules) in %.1f s: %@", rules.count, Date().timeIntervalSince(start), error ?? "ok"))
    var bad: [(Int, String)] = []
    if error != nil {
        log("  Bisecting to find the offending rules…")
        bad = findBad(rules)
        for (i, e) in bad { log("  Dropping rule #\(i): \(e)") }
        if let fix = fix, !bad.isEmpty {
            let badSet = Set(bad.map { $0.0 })
            let kept = rules.enumerated().filter { !badSet.contains($0.offset) }.map { $0.element }
            if let recheck = compile(kept) { fail("still fails to compile after dropping the offending rules: \(recheck)") }
            let out = try! JSONSerialization.data(withJSONObject: kept, options: [.withoutEscapingSlashes])
            try! out.write(to: URL(fileURLWithPath: fix))
        }
    }
    let result: [String: Any] = ["total": rules.count, "bad": bad.map { $0.0 }]
    FileHandle.standardOutput.write(try! JSONSerialization.data(withJSONObject: result))
    print()
}

let args = CommandLine.arguments
Thread {
    var status: Int32 = 0
    if args.count >= 3 && args[1] == "selectors" {
        selectorsMode(args[2])
    } else if args.count >= 3 && args[1] == "compile" {
        var fix: String?
        if let i = args.firstIndex(of: "--fix"), i + 1 < args.count { fix = args[i + 1] }
        compileMode(args[2], fix: fix)
    } else {
        log("usage: validate selectors <selectors.json> | validate compile <rules.json> [--fix <out.json>]")
        status = 2
    }
    try? FileManager.default.removeItem(at: storeDir)
    exit(status)
}.start()
RunLoop.main.run()
