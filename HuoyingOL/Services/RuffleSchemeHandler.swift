//
//  RuffleSchemeHandler.swift
//  HuoyingOL
//
//  自定义 scheme ruffle:// 在真机 WKWebView 里 fetch / script 都到不了这里，所以不再用它送 wasm 或 entry.swf。
//  SWF 和 res.huoying 资源走 AirNativeFetchBridge：URLSession 下载后把 base64 交回页面，由 window.fetch 组成 Response。
//  本 handler 先留着，页面不再依赖它。
//
//  已知限制：火影 OL 的 entry.swf 是 ActionScript 3，并用 Flash Socket 连 zone.huoying.qq.com。
//  Ruffle 只开 WebSocket。AirSocketBridge 把 ws://air.socket/connect 收成 TCP，主机限于火影/腾讯区服。
//  加载进度来自 resource.cfg 和各版本目录里的 .pkg，不单是 entry.swf。
//

import Foundation
import Network
import WebKit

final class RuffleSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "ruffle"

    private let lock = NSLock()
    private var stoppedTasks = Set<ObjectIdentifier>()
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            fail(urlSchemeTask, URLError(.badURL))
            return
        }
        if urlSchemeTask.request.httpMethod?.uppercased() == "OPTIONS" {
            finish(urlSchemeTask, url: url, status: 204, mime: "text/plain", data: Data())
            return
        }
        switch url.host?.lowercased() {
        case "bundle":
            serveBundle(url, task: urlSchemeTask)
        case "proxy":
            serveProxy(url, webView: webView, task: urlSchemeTask)
        default:
            fail(urlSchemeTask, URLError(.unsupportedURL))
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        lock.lock()
        stoppedTasks.insert(ObjectIdentifier(urlSchemeTask))
        lock.unlock()
    }

    private func serveBundle(_ url: URL, task: WKURLSchemeTask) {
        let name = url.lastPathComponent
        guard !name.isEmpty, !name.contains("/"), !name.contains(".."),
              let file = Self.bundleFile(named: name) else {
            fail(task, URLError(.fileDoesNotExist))
            return
        }
        do {
            let data = try Data(contentsOf: file)
            finish(task, url: url, status: 200, mime: Self.mime(for: name), data: data)
        } catch {
            fail(task, error)
        }
    }

    private func serveProxy(_ url: URL, webView: WKWebView, task: WKURLSchemeTask) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let raw = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let target = URL(string: raw),
              let scheme = target.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              !Self.isBlockedHost(target) else {
            fail(task, URLError(.badURL))
            return
        }
        // WKURLSchemeTask 的回调必须留在 start 所在线程，所以在这里等下载结束。
        let semaphore = DispatchSemaphore(value: 0)
        var body = Data()
        var mime = Self.mime(for: target.path)
        var status = 200
        var failure: Error?
        var request = URLRequest(url: target)
        request.httpMethod = "GET"
        let dataTask = session.dataTask(with: request) { data, response, error in
            if let error = error {
                failure = error
            } else {
                body = data ?? Data()
                if let http = response as? HTTPURLResponse {
                    status = http.statusCode
                    if let responseMime = http.mimeType, !responseMime.isEmpty {
                        mime = responseMime
                    }
                }
            }
            semaphore.signal()
        }
        dataTask.resume()
        semaphore.wait()
        _ = webView
        if let failure = failure {
            fail(task, failure)
            return
        }
        finish(task, url: url, status: status, mime: mime, data: body)
    }

    private func finish(_ task: WKURLSchemeTask, url: URL, status: Int, mime: String, data: Data) {
        if isStopped(task) { return }
        let headers = [
            "Content-Type": mime,
            "Content-Length": String(data.count),
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
            "Access-Control-Allow-Headers": "*",
            "Cache-Control": "public, max-age=86400"
        ]
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
            fail(task, URLError(.badServerResponse))
            return
        }
        if isStopped(task) { return }
        task.didReceive(response)
        if isStopped(task) { return }
        if !data.isEmpty {
            task.didReceive(data)
        }
        if isStopped(task) { return }
        task.didFinish()
    }

    private func fail(_ task: WKURLSchemeTask, _ error: Error) {
        if isStopped(task) { return }
        task.didFailWithError(error)
    }

    private func isStopped(_ task: WKURLSchemeTask) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return stoppedTasks.contains(ObjectIdentifier(task))
    }

    private static func bundleFile(named name: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "Ruffle") {
            return url
        }
        if let root = Bundle.main.resourceURL?.appendingPathComponent("Ruffle", isDirectory: true) {
            let file = root.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: file.path) {
                return file
            }
        }
        return Bundle.main.url(forResource: name, withExtension: nil)
    }

    private static func mime(for name: String) -> String {
        let lower = name.lowercased()
        if lower.hasSuffix(".wasm") { return "application/wasm" }
        if lower.hasSuffix(".js") { return "text/javascript" }
        if lower.hasSuffix(".swf") { return "application/x-shockwave-flash" }
        return "application/octet-stream"
    }

    private static func isBlockedHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return true }
        if host == "localhost" || host.hasSuffix(".local") || host == "0.0.0.0" || host == "::1" {
            return true
        }
        if host.hasPrefix("127.") || host.hasPrefix("10.") || host.hasPrefix("192.168.") || host.hasPrefix("169.254.") {
            return true
        }
        return false
    }

}

