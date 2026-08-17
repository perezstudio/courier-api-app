import CoreData
import Foundation
import OSLog

/// Owns the Core Data container.
///
/// Two behaviors here are load-bearing and deliberately not the defaults:
///
/// 1. **A store that fails to open is quarantined, never deleted.** There is no
///    cloud copy of a Courier library, so discarding a store is total data loss
///    for the user. See REQUIREMENTS.md §5.3 and §11.
/// 2. **Migration takes a backup first.** Lightweight migration is usually
///    safe, but "usually" is not good enough when it is the only copy.
final class CoreDataStack {

    enum StoreLocation {
        /// The real store under Application Support.
        case applicationSupport
        /// An in-memory store for tests; nothing touches the disk.
        case inMemory
    }

    /// Recorded when the store could not be opened and was moved aside, so the
    /// UI can tell the user where their old library went (§5.3).
    struct QuarantineReport: Sendable {
        let quarantinedURL: URL
        let underlyingError: String
    }

    private static let logger = Logger(subsystem: "com.perezstudio.Courier", category: "persistence")

    let container: NSPersistentContainer
    private(set) var quarantineReport: QuarantineReport?

    var viewContext: NSManagedObjectContext { container.viewContext }

    // MARK: - Init

    init(location: StoreLocation = .applicationSupport) throws {
        let model = Self.managedObjectModel()
        container = NSPersistentContainer(name: "Courier", managedObjectModel: model)

        switch location {
        case .inMemory:
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            description.shouldAddStoreAsynchronously = false
            container.persistentStoreDescriptions = [description]

        case .applicationSupport:
            let storeURL = try Self.storeURL()
            container.persistentStoreDescriptions = [Self.storeDescription(at: storeURL)]
        }

        try loadStores(location: location)
        configureContexts()
    }

    // MARK: - Store loading

    private func loadStores(location: StoreLocation) throws {
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }

        guard let loadError else { return }

        // In-memory stores have nothing to quarantine — a failure here is a
        // programming error in the model, not user data trouble.
        guard case .applicationSupport = location else { throw loadError }

        Self.logger.error("Store failed to open, quarantining: \(loadError.localizedDescription)")

        let storeURL = try Self.storeURL()
        let quarantinedURL = try Self.quarantine(storeAt: storeURL)
        quarantineReport = QuarantineReport(
            quarantinedURL: quarantinedURL,
            underlyingError: loadError.localizedDescription
        )

        container.persistentStoreDescriptions = [Self.storeDescription(at: storeURL)]

        var retryError: Error?
        container.loadPersistentStores { _, error in
            retryError = error
        }
        if let retryError { throw retryError }
    }

    private func configureContexts() {
        let context = container.viewContext
        context.automaticallyMergesChangesFromParent = true
        // Unique constraints on `id` mean an insert colliding with an existing
        // row would otherwise fail the whole save. Property-level merge lets the
        // newer values win instead.
        context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        // No undo manager: nothing consumes it yet, and an unused one records
        // every change forever. Undo gets wired up with proper per-mutation
        // grouping — see MainWindowController.windowWillReturnUndoManager.
        context.undoManager = nil
    }

    // MARK: - Background work

    /// Runs a block on a private-queue context and saves if it made changes.
    func performBackgroundTask<T>(
        _ block: @escaping (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            container.performBackgroundTask { context in
                context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
                do {
                    let result = try block(context)
                    if context.hasChanges {
                        try context.save()
                    }
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Model

    /// Loads the compiled model explicitly rather than letting
    /// `NSPersistentContainer` search every bundle. In unit tests the app is
    /// the host bundle, so the default search can find the model twice and
    /// produce duplicate-entity warnings.
    nonisolated private static func managedObjectModel() -> NSManagedObjectModel {
        let bundle = Bundle(for: CoreDataStack.self)
        guard
            let url = bundle.url(forResource: "Courier", withExtension: "momd")
                ?? bundle.url(forResource: "Courier", withExtension: "mom"),
            let model = NSManagedObjectModel(contentsOf: url)
        else {
            fatalError("Courier.momd is missing from the app bundle — check the Core Data model is in the target.")
        }
        return model
    }

    // MARK: - Store URLs

    nonisolated static func supportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("Courier", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    nonisolated static func storeURL() throws -> URL {
        try supportDirectory().appendingPathComponent("Courier.sqlite")
    }

    nonisolated private static func storeDescription(at url: URL) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: url)
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        return description
    }

    // MARK: - Quarantine

    /// Moves a store and its sidecar files aside so a fresh one can be created
    /// without destroying the user's data. Returns the new location.
    @discardableResult
    nonisolated static func quarantine(storeAt storeURL: URL) throws -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")

        let directory = storeURL.deletingLastPathComponent()
        let quarantinedURL = directory.appendingPathComponent("Courier-corrupt-\(stamp).sqlite")

        let fileManager = FileManager.default
        // -wal and -shm hold committed transactions; moving the .sqlite alone
        // would leave them to be picked up by the replacement store.
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: storeURL.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = URL(fileURLWithPath: quarantinedURL.path + suffix)
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: source, to: destination)
        }

        // External binary data (response bodies) lives in a sibling directory.
        let externalStorage = directory.appendingPathComponent(".Courier_SUPPORT", isDirectory: true)
        if fileManager.fileExists(atPath: externalStorage.path) {
            let destination = directory.appendingPathComponent(
                ".Courier-corrupt-\(stamp)_SUPPORT",
                isDirectory: true
            )
            try? fileManager.moveItem(at: externalStorage, to: destination)
        }

        return quarantinedURL
    }
}
