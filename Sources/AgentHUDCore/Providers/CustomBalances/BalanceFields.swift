import Foundation
import CoreFoundation

/// JSON Pointer paths identify actual keys even when they contain dots, slashes or tildes.
public struct BalanceField: Hashable, Sendable, Identifiable {
    public let path: String
    public let value: Decimal
    public var id: String { path }
}

public enum BalanceFields {
    public static func parse(_ data: Data) throws -> [BalanceField] {
        guard data.count <= 2_097_152 else { throw UsageProviderError(L10n.text("响应超过 2 MB", "Response exceeds 2 MB")) }
        let root: Any
        do { root = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) }
        catch { throw UsageProviderError(L10n.text("响应不是 JSON，请检查登录状态和接口地址", "Response is not JSON; check the endpoint and sign-in")) }
        var fields: [BalanceField] = []
        func visit(_ value: Any, path: String, depth: Int) {
            guard depth <= 24, fields.count < 512 else { return }
            if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { return }
            if let dictionary = value as? [String: Any] {
                for key in dictionary.keys.sorted() {
                    let escaped = key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
                    visit(dictionary[key]!, path: path + "/" + escaped, depth: depth + 1)
                }
            } else if let array = value as? [Any] {
                for (index, item) in array.prefix(512).enumerated() { visit(item, path: path + "/\(index)", depth: depth + 1) }
            } else if let text = (value as? NSNumber)?.stringValue ?? value as? String,
                      text.range(of: #"^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil,
                      let amount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), !amount.isNaN {
                fields.append(BalanceField(path: path, value: amount))
            }
        }
        visit(root, path: "", depth: 0)
        return fields
    }
}

/// Non-secret settings. HTTP requests live separately in the application's private local data directory.
public struct CustomBalanceProfile: Hashable, Codable, Sendable, Identifiable {
    public enum ValueKind: String, Hashable, Codable, Sendable { case remaining, used }
    public var id: String
    public var name: String
    public var currency: String
    public var balancePath: String
    public var totalPath: String?
    public var divisor: Decimal
    public var enabled: Bool
    public var valueKind: ValueKind
    /// Bumped after verified credential renewal, independently of the balance's unit/mapping identity.
    public var credentialRevision: Int?
    public var avatar: CustomBalanceAvatar?

    public init(id: String = UUID().uuidString, name: String, currency: String, balancePath: String,
                totalPath: String? = nil, divisor: Decimal = 1, enabled: Bool = true, valueKind: ValueKind = .remaining) {
        self.id = id; self.name = name; self.currency = currency; self.balancePath = balancePath
        self.totalPath = totalPath; self.divisor = divisor; self.enabled = enabled
        self.valueKind = valueKind
    }

    public func amounts(in fields: [BalanceField]) throws -> (balance: Decimal, total: Decimal?) {
        guard !divisor.isNaN, divisor > 0, let balance = fields.first(where: { $0.path == balancePath })?.value else {
            throw UsageProviderError(L10n.text("余额字段不存在或单位换算无效", "Missing balance field or invalid unit divisor"))
        }
        let total = totalPath.flatMap { path in fields.first(where: { $0.path == path })?.value }
        guard totalPath == nil || total != nil, total.map({ $0 >= 0 }) ?? true else {
            throw UsageProviderError(L10n.text("总量字段不存在或为负数", "Missing or negative total field"))
        }
        guard valueKind != .used || (total != nil && balance >= 0) else {
            throw UsageProviderError(L10n.text("读取已用值时，必须选择总量字段", "Select a total field when reading used amounts"))
        }
        let remaining = (valueKind == .used ? total! - balance : balance) / divisor
        let limit = total.map { $0 / divisor }
        guard !remaining.isNaN, limit.map({ !$0.isNaN }) ?? true else {
            throw UsageProviderError(L10n.text("字段数值超出范围", "Amount is out of range"))
        }
        return (remaining, limit)
    }

    /// An endpoint may report credits rather than money; never assign those an invented currency symbol.
    public static func format(_ amount: Decimal, unit: String) -> String {
        if Locale.commonISOCurrencyCodes.contains(unit) { return MoneyFormat.amount(amount, currency: unit) }
        return amount.formatted(.number.precision(.fractionLength(0...2))) + " " + unit
    }
}
