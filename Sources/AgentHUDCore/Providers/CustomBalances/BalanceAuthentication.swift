import Foundation

public enum BalanceRequestFailure: Error, LocalizedError, Sendable {
    case authentication(status: Int)

    public var errorDescription: String? {
        switch self {
        case .authentication(let status):
            return L10n.text("认证已失效或权限不足（\(status)），请更新凭据", "Authentication expired or access denied (\(status)); update credentials")
        }
    }

    static func applicationAuthenticationStatus(_ data: Data) -> Int? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let nested = object["error"] as? [String: Any] ?? [:]
        for value in [object["code"], object["status"], object["status_code"], nested["code"], nested["status"]] {
            if let number = value as? Int, [401, 403].contains(number) { return number }
            if let string = value as? String, let number = Int(string), [401, 403].contains(number) { return number }
        }
        return nil
    }
}

/// One prompt per failed-authentication episode. Dismissal stays quiet until recovery, disablement or removal.
public struct BalanceAuthenticationReminders {
    public private(set) var required: Set<String> = []
    private var acknowledged: Set<String> = []
    public init() {}
    public mutating func update(required: Set<String>) {
        self.required = required
        acknowledged.formIntersection(required)
    }
    public var waiting: [String] { required.subtracting(acknowledged).sorted() }
    public mutating func acknowledge(_ id: String) { acknowledged.insert(id) }
}
