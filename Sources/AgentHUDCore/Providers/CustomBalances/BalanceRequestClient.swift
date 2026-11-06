import Foundation

public enum BalanceRequestClient {
    public static func fetch(_ definition: BalanceRequest) async throws -> [BalanceField] {
        try await fetch(definition, configuration: .ephemeral)
    }

    static func fetch(_ definition: BalanceRequest, configuration config: URLSessionConfiguration) async throws -> [BalanceField] {
        try definition.validate()
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: definition.url)
        request.httpMethod = definition.method
        request.allHTTPHeaderFields = definition.headers
        request.httpBody = definition.body?.data(using: .utf8)
        if definition.body != nil, request.value(forHTTPHeaderField: "Content-Type") == nil {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else { throw UsageProviderError(L10n.text("无效的 HTTP 响应", "Invalid HTTP response")) }
            if [401, 403].contains(response.statusCode) { throw BalanceRequestFailure.authentication(status: response.statusCode) }
            if (300...399).contains(response.statusCode), let location = response.value(forHTTPHeaderField: "Location"),
               let target = URL(string: location, relativeTo: definition.url),
               ["login", "signin", "sign-in", "sso", "oauth", "authorize"].contains(where: { target.path.lowercased().contains($0) }) {
                throw BalanceRequestFailure.authentication(status: response.statusCode)
            }
            guard (200...299).contains(response.statusCode) else {
                // Neither the response body nor URL enters a report: either can contain credentials.
                throw UsageProviderError(L10n.text("余额查询返回 HTTP \(response.statusCode)，请检查登录凭据", "Balance query returned HTTP \(response.statusCode); check credentials"))
            }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 2_097_152 else { throw UsageProviderError(L10n.text("响应超过 2 MB", "Response exceeds 2 MB")) }
                data.append(byte)
            }
            if let status = BalanceRequestFailure.applicationAuthenticationStatus(data) { throw BalanceRequestFailure.authentication(status: status) }
            return try BalanceFields.parse(data)
        } catch let error as BalanceRequestFailure { throw error }
        catch let error as UsageProviderError { throw error }
        catch {
            if Task.isCancelled { throw CancellationError() }
            throw UsageProviderError(L10n.text("余额请求失败，请检查网络或重新导入登录凭据", "Balance request failed; check the connection or import fresh credentials"))
        }
    }
}

private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
