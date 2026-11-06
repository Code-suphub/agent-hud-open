import Foundation

/// Parsed as data. No part of an imported command is passed to a shell or curl process.
public struct BalanceRequest: Codable, Hashable, Sendable {
    public var url: URL
    public var method: String
    public var headers: [String: String]
    public var body: String?
    /// Headers selected for future credential renewal. Nil infers common names for older saved requests.
    public var authenticationHeaders: Set<String>?

    public init(url: URL, method: String = "GET", headers: [String: String] = [:], body: String? = nil) {
        self.url = url; self.method = method; self.headers = headers; self.body = body
    }

    public static func parse(curl: String, forSelection: Bool = false) throws -> Self {
        let words = try tokenize(curl)
        guard words.first == "curl" else { throw invalid("请粘贴以 curl 开头的请求", "Paste a request starting with curl") }
        var url: URL?, method: String?, headers: [String: String] = [:], body: String?
        var index = 1
        func value() throws -> String {
            index += 1
            guard index < words.count else { throw invalid("请求参数不完整", "Incomplete request option") }
            return words[index]
        }
        while index < words.count {
            let word = words[index]
            switch word {
            case "-X", "--request": method = try value().uppercased()
            case "-H", "--header":
                let header = try value()
                guard let colon = header.firstIndex(of: ":") else { throw invalid("请求头格式无效", "Invalid header") }
                let key = String(header[..<colon]).trimmingCharacters(in: .whitespaces)
                let val = String(header[header.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty, !header.utf8.contains(10), !header.utf8.contains(13) else { throw invalid("请求头格式无效", "Invalid header") }
                if let old = headers.keys.first(where: { $0.caseInsensitiveCompare(key) == .orderedSame }) { headers.removeValue(forKey: old) }
                headers[key] = val
            case "-b", "--cookie":
                let cookie = try value()
                guard cookie.contains("="), !cookie.utf8.contains(10), !cookie.utf8.contains(13) else {
                    throw invalid("请使用 Cookie 文本，不能读取文件", "Use literal cookies, not a cookie file")
                }
                if let old = headers.keys.first(where: { $0.lowercased() == "cookie" }) { headers.removeValue(forKey: old) }
                headers["Cookie"] = cookie
            case "-d", "--data", "--data-raw", "--data-binary":
                let data = try value()
                guard body == nil, word == "--data-raw" || !data.hasPrefix("@") else {
                    throw invalid("只支持一段内联请求体，不能读取文件", "Use one inline request body; files are unsupported")
                }
                body = data
            case "--url":
                guard url == nil else { throw invalid("只支持一个请求地址", "Use a single request URL") }
                url = URL(string: try value())
            case "--compressed", "--silent", "-s", "--show-error", "-S", "--fail", "-f": break
            default:
                guard !word.hasPrefix("-"), url == nil else {
                    throw invalid("包含不支持的 curl 参数，请仅保留地址、请求头和请求体", "Unsupported curl option; keep the URL, headers and inline body")
                }
                url = URL(string: word)
            }
            index += 1
        }
        guard let url else { throw invalid("缺少请求地址", "Missing request URL") }
        let request = Self(url: url, method: method ?? (body == nil ? "GET" : "POST"), headers: headers, body: body)
        try request.validate(allowManagedHeaders: forSelection)
        return request
    }

    public func validate() throws {
        try validate(allowManagedHeaders: false)
    }

    private func validate(allowManagedHeaders: Bool) throws {
        guard url.scheme?.lowercased() == "https", url.host != nil, url.user == nil, url.password == nil,
              url.fragment == nil, ["GET", "POST"].contains(method), !(method == "GET" && body != nil) else {
            throw Self.invalid("仅支持 HTTPS 的 GET / POST 查询请求", "Use an HTTPS GET or POST query")
        }
        for (key, value) in headers {
            guard !key.isEmpty, key.utf8.allSatisfy({ (33...126).contains($0) && $0 != 58 }),
                  !value.utf8.contains(where: { ($0 < 32 && $0 != 9) || $0 == 127 }),
                  allowManagedHeaders || !["host", "content-length", "connection", "transfer-encoding"].contains(key.lowercased()) else {
                throw Self.invalid("包含无效或由客户端管理的请求头", "Invalid or client-managed header")
            }
        }
    }

    private static func invalid(_ zh: String, _ en: String) -> UsageProviderError { UsageProviderError(L10n.text(zh, en)) }

    private static func tokenize(_ source: String) throws -> [String] {
        guard source.utf8.count <= 131_072 else { throw invalid("请求内容过长", "Request is too large") }
        var words: [String] = [], word = "", quote: Character?, escaped = false, started = false
        for char in source {
            if escaped {
                if char != "\n" {
                    if quote == "\"", !"\\\"$`".contains(char) { word.append("\\") }
                    word.append(char); started = true
                }
                escaped = false; continue
            }
            if let current = quote {
                if char == current { quote = nil }
                else if char == "\\", current == "\"" { escaped = true }
                else { word.append(char) }
            } else if char == "\\" { escaped = true }
            else if char == "'" || char == "\"" { quote = char; started = true }
            else if char.isWhitespace {
                if started { words.append(word); word = ""; started = false }
            } else {
                guard !";|&<>`$()".contains(char) else { throw invalid("不支持 Shell 表达式", "Shell expressions are unsupported") }
                word.append(char); started = true
            }
        }
        guard quote == nil, !escaped else { throw invalid("请求引号或转义不完整", "Unclosed quote or escape") }
        if started { words.append(word) }
        return words
    }
}