/// resource.cfg 里每条资源带有自己的版本目录。LoginConfig.xml 不在 entry.swf 那一版，直接拼当前目录会得到 162 字节的 nginx 404。
private enum AssetTagIndex {
    static func parse(_ data: Data) -> [String: String] {
        guard data.count > 16 else { return [:] }
        let end = (Int(data[0]) << 24) | (Int(data[1]) << 16) | (Int(data[2]) << 8) | Int(data[3])
        let reader = Reader(data: data, limit: min(max(end, 0), data.count))
        reader.index = 9
        _ = reader.value()
        guard let first = reader.value() else { return [:] }
        var map: [String: String] = [:]
        func take(_ value: TagValue) {
            guard case .object(let fields) = value,
                  case .text(let url)? = fields["url"],
                  case .text(let tag)? = fields["tag"],
                  !url.isEmpty, tag.hasPrefix("Naruto") else { return }
            map[url] = tag
        }
        take(first)
        while reader.index < reader.limit {
            let mark = data[reader.index]
            if mark == 0x01 {
                reader.index += 1
                continue
            }
            if mark == 0x06 {
                guard reader.value() != nil, reader.index < data.count, data[reader.index] == 0x0A, let obj = reader.value() else { break }
                take(obj)
                continue
            }
            if mark == 0x0A {
                guard let obj = reader.value() else { break }
                take(obj)
                continue
            }
            break
        }
        return map
    }

    fileprivate enum TagValue {
        case text(String)
        case number(Int)
        case empty
        case object([String: TagValue])
    }

    fileprivate final class Reader {
        let data: Data
        let limit: Int
        var index: Int
        var strings: [String] = []
        var traits: [[String]] = []

        init(data: Data, limit: Int) {
            self.data = data
            self.limit = limit
            self.index = 0
        }

        func value() -> TagValue? {
            guard index < data.count else { return nil }
            let mark = data[index]
            index += 1
            switch mark {
            case 0x01, 0x02, 0x03:
                return .empty
            case 0x04:
                guard let raw = u29() else { return nil }
                var number = Int(raw)
                if number & 0x10000000 != 0 { number -= 0x20000000 }
                return .number(number)
            case 0x06:
                guard let text = string() else { return nil }
                return .text(text)
            case 0x0A:
                return object()
            default:
                return nil
            }
        }

        private func object() -> TagValue? {
            guard let header = u29() else { return nil }
            if header & 1 == 0 { return .empty }
            let props: [String]
            if header & 3 == 1 {
                let traitIndex = Int(header >> 2)
                guard traits.indices.contains(traitIndex) else { return nil }
                props = traits[traitIndex]
            } else {
                let count = Int(header >> 4)
                guard string() != nil else { return nil }
                var names: [String] = []
                for _ in 0..<count {
                    guard let name = string() else { return nil }
                    names.append(name)
                }
                traits.append(names)
                props = names
            }
            var fields: [String: TagValue] = [:]
            for name in props {
                guard let item = value() else { return nil }
                fields[name] = item
            }
            return .object(fields)
        }

        private func string() -> String? {
            guard let header = u29() else { return nil }
            if header & 1 == 0 {
                let ref = Int(header >> 1)
                guard strings.indices.contains(ref) else { return nil }
                return strings[ref]
            }
            let length = Int(header >> 1)
            guard length >= 0, index + length <= data.count else { return nil }
            let text = length == 0 ? "" : String(data: data.subdata(in: index..<(index + length)), encoding: .utf8) ?? ""
            index += length
            strings.append(text)
            return text
        }

        private func u29() -> UInt32? {
            var value: UInt32 = 0
            for shift in 0..<4 {
                guard index < data.count else { return nil }
                let byte = UInt32(data[index])
                index += 1
                if shift == 3 {
                    value = (value << 8) | byte
                    break
                }
                value = (value << 7) | (byte & 0x7F)
                if byte & 0x80 == 0 { break }
            }
            return value
        }
    }
}

