import CoreData
import Foundation
import Testing

@testable import Courier

@MainActor
@Suite("Secrets")
struct SecretStoreTests {

    @Test("Secret values round-trip and never touch Core Data")
    func secretsStayOutOfTheStore() throws {
        let s = try TestStack()
        let workspace = try s.makeWorkspace()
        let environment = try s.environments.createEnvironment(name: "Prod", inWorkspace: workspace)

        let variable = try s.environments.addVariable(
            key: "API_TOKEN",
            value: "super-secret",
            isSecret: true,
            toEnvironment: environment.id
        )

        // The Core Data row holds an empty value...
        #expect(variable.value.isEmpty)
        let stored = try #require(try s.context.fetch(CDVariable.fetchRequest()).first)
        #expect(stored.value.isEmpty)

        // ...and the real value comes back from the secret store.
        #expect(try s.environments.value(for: variable.id) == "super-secret")
        #expect(try s.secrets.value(for: variable.id) == "super-secret")
    }

    @Test("Non-secret values live in Core Data, not the secret store")
    func plainValuesStayInTheStore() throws {
        let s = try TestStack()
        let workspace = try s.makeWorkspace()
        let environment = try s.environments.createEnvironment(name: "Dev", inWorkspace: workspace)

        let variable = try s.environments.addVariable(
            key: "BASE_URL",
            value: "https://example.com",
            isSecret: false,
            toEnvironment: environment.id
        )

        #expect(variable.value == "https://example.com")
        #expect(try s.secrets.value(for: variable.id) == nil)
    }

    @Test("Flipping a variable to secret moves the value out of Core Data")
    func promotingToSecretMovesValue() throws {
        let s = try TestStack()
        let workspace = try s.makeWorkspace()
        let environment = try s.environments.createEnvironment(name: "Dev", inWorkspace: workspace)
        let variable = try s.environments.addVariable(
            key: "TOKEN",
            value: "plain",
            isSecret: false,
            toEnvironment: environment.id
        )

        try s.environments.updateVariable(
            id: variable.id,
            key: "TOKEN",
            value: "now-secret",
            isSecret: true,
            isEnabled: true
        )

        let stored = try #require(try s.context.fetch(CDVariable.fetchRequest()).first)
        #expect(stored.value.isEmpty)
        #expect(try s.secrets.value(for: variable.id) == "now-secret")
    }

    @Test("Flipping a variable back to plain clears its Keychain item")
    func demotingFromSecretClearsKeychain() throws {
        let s = try TestStack()
        let workspace = try s.makeWorkspace()
        let environment = try s.environments.createEnvironment(name: "Dev", inWorkspace: workspace)
        let variable = try s.environments.addVariable(
            key: "TOKEN",
            value: "secret",
            isSecret: true,
            toEnvironment: environment.id
        )

        try s.environments.updateVariable(
            id: variable.id,
            key: "TOKEN",
            value: "public",
            isSecret: false,
            isEnabled: true
        )

        #expect(try s.secrets.value(for: variable.id) == nil)
        #expect(try s.environments.value(for: variable.id) == "public")
    }

    @Test("Deleting a variable deletes its secret")
    func deleteRemovesSecret() throws {
        let s = try TestStack()
        let workspace = try s.makeWorkspace()
        let environment = try s.environments.createEnvironment(name: "Prod", inWorkspace: workspace)
        let variable = try s.environments.addVariable(
            key: "K", value: "v", isSecret: true, toEnvironment: environment.id
        )

        try s.environments.deleteVariable(id: variable.id)
        #expect(try s.secrets.allIdentifiers().isEmpty)
    }

