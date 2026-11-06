import Foundation
import Darwin
import AgentHUDSupport

/// Request credentials stay in the application's local data directory, outside ordinary settings and reports.
public enum BalanceRequestStore {
    public static var directory: URL { AppSupport.directory.appendingPathComponent("balance-requests", isDirectory: true) }
    public static func save(_ request: BalanceRequest, id: String) throws { try BalanceRequestFiles(directory: directory).save(request, id: id) }
    public static func load(id: String) throws -> BalanceRequest { try BalanceRequestFiles(directory: directory).load(id: id) }
    public static func remove(id: String) throws { try BalanceRequestFiles(directory: directory).remove(id: id) }
}

struct BalanceRequestFiles {
    let directory: URL
    private let manager = FileManager.default
    private static let maximumSize = 1_048_576
    private func file(_ id: String) -> URL { directory.appendingPathComponent(RecordCoding.hash([id]) + ".json") }

    func save(_ request: BalanceRequest, id: String) throws {
        try request.validate()
        let data = try JSONEncoder().encode(request)
        guard data.count <= Self.maximumSize else { throw failure() }
        do {
            try prepareDirectory()
            let destination = file(id)
            if manager.fileExists(atPath: destination.path) { try requireRegularFile(destination) }
            let temporary = directory.appendingPathComponent(".request-" + UUID().uuidString)
            let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
            guard descriptor >= 0 else { throw failure() }
            defer { close(descriptor); try? manager.removeItem(at: temporary) }
            try data.withUnsafeBytes { bytes in
                guard let start = bytes.baseAddress else { throw failure() }
                var count = 0
                while count < bytes.count {
                    let written = Darwin.write(descriptor, start.advanced(by: count), bytes.count - count)
                    if written < 0 && errno == EINTR { continue }
                    guard written > 0 else { throw failure() }
                    count += written
                }
            }
            guard fsync(descriptor) == 0, Darwin.rename(temporary.path, destination.path) == 0 else { throw failure() }
        } catch { throw failure() }
    }

    func load(id: String) throws -> BalanceRequest {
        do {
            try prepareDirectory()
            let url = file(id)
            try requireRegularFile(url)
            let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
            guard descriptor >= 0 else { throw failure() }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: Self.maximumSize + 1) ?? Data()
            guard data.count <= Self.maximumSize else { throw failure() }
            let request = try JSONDecoder().decode(BalanceRequest.self, from: data)
            try request.validate()
            return request
        } catch { throw failure() }
    }

    func remove(id: String) throws {
        try prepareDirectory()
        let url = file(id)
        guard manager.fileExists(atPath: url.path) else { return }
        try requireRegularFile(url)
        try manager.removeItem(at: url)
    }

    private func prepareDirectory() throws {
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard try manager.attributesOfItem(atPath: directory.path)[.type] as? FileAttributeType == .typeDirectory else { throw failure() }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
    private func requireRegularFile(_ url: URL) throws {
        let attributes = try manager.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              ((attributes[.size] as? NSNumber)?.intValue ?? (Self.maximumSize + 1)) <= Self.maximumSize else { throw failure() }
    }
    private func failure() -> UsageProviderError {
        UsageProviderError(L10n.text("无法读取或保存本地认证配置，请重新导入请求", "Cannot read or save the local credentials; import the request again"))
    }
}