/// 页面里的 `window.fetch`（Ruffle 的 `__wbg_fetch` 调的就是它）不能跨域读 entry.swf。
/// 真机上 `ruffle://` 也到不了 WKURLSchemeHandler，所以由这里用 URLSession 把字节送回 JS。
final class AirNativeFetchBridge: NSObject, WKScriptMessageHandler {
    static let handlerName = "airNativeFetch"
    static let maxBytes = 48 * 1024 * 1024

    weak var webView: WKWebView?

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 90
        config.httpShouldSetCookies = false
        config.urlCache = nil
        return URLSession(configuration: config)
    }()
    private let lookupSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.httpShouldSetCookies = false
        config.urlCache = nil
        return URLSession(configuration: config)
    }()
    private let workQueue = DispatchQueue(label: "air.asset-index")
    private let indexLock = NSLock()
    private var assetTags: [String: String] = [:]
    /// entry.swf 所在版本目录，例如 NarutoBetali.37Build303。resource.cfg 必须从这里取，
    /// 根路径 /resource.cfg 是 nginx 404（SWF 内部按 baseURL 解析相对路径导致）。
    private var buildDir: String = ""

    /// 把原生侧的进度/结果回显到页面状态条，方便真机排查。
    private func report(_ text: String) {
        let script = "console.log(" + Self.jsString("[air-ruffle] " + text) + ")"
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    private func noteBuildDir(_ url: URL) {
        guard let first = url.path.split(separator: "/").map(String.init).first,
              first.lowercased().contains("build") else { return }
        indexLock.lock()
        let changed = buildDir != first
        if changed { buildDir = first }
        indexLock.unlock()
        if changed { report("版本目录 " + first) }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        let id = (body["id"] as? String) ?? ""
        guard id.range(of: "^[A-Za-z0-9]{1,32}$", options: .regularExpression) != nil else { return }
        guard let raw = body["url"] as? String, let url = URL(string: raw), Self.allows(url) else {
            deliver(id: id, status: 0, mime: "", data: nil, error: "blocked url")
            return
        }
        workQueue.async { [weak self] in
            guard let self = self else { return }
            self.noteBuildDir(url)
            if url.path.lowercased().hasSuffix("resource.cfg") {
                // SWF 会按 baseURL 把 resource.cfg 解析到根路径，先试版本目录，命中就直接回给页面。
                if let fixed = self.versionedResourceCfg(for: url), fixed.absoluteString != url.absoluteString,
                   let loaded = self.downloadSync(fixed), loaded.0 == 200, !loaded.1.isEmpty {
                    self.ingest(loaded.1)
                    self.report("resource.cfg 已从 " + fixed.path + " 取得 " + String(loaded.1.count) + " 字节")
                    self.deliver(id: id, status: 200, mime: "application/octet-stream", data: loaded.1, error: nil)
                    return
                }
            }
            if !url.path.lowercased().hasSuffix("resource.cfg") {
                self.ensureIndex(near: url)
            }
            self.load(id: id, url: self.rewrite(url), allowRecover: true)
        }
    }

    private func load(id: String, url: URL, allowRecover: Bool) {
        guard Self.allows(url) else {
            deliver(id: id, status: 0, mime: "", data: nil, error: "blocked url")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(AppSettings.desktopWebUserAgent, forHTTPHeaderField: "User-Agent")
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            self?.workQueue.async {
                self?.finish(id: id, url: url, data: data, response: response, error: error, allowRecover: allowRecover)
            }
        }
        task.resume()
    }

    private func finish(id: String, url: URL, data: Data?, response: URLResponse?, error: Error?, allowRecover: Bool) {
        if let error = error {
            deliver(id: id, status: 0, mime: "", data: nil, error: error.localizedDescription)
            return
        }
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        var mime = http?.mimeType ?? ""
        if url.path.lowercased().contains(".swf") {
            mime = "application/x-shockwave-flash"
        } else if mime.isEmpty {
            mime = Self.mime(for: url)
        }
        let bytes = data ?? Data()
        if status == 200, url.path.lowercased().hasSuffix("resource.cfg") {
            ingest(bytes)
        }
        if status >= 400, allowRecover {
            ensureIndex(near: url)
            let better = rewrite(url)
            if better.absoluteString != url.absoluteString {
                load(id: id, url: better, allowRecover: false)
                return
            }
            // 索引还没建起来时按版本目录兜底：/flash/core/naruto.core.swf → /<Build>/flash/core/naruto.core.swf
            indexLock.lock()
            let dir = buildDir
            indexLock.unlock()
            if !dir.isEmpty, !url.path.hasPrefix("/" + dir + "/"),
               var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                components.path = "/" + dir + url.path
                if let fallback = components.url {
                    report("404 兜底 " + fallback.path)
                    load(id: id, url: fallback, allowRecover: false)
                    return
                }
            }
        }
        if bytes.count > Self.maxBytes {
            deliver(id: id, status: 0, mime: "", data: nil, error: "response too large")
            return
        }
        deliver(id: id, status: status, mime: mime, data: bytes, error: nil)
    }

    private func ensureIndex(near url: URL) {
        indexLock.lock()
        let ready = !assetTags.isEmpty
        let dir = buildDir
        indexLock.unlock()
        guard !ready else { return }
        var candidates: [String] = []
        if !dir.isEmpty {
            candidates.append("/" + dir + "/resource.cfg")
            candidates.append("/" + dir + "/flash/core/resource.cfg")
        }
        candidates.append("/flash/core/resource.cfg")
        candidates.append("/resource.cfg")
        for path in candidates {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { continue }
            components.path = path
            components.query = nil
            guard let cfgURL = components.url, let loaded = downloadSync(cfgURL), loaded.0 == 200, !loaded.1.isEmpty else { continue }
            ingest(loaded.1)
            indexLock.lock()
            let count = assetTags.count
            indexLock.unlock()
            if count > 0 {
                report("索引完成 " + String(count) + " 条 ← " + path)
                return
            }
        }
        report("索引失败（资源目录均未命中）")
    }

    /// resource.cfg 的真实位置：entry.swf 同目录。
    private func versionedResourceCfg(for url: URL) -> URL? {
        indexLock.lock()
        let dir = buildDir
        indexLock.unlock()
        guard !dir.isEmpty,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.path = "/" + dir + "/resource.cfg"
        components.query = nil
        return components.url
    }

    private func ingest(_ data: Data) {
        // resource.cfg 一般是 LZMA alone 压缩的 AMF，也兼容未压缩的版本。
        var payload = data
        if let decoded = AirLzmaDecompressAlone(data), !decoded.isEmpty {
            payload = decoded
        }
        let map = AssetTagIndex.parse(payload)
        guard !map.isEmpty else { return }
        indexLock.lock()
        assetTags = map
        indexLock.unlock()
    }

    private func rewrite(_ url: URL) -> URL {
        indexLock.lock()
        let map = assetTags
        indexLock.unlock()
        guard !map.isEmpty else { return url }
        let parts = url.path.split(separator: "/").map(String.init)
        guard !parts.isEmpty else { return url }
        for start in 0..<parts.count {
            let suffix = parts[start...].joined(separator: "/")
            guard let tag = map[suffix] else { continue }
            if start == 1, parts[0] == tag { return url }
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
            components.path = "/" + tag + "/" + suffix
            return components.url ?? url
        }
        return url
    }

    private func downloadSync(_ url: URL) -> (Int, Data)? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(AppSettings.desktopWebUserAgent, forHTTPHeaderField: "User-Agent")
        let semaphore = DispatchSemaphore(value: 0)
        var result: (Int, Data)?
        let task = lookupSession.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            result = (status, data ?? Data())
            semaphore.signal()
        }
        task.resume()
        if semaphore.wait(timeout: .now() + 40) == .timedOut {
            task.cancel()
            return nil
        }
        return result
    }

    private func deliver(id: String, status: Int, mime: String, data: Data?, error: String?) {
        var scripts: [String] = []
        if error == nil, let data = data, !data.isEmpty {
            let encoded = data.base64EncodedString()
            let size = 120_000
            var start = encoded.startIndex
            while start < encoded.endIndex {
                let end = encoded.index(start, offsetBy: size, limitedBy: encoded.endIndex) ?? encoded.endIndex
                let chunk = String(encoded[start..<end])
                scripts.append("window.__airNativePush&&window.__airNativePush(\(Self.jsString(id)),\(Self.jsString(chunk)))")
                start = end
            }
        }
        let errorJS = error.map(Self.jsString) ?? "null"
        scripts.append("window.__airNativeFinish&&window.__airNativeFinish(\(Self.jsString(id)),\(status),\(Self.jsString(mime)),\(errorJS))")
        run(scripts)
    }

    private func run(_ scripts: [String]) {
        DispatchQueue.main.async { [weak self] in
            self?.runOnMain(scripts, index: 0)
        }
    }

    private func runOnMain(_ scripts: [String], index: Int) {
        guard index < scripts.count, let webView = webView else { return }
        webView.evaluateJavaScript(scripts[index]) { [weak self] _, _ in
            self?.runOnMain(scripts, index: index + 1)
        }
    }

    private static func allows(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        guard let host = url.host?.lowercased(), !host.isEmpty, !isBlocked(host) else { return false }
        if host == "res.huoying.qq.com" || host == "res.huoying.com" { return true }
        // 火影/腾讯侧的接口（HTTPDNS 的 /d?dn=…、登录校验等）在 WebView 里会被 CORS 挡掉，
        // 统一走原生 URLSession 才能拿到数据。放心：isBlocked 已挡住内网地址。
        if host == "qq.com" || host.hasSuffix(".qq.com") { return true }
        let parts = host.split(separator: ".")
        if parts.count == 4, parts.allSatisfy({ Int($0) != nil }) { return true }
        let path = url.path.lowercased()
        return path.contains(".swf") || path.contains(".pkg") || path.contains(".cfg")
    }

    private static func isBlocked(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".local") || host == "0.0.0.0" || host == "::1" { return true }
        if host.hasPrefix("127.") || host.hasPrefix("10.") || host.hasPrefix("192.168.") || host.hasPrefix("169.254.") { return true }
        if host.hasPrefix("172.") {
            let parts = host.split(separator: ".")
            if parts.count > 1, let second = Int(parts[1]), (16...31).contains(second) { return true }
        }
        return false
    }

    private static func mime(for url: URL) -> String {
        let path = url.path.lowercased()
        if path.contains(".swf") { return "application/x-shockwave-flash" }
        if path.hasSuffix(".png") { return "image/png" }
        if path.hasSuffix(".jpg") || path.hasSuffix(".jpeg") { return "image/jpeg" }
        if path.hasSuffix(".gif") { return "image/gif" }
        if path.hasSuffix(".xml") { return "application/xml" }
        if path.hasSuffix(".json") { return "application/json" }
        if path.hasSuffix(".mp3") { return "audio/mpeg" }
        if path.hasSuffix(".txt") { return "text/plain" }
        return "application/octet-stream"
    }

    private static func jsString(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x5C:
                out += "\\\\"
            case 0x22:
                out += "\\\""
            case 0x2028:
                out += "\\u2028"
            case 0x2029:
                out += "\\u2029"
            case 0..<0x20:
                if scalar.value == 0x0A {
                    out += "\\n"
                } else if scalar.value == 0x0D {
                    out += "\\r"
                } else {
                    out += String(format: "\\u%04x", scalar.value)
                }
            default:
                out.append(Character(scalar))
            }
        }
        out += "\""
        return out
    }
}