    @Test("Deleting an environment deletes its variables' secrets")
    func deleteEnvironmentRemovesSecrets() throws {
        let s = try TestStack()
        let workspace = try s.makeWorkspace()
        let environment = try s.environments.createEnvironment(name: "Prod", inWorkspace: workspace)
        try s.environments.addVariable(
            key: "A", value: "1", isSecret: true, toEnvironment: environment.id
        )
        try s.environments.addVariable(
            key: "B", value: "2", isSecret: true, toEnvironment: environment.id
        )

        try s.environments.deleteEnvironment(id: environment.id)

        // The cascade would otherwise leave two invisible Keychain items behind.
        #expect(try s.secrets.allIdentifiers().isEmpty)
    }

    @Test("The orphan sweep removes secrets with no variable")
    func sweepRemovesOrphans() throws {
        let s = try TestStack()
        let workspace = try s.makeWorkspace()
        let environment = try s.environments.createEnvironment(name: "Prod", inWorkspace: workspace)
        let live = try s.environments.addVariable(
            key: "LIVE", value: "keep", isSecret: true, toEnvironment: environment.id
        )

        // Simulates a store restored from a backup taken before these existed.
        try s.secrets.set("orphan-1", for: UUID())
        try s.secrets.set("orphan-2", for: UUID())

        let removed = try s.environments.sweepOrphanedSecrets()

        #expect(removed == 2)
        #expect(try s.secrets.allIdentifiers() == [live.id])
    }
}

@MainActor
@Suite("Run history and retention")
struct RunRetentionTests {

