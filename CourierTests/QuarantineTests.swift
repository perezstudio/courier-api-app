import Foundation
import Testing

@testable import Courier

/// The quarantine path (REQUIREMENTS.md §5.3). The pre-rewrite app *deleted*
/// a store that failed to open, which silently destroyed the user's library.
/// With no cloud copy, moving it aside is the difference between a bad day and
/// unrecoverable loss — so it gets a test.
@Suite("Corrupt store quarantine")
struct QuarantineTests {

    /// A scratch directory holding a fake store and its sidecar files.
    private func makeFakeStore() throws -> (directory: URL, storeURL: URL) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("courier-quarantine-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let storeURL = directory.appendingPathComponent("Courier.sqlite")
        try Data("main".utf8).write(to: storeURL)
        try Data("wal".utf8).write(to: URL(fileURLWithPath: storeURL.path + "-wal"))
        try Data("shm".utf8).write(to: URL(fileURLWithPath: storeURL.path + "-shm"))

        return (directory, storeURL)
    }

    @Test("Quarantine preserves the store instead of deleting it")
    func preservesData() throws {
        let (directory, storeURL) = try makeFakeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let quarantined = try CoreDataStack.quarantine(storeAt: storeURL)

        let fileManager = FileManager.default
        #expect(!fileManager.fileExists(atPath: storeURL.path))
        #expect(fileManager.fileExists(atPath: quarantined.path))
        #expect(try Data(contentsOf: quarantined) == Data("main".utf8))
        #expect(quarantined.lastPathComponent.hasPrefix("Courier-corrupt-"))
    }

    @Test("Quarantine moves the -wal and -shm sidecars too")
    func movesSidecars() throws {
        let (directory, storeURL) = try makeFakeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let quarantined = try CoreDataStack.quarantine(storeAt: storeURL)

        let fileManager = FileManager.default
        // Leaving these behind would let a fresh store adopt the old store's
        // uncheckpointed transactions — a subtle and very confusing corruption.
        #expect(!fileManager.fileExists(atPath: storeURL.path + "-wal"))
        #expect(!fileManager.fileExists(atPath: storeURL.path + "-shm"))
        #expect(fileManager.fileExists(atPath: quarantined.path + "-wal"))
        #expect(fileManager.fileExists(atPath: quarantined.path + "-shm"))
    }

    @Test("Quarantine moves the external binary storage directory")
    func movesExternalStorage() throws {
        let (directory, storeURL) = try makeFakeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Response bodies over the inline threshold live here.
        let support = directory.appendingPathComponent(".Courier_SUPPORT", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try Data("body".utf8).write(to: support.appendingPathComponent("blob"))

        _ = try CoreDataStack.quarantine(storeAt: storeURL)

        #expect(!FileManager.default.fileExists(atPath: support.path))
        let moved = try FileManager.default
            .contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix("_SUPPORT") }
        #expect(moved.count == 1)
    }

    @Test("Quarantine tolerates missing sidecars")
    func toleratesMissingSidecars() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("courier-quarantine-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("Courier.sqlite")
        try Data("main".utf8).write(to: storeURL)

        let quarantined = try CoreDataStack.quarantine(storeAt: storeURL)
        #expect(FileManager.default.fileExists(atPath: quarantined.path))
    }
}