/// 把 App Bundle 里的 .wasm 字节按需送进页面。
///
/// 之前的做法是用上百个 WKUserScript 把 28MB 二进制（约 38MB base64）在每个文档
/// documentStart 时全量注入：登录页也要付一次内存与解析代价，且容易撞 WebKit 的
/// 注入体积上限。现在改成 Ruffle 真正调用 `__airLoadWasm` 时才回传，逐块 atob，
/// 不产生 38MB 的中间字符串，也不再依赖 `ruffle://` 自定义 scheme。
final class AirBundleBridge: NSObject, WKScriptMessageHandler {
    static let handlerName = "airNativeBundle"
    static let allowedNames = Set([
        "878d548199cddef07035.wasm",
        "172de42e6619eac8f371.wasm"
    ])
    /// 除两个 wasm 外，还放行随 IPA 内置的 APK 原始资产（APK/ 前缀），禁止路径穿越。
    private static func isAllowed(_ name: String) -> Bool {
        if allowedNames.contains(name) { return true }
        guard name.hasPrefix("APK/") else { return false }
        let rel = String(name.dropFirst(4))
        if rel.isEmpty || rel.hasPrefix("/") || rel.contains("..") { return false }
        return rel.range(of: #"^[A-Za-z0-9_./-]+$"#, options: .regularExpression) != nil
    }
    /// 必须是 4 的倍数：JS 端对每块单独 atob。
    private static let chunkSize = 200_000

    weak var webView: WKWebView?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let id = body["id"] as? String,
              id.range(of: "^[A-Za-z0-9]{1,32}$", options: .regularExpression) != nil,
              let name = body["name"] as? String,
              Self.isAllowed(name) else {
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let file = Self.bundleFile(named: name),
                  let data = try? Data(contentsOf: file), !data.isEmpty else {
                self.finish(id: id, error: "bundle 中缺少 \(name)")
                return
            }
            let encoded = data.base64EncodedString()
            var scripts: [String] = []
            var start = encoded.startIndex
            while start < encoded.endIndex {
                let end = encoded.index(start, offsetBy: Self.chunkSize, limitedBy: encoded.endIndex) ?? encoded.endIndex
                let chunk = String(encoded[start..<end])
                scripts.append("window.__airBundlePush&&window.__airBundlePush(\(Self.jsString(id)),\(Self.jsString(chunk)))")
                start = end
            }
            self.run(scripts) { [weak self] in
                self?.finish(id: id, error: nil)
            }
        }
    }