    @Test("A completed run stores its payloads and reports its size")
    func completesRun() throws {
        let s = try TestStack()
        let workspace = try s.makeWorkspace()
        let request = try s.library.createRequest(name: "R", in: .workspaceRoot(workspace))

        let run = try s.runs.createRun(
            forRequest: request.id, method: "GET", url: "https://example.com"
        )
        #expect(run.status == .pending)

        let body = Data(#"{"ok":true}"#.utf8)
        try s.runs.complete(
            runID: run.id,
            statusCode: 200,
            statusText: "OK",
            duration: 0.142,
            body: body,
            headersJSON: #"{"Content-Type":"application/json"}"#,
            requestSnapshotJSON: #"{"url":"https://example.com"}"#,
            timingJSON: nil
        )

        let stored = try #require(try s.runs.run(id: run.id))
        #expect(stored.status == .completed)
        #expect(stored.statusCode == 200)
        #expect(stored.duration == 0.142)
        #expect(stored.size == body.count)
        #expect(try s.runs.responseBody(forRun: run.id) == body)
    }

    @Test("A failed run records its message and no status code")
    func failsRun() throws {
        let s = try TestStack()
        let workspace = try s.makeWorkspace()
        let request = try s.library.createRequest(name: "R", in: .workspaceRoot(workspace))
        let run = try s.runs.createRun(forRequest: request.id, method: "GET", url: "bad://url")

        try s.runs.fail(runID: run.id, message: "Could not connect", duration: 1.5)

        let stored = try #require(try s.runs.run(id: run.id))
        #expect(stored.status == .failed)
        #expect(stored.errorMessage == "Could not connect")
        #expect(stored.statusCode == nil)
    }

    @Test("Runs list newest first")
    func runsAreNewestFirst() throws {
        let s = try TestStack()
        let workspace = try s.makeWorkspace()
        let request = try s.library.createRequest(name: "R", in: .workspaceRoot(workspace))

        for index in 0..<3 {
            let run = try s.runs.createRun(
                forRequest: request.id, method: "GET", url: "https://example.com/\(index)"
            )
            // createdAt defaults to now; nudge them apart deterministically.
            let object = try #require(
                try s.context.fetch(CDRun.fetchRequest()).first { $0.id == run.id }
            )
            object.createdAt = Date(timeIntervalSince1970: Double(index))
        }
        try s.context.save()

        let runs = try s.runs.runs(forRequest: request.id)
        #expect(runs.map(\.url) == [
            "https://example.com/2", "https://example.com/1", "https://example.com/0",
        ])
    }

    @Test("Retention keeps the newest N runs per request")
    func prunesToLimit() throws {
        let s = try TestStack()
        let workspace = try s.makeWorkspace()
        let request = try s.library.createRequest(name: "R", in: .workspaceRoot(workspace))

        for index in 0..<10 {
            let run = try s.runs.createRun(
                forRequest: request.id, method: "GET", url: "https://example.com/\(index)"
            )
            let object = try #require(
                try s.context.fetch(CDRun.fetchRequest()).first { $0.id == run.id }
            )
            object.createdAt = Date(timeIntervalSince1970: Double(index))
        }
        try s.context.save()

        let deleted = try HistoryRetention.prune(in: s.context, limit: 3)

        #expect(deleted == 7)
        let remaining = try s.runs.runs(forRequest: request.id)
        #expect(remaining.count == 3)
        #expect(remaining.map(\.url) == [
            "https://example.com/9", "https://example.com/8", "https://example.com/7",
        ])
    }

    @Test("Retention never deletes a starred run")
    func neverPrunesStarred() throws {
        let s = try TestStack()
        let workspace = try s.makeWorkspace()
        let request = try s.library.createRequest(name: "R", in: .workspaceRoot(workspace))

        var firstRunID: UUID?
        for index in 0..<10 {
            let run = try s.runs.createRun(
                forRequest: request.id, method: "GET", url: "https://example.com/\(index)"
            )
            if index == 0 { firstRunID = run.id }
            let object = try #require(
                try s.context.fetch(CDRun.fetchRequest()).first { $0.id == run.id }
            )
            object.createdAt = Date(timeIntervalSince1970: Double(index))
        }
        try s.context.save()

        // Star the oldest — exactly the one retention would otherwise delete first.
        let starred = try #require(firstRunID)
        try s.runs.setStarred(true, forRun: starred)

        try HistoryRetention.prune(in: s.context, limit: 3)

        let remaining = try s.runs.runs(forRequest: request.id)
        #expect(remaining.count == 4)
        #expect(remaining.contains { $0.id == starred })
    }

    @Test("Retention is per-request, not global")
    func prunesPerRequest() throws {
        let s = try TestStack()
        let workspace = try s.makeWorkspace()
        let first = try s.library.createRequest(name: "First", in: .workspaceRoot(workspace))
        let second = try s.library.createRequest(name: "Second", in: .workspaceRoot(workspace))

        for request in [first, second] {
            for index in 0..<5 {
                let run = try s.runs.createRun(
                    forRequest: request.id, method: "GET", url: "https://example.com"
                )
                let object = try #require(
                    try s.context.fetch(CDRun.fetchRequest()).first { $0.id == run.id }
                )
                object.createdAt = Date(timeIntervalSince1970: Double(index))
            }
        }
        try s.context.save()

        try HistoryRetention.prune(in: s.context, limit: 2)

        #expect(try s.runs.runs(forRequest: first.id).count == 2)
        #expect(try s.runs.runs(forRequest: second.id).count == 2)
    }

    @Test("Deleting a request cascades to its runs and payloads")
    func deletingRequestRemovesRuns() throws {
        let s = try TestStack()
        let workspace = try s.makeWorkspace()
        let request = try s.library.createRequest(name: "R", in: .workspaceRoot(workspace))
        let run = try s.runs.createRun(
            forRequest: request.id, method: "GET", url: "https://example.com"
        )
        try s.runs.complete(
            runID: run.id,
            statusCode: 200,
            statusText: "OK",
            duration: 0.1,
            body: Data("hello".utf8),
            headersJSON: "{}",
            requestSnapshotJSON: "{}",
            timingJSON: nil
        )

        try s.library.deleteRequest(id: request.id)

        #expect(try s.context.count(for: CDRun.fetchRequest()) == 0)
        #expect(try s.context.count(for: CDRunResponseBody.fetchRequest()) == 0)
        #expect(try s.context.count(for: CDRunResponseHeaders.fetchRequest()) == 0)
        #expect(try s.context.count(for: CDRunRequestSnapshot.fetchRequest()) == 0)
    }
}
