import Foundation

public struct BalanceRequestPart: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let value: String
    public let isCookie: Bool
    public var keep: Bool
    public var isAuthentication: Bool
}

/// An editable allowlist; removing browser metadata must not remove user-selected routing or CSRF headers.
public struct BalanceRequestSelection: Sendable {
    public let original: BalanceRequest
    public var parts: [BalanceRequestPart]

    public init(_ request: BalanceRequest, preserveSavedSelection: Bool = false) {
        original = request
        parts = request.headers.keys.sorted { $0.lowercased() < $1.lowercased() }.flatMap { name -> [BalanceRequestPart] in
            let value = request.headers[name]!
            if name.lowercased() == "cookie" {
                return BalanceRequest.cookies(value).map {
                    BalanceRequestPart(id: "cookie:" + $0.name, name: $0.name, value: $0.value, isCookie: true,
                                       keep: true, isAuthentication: true)
                }
            }
            let lower = name.lowercased()
            let browserOnly = lower.hasPrefix("sec-") || ["user-agent", "accept-encoding", "accept-language", "priority", "dnt",
                "cache-control", "pragma", "upgrade-insecure-requests", "referer", "origin", "x-client-data",
                "host", "content-length", "connection", "transfer-encoding"].contains(lower)
            return [BalanceRequestPart(id: "header:" + lower, name: name, value: value, isCookie: false,
                keep: preserveSavedSelection || !browserOnly,
                isAuthentication: request.authenticationHeaders.map { $0.contains(lower) } ?? BalanceRequest.isAuthenticationHeader(name))]
        }
    }

    public var canProbe: Bool {
        original.method == "GET" && parts == Self(original).parts
    }

    /// Try only a freshly imported GET and leave manual selections to the exact-request test.
    public func probe(requiredPaths: Set<String> = [],
                      fetch: (BalanceRequest) async throws -> [BalanceField] = { try await BalanceRequestClient.fetch($0) })
        async throws -> (selection: Self, fields: [BalanceField], attempts: Int) {
        guard canProbe else {
            throw UsageProviderError(L10n.text("智能测试需要新导入且未手动调整的 GET 请求", "Smart test requires a newly imported GET with its suggested selection"))
        }
        func isCookieContext(_ part: BalanceRequestPart) -> Bool {
            let name = part.name.lowercased()
            return part.isCookie || name.contains("csrf") || name.contains("xsrf")
        }
        var candidates: [Self] = []
        if parts.contains(where: { $0.keep && $0.isAuthentication && !isCookieContext($0) }) {
            var tokenOnly = self
            for index in parts.indices where isCookieContext(parts[index]) { tokenOnly.parts[index].keep = false }
            if tokenOnly.parts != parts { candidates.append(tokenOnly) }
        }
        candidates.append(self)
        var withOrigin = self
        for index in parts.indices where !parts[index].isCookie && ["origin", "referer"].contains(parts[index].name.lowercased()) {
            withOrigin.parts[index].keep = true
        }
        if withOrigin.parts != parts { candidates.append(withOrigin) }

        for (index, candidate) in candidates.enumerated() {
            try Task.checkCancellation()
            let fields: [BalanceField]
            do {
                fields = try await fetch(candidate.request())
            } catch is BalanceRequestFailure where index < candidates.count - 1 {
                continue
            }
            try Task.checkCancellation()
            let paths = Set(fields.map(\.path))
            let hasValues = !requiredPaths.isEmpty
                ? requiredPaths.isSubset(of: paths)
                : paths.contains { !["/code", "/status", "/status_code", "/error"].contains($0) && !$0.hasPrefix("/error/") }
            if hasValues { return (candidate, fields, index + 1) }
        }
        throw UsageProviderError(L10n.text("未读取到预期字段，请检查响应或手动测试请求",
                                            "Expected fields were not found. Inspect the response or test the request manually."))
    }

    public func request() -> BalanceRequest {
        var result = original
        result.headers = [:]
        result.authenticationHeaders = []
        var cookies: [String] = []
        for part in parts where part.keep {
            if part.isCookie { cookies.append(part.name + "=" + part.value) }
            else {
                result.headers[part.name] = part.value
                if part.isAuthentication { result.authenticationHeaders?.insert(part.name.lowercased()) }
            }
        }
        if !cookies.isEmpty {
            result.headers["Cookie"] = cookies.joined(separator: "; ")
            result.authenticationHeaders?.insert("cookie")
        }
        return result
    }
}

public extension BalanceRequest {
    static func isAuthenticationHeader(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower == "cookie" || lower.contains("auth") || lower.contains("secret") || lower.contains("token") || lower.contains("api-key") ||
            lower.contains("apikey") || lower.contains("csrf") || lower.contains("session")
    }

    /// Only names leave the vault for the renewal form; existing values are never prefilled.
    var credentialHeaderNames: [String] {
        headers.keys.filter { name in
            authenticationHeaders.map { $0.contains(name.lowercased()) } ?? Self.isAuthenticationHeader(name)
        }.sorted()
    }

    func replacingCredentials(_ values: [String: String]) throws -> BalanceRequest {
        var result = self
        var changed = false
        for name in credentialHeaderNames {
            guard let raw = values[name], !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.utf8.contains(where: { ($0 < 32 && $0 != 9) || $0 == 127 }) else {
                throw UsageProviderError(L10n.text("认证值不能包含换行", "Credentials must not contain line breaks"))
            }
            if name.lowercased() == "cookie" {
                let incoming = Self.cookies(value)
                let kept = Self.cookies(headers[name] ?? "")
                guard incoming.contains(where: { item in kept.contains { $0.name == item.name } }) else {
                    throw UsageProviderError(L10n.text("Cookie 中没有已选中的认证项", "No selected cookie names were found"))
                }
                value = kept.map { item in
                    item.name + "=" + (incoming.last { $0.name == item.name }?.value ?? item.value)
                }.joined(separator: "; ")
            } else if name.lowercased() == "authorization", headers[name]?.lowercased().hasPrefix("bearer ") == true,
                      !value.contains(" ") { value = "Bearer " + value }
            result.headers[name] = value
            changed = true
        }
        guard changed else { throw UsageProviderError(L10n.text("请填写至少一项新凭据", "Enter at least one updated credential")) }
        try result.validate()
        return result
    }

    static func cookies(_ value: String) -> [(name: String, value: String)] {
        var result: [(name: String, value: String)] = []
        for fragment in value.split(separator: ";") {
            guard let index = fragment.firstIndex(of: "=") else { continue }
            let name = fragment[..<index].trimmingCharacters(in: .whitespaces)
            let value = fragment[fragment.index(after: index)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !result.contains(where: { $0.name == name }) else { continue }
            result.append((name, value))
        }
        return result
    }
}