    private func run(_ scripts: [String], completion: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.runOnMain(scripts, index: 0, completion: completion)
        }
    }

    private func runOnMain(_ scripts: [String], index: Int, completion: @escaping () -> Void) {
        guard index < scripts.count else { completion(); return }
        guard let webView = webView else { completion(); return }
        webView.evaluateJavaScript(scripts[index]) { [weak self] _, _ in
            self?.runOnMain(scripts, index: index + 1, completion: completion)
        }
    }

    private func finish(id: String, error: String?) {
        let payload = error.map(Self.jsString) ?? "null"
        let script = "window.__airBundleFinish&&window.__airBundleFinish(\(Self.jsString(id)),\(payload))"
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    private static func bundleFile(named name: String) -> URL? {
        if name.hasPrefix("APK/") {
            let rel = String(name.dropFirst(4))
            if let url = Bundle.main.url(forResource: rel, withExtension: nil, subdirectory: "APK") {
                return url
            }
            if let root = Bundle.main.resourceURL?.appendingPathComponent("APK", isDirectory: true) {
                let file = root.appendingPathComponent(rel)
                if FileManager.default.fileExists(atPath: file.path) { return file }
            }
            return nil
        }
        if let url = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "Ruffle") {
            return url
        }
        if let root = Bundle.main.resourceURL?.appendingPathComponent("Ruffle", isDirectory: true) {
            let file = root.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: file.path) { return file }
        }
        return Bundle.main.url(forResource: name, withExtension: nil)
    }

    private static func jsString(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x5C: out += "\\\\"
            case 0x22: out += "\\\""
            case 0x0A: out += "\\n"
            case 0x0D: out += "\\r"
            case 0..<0x20: out += String(format: "\\u%04x", scalar.value)
            default: out.append(Character(scalar))
            }
        }
        out += "\""
        return out
    }
}

/// Ruffle 的 Flash Socket 会改走 WebSocket。这里把 `ws://air.socket/connect` 收成到区服的 TCP。
final class AirSocketBridge: NSObject, WKScriptMessageHandler {
    static let handlerName = "airNativeSocket"

    weak var webView: WKWebView?

    private let lock = NSLock()
    private var connections: [String: NWConnection] = [:]
    private let queue = DispatchQueue(label: "air.socket")

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        let op = body["op"] as? String ?? ""
        let id = body["id"] as? String ?? ""
        guard id.range(of: "^[A-Za-z0-9]{1,32}$", options: .regularExpression) != nil else { return }
        switch op {
        case "open":
            let host = body["host"] as? String ?? ""
            let port = portValue(body["port"])
            open(id: id, host: host, port: port)
        case "send":
            send(id: id, base64: body["b64"] as? String ?? "")
        case "close":
            close(id: id, notify: false)
        default:
            break
        }
    }

    private func open(id: String, host: String, port: Int) {
        guard Self.allows(host: host, port: port) else {
            emit(id: id, type: "error", base64: nil)
            return
        }
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            emit(id: id, type: "error", base64: nil)
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
        lock.lock()
        connections[id] = connection
        lock.unlock()
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.emit(id: id, type: "open", base64: nil)
                self.receive(id: id, connection: connection)
            case .failed(_):
                self.close(id: id, notify: true)
            case .cancelled:
                self.close(id: id, notify: true)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receive(id: String, connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                self.emit(id: id, type: "data", base64: data.base64EncodedString())
            }
            if isComplete || error != nil {
                self.close(id: id, notify: true)
                return
            }
            self.receive(id: id, connection: connection)
        }
    }

    private func send(id: String, base64: String) {
        guard let data = Data(base64Encoded: base64), !data.isEmpty else { return }
        lock.lock()
        let connection = connections[id]
        lock.unlock()
        connection?.send(content: data, completion: .contentProcessed { [weak self] error in
            if error != nil {
                self?.close(id: id, notify: true)
            }
        })
    }

    private func close(id: String, notify: Bool) {
        lock.lock()
        let connection = connections.removeValue(forKey: id)
        lock.unlock()
        guard let connection = connection else { return }
        connection.stateUpdateHandler = nil
        connection.cancel()
        if notify {
            emit(id: id, type: "close", base64: nil)
        }
    }

    private func emit(id: String, type: String, base64: String?) {
        let payload = base64.map(Self.jsString) ?? "null"
        let script = "window.__airSocketEvent&&window.__airSocketEvent(\(Self.jsString(id)),\(Self.jsString(type)),\(payload))"
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    private func portValue(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String, let port = Int(text) { return port }
        return 0
    }

    private static func allows(host: String, port: Int) -> Bool {
        guard port > 0, port < 65536 else { return false }
        let name = host.lowercased()
        if name.isEmpty || isBlocked(name) { return false }
        if name == "ied-tqosweb.qq.com" || name.hasSuffix(".huoying.qq.com") || name.hasSuffix(".huoying.com") {
            return true
        }
        let parts = name.split(separator: ".")
        if parts.count == 4, parts.allSatisfy({ Int($0) != nil }) {
            return true
        }
        return false
    }

    private static func isBlocked(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".local") || host == "0.0.0.0" || host == "::1" { return true }
        if host.hasPrefix("127.") || host.hasPrefix("10.") || host.hasPrefix("192.168.") || host.hasPrefix("169.254.") { return true }
        if host.hasPrefix("172.") {
            let parts = host.split(separator: ".")
            if parts.count > 1, let second = Int(parts[1]), (16...31).contains(second) { return true }
        }
        return false
    }

    private static func jsString(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x5C:
                out += "\\\\"
            case 0x22:
                out += "\\\""
            case 0x0A:
                out += "\\n"
            case 0x0D:
                out += "\\r"
            case 0..<0x20:
                out += String(format: "\\u%04x", scalar.value)
            default:
                out.append(Character(scalar))
            }
        }
        out += "\""
        return out
    }
}
