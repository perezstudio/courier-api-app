import CoreData
import Foundation
import Testing

@testable import Courier

/// Environments driving resolution, end to end through the repositories.
@MainActor
@Suite("Environments and resolution")
struct EnvironmentTests {

    private func makeController() throws -> (LibraryController, InMemorySecretStore) {
        let stack = try CoreDataStack(location: .inMemory)
        let secrets = InMemorySecretStore()
        let controller = LibraryController(stack: stack, secretStore: secrets)
        controller.load()
        return (controller, secrets)
    }

    @Test("An environment's variables resolve at environment scope")
    func resolvesFromEnvironment() throws {
        let (controller, _) = try makeController()
        let workspace = try #require(controller.activeWorkspaceID)

        let environment = try controller.environments.createEnvironment(
            name: "Prod", inWorkspace: workspace
        )
        try controller.environments.addVariable(
            key: "host", value: "api.example.com", isSecret: false,
            toEnvironment: environment.id
        )
        controller.setActiveEnvironment(environment.id)

        let context = controller.makeVariableContext()
        #expect(context.binding(for: "host")?.value == "api.example.com")
        #expect(context.binding(for: "host")?.scope == .environment)
    }

    @Test("Collection variables resolve at collection scope")
    func resolvesFromCollection() throws {
        let (controller, _) = try makeController()
        let workspace = try #require(controller.activeWorkspaceID)

        try controller.environments.addCollectionVariable(
            key: "version", value: "v2", isSecret: false, toWorkspace: workspace
        )

        let context = controller.makeVariableContext()
        #expect(context.binding(for: "version")?.value == "v2")
        #expect(context.binding(for: "version")?.scope == .collection)
    }

    @Test("The environment wins over the collection for the same name")
    func environmentBeatsCollection() throws {
        let (controller, _) = try makeController()
        let workspace = try #require(controller.activeWorkspaceID)

        try controller.environments.addCollectionVariable(
            key: "host", value: "collection.example.com", isSecret: false, toWorkspace: workspace
        )
        let environment = try controller.environments.createEnvironment(
            name: "Prod", inWorkspace: workspace
        )
        try controller.environments.addVariable(
            key: "host", value: "env.example.com", isSecret: false, toEnvironment: environment.id
        )
        controller.setActiveEnvironment(environment.id)

        let context = controller.makeVariableContext()
        #expect(context.binding(for: "host")?.value == "env.example.com")
        #expect(context.binding(for: "host")?.scope == .environment)
    }

    @Test("With no active environment, only collection variables resolve")
    func withoutActiveEnvironment() throws {
        let (controller, _) = try makeController()
        let workspace = try #require(controller.activeWorkspaceID)

        let environment = try controller.environments.createEnvironment(
            name: "Prod", inWorkspace: workspace
        )
        try controller.environments.addVariable(
            key: "host", value: "env.example.com", isSecret: false, toEnvironment: environment.id
        )
        try controller.environments.addCollectionVariable(
            key: "version", value: "v1", isSecret: false, toWorkspace: workspace
        )
        // Deliberately not activated.

        let context = controller.makeVariableContext()
        #expect(context.binding(for: "host") == nil)
        #expect(context.binding(for: "version")?.value == "v1")
    }

    @Test("Disabled variables do not resolve")
    func skipsDisabled() throws {
        let (controller, _) = try makeController()
        let workspace = try #require(controller.activeWorkspaceID)

        let environment = try controller.environments.createEnvironment(
            name: "Prod", inWorkspace: workspace
        )
        let variable = try controller.environments.addVariable(
            key: "host", value: "api.example.com", isSecret: false,
            toEnvironment: environment.id
        )
        controller.setActiveEnvironment(environment.id)
        try controller.environments.updateVariable(
            id: variable.id, key: "host", value: "api.example.com",
            isSecret: false, isEnabled: false
        )

        #expect(controller.makeVariableContext().binding(for: "host") == nil)
    }

    @Test("Secret values resolve from the Keychain, not from Core Data")
    func resolvesSecretsFromKeychain() throws {
        let (controller, secrets) = try makeController()
        let workspace = try #require(controller.activeWorkspaceID)

        let environment = try controller.environments.createEnvironment(
            name: "Prod", inWorkspace: workspace
        )
        let variable = try controller.environments.addVariable(
            key: "token", value: "s3cret", isSecret: true, toEnvironment: environment.id
        )
        controller.setActiveEnvironment(environment.id)

        // Core Data holds nothing; the resolver still produces the real value.
        let stored = try #require(
            try controller.environments.environments(forWorkspace: workspace).first?.variables.first
        )
        #expect(stored.value.isEmpty)
        #expect(try secrets.value(for: variable.id) == "s3cret")
        #expect(controller.makeVariableContext().binding(for: "token")?.value == "s3cret")
    }

    @Test("Switching the active environment changes what resolves")
    func switchingEnvironments() throws {
        let (controller, _) = try makeController()
        let workspace = try #require(controller.activeWorkspaceID)

        let dev = try controller.environments.createEnvironment(name: "Dev", inWorkspace: workspace)
        try controller.environments.addVariable(
            key: "host", value: "dev.example.com", isSecret: false, toEnvironment: dev.id
        )
        let prod = try controller.environments.createEnvironment(name: "Prod", inWorkspace: workspace)
        try controller.environments.addVariable(
            key: "host", value: "prod.example.com", isSecret: false, toEnvironment: prod.id
        )

        controller.setActiveEnvironment(dev.id)
        #expect(controller.makeVariableContext().binding(for: "host")?.value == "dev.example.com")

        controller.setActiveEnvironment(prod.id)
        #expect(controller.makeVariableContext().binding(for: "host")?.value == "prod.example.com")

        controller.setActiveEnvironment(nil)
        #expect(controller.makeVariableContext().binding(for: "host") == nil)
    }

    @Test("Changing the active environment notifies every window")
    func notifiesOnEnvironmentChange() throws {
        let (controller, _) = try makeController()
        let workspace = try #require(controller.activeWorkspaceID)
        let environment = try controller.environments.createEnvironment(
            name: "Prod", inWorkspace: workspace
        )

        var notifications = 0
        let token = controller.observe { notifications += 1 }

        controller.setActiveEnvironment(environment.id)

        // Every tab's URL bar and Variables tab must re-resolve.
        #expect(notifications >= 1)
        token.cancelNow()
    }

    @Test("A resolved request uses the active environment")
    func buildsRequestWithEnvironment() throws {
        let (controller, _) = try makeController()
        let workspace = try #require(controller.activeWorkspaceID)

        let environment = try controller.environments.createEnvironment(
            name: "Prod", inWorkspace: workspace
        )
        try controller.environments.addVariable(
            key: "host", value: "api.example.com", isSecret: false, toEnvironment: environment.id
        )
        try controller.environments.addVariable(
            key: "token", value: "abc", isSecret: true, toEnvironment: environment.id
        )
        controller.setActiveEnvironment(environment.id)

        let input = RequestBuilder.Input(
            method: "GET",
            urlTemplate: "https://{{host}}/users",
            headers: [KeyValueRow(key: "X-Token", value: "{{token}}")],
            queryParams: [],
            bodyType: .none,
            bodyContent: "",
            auth: .empty,
            authSecret: nil,
            timeout: 30,
            followRedirects: true
        )
        let output = RequestBuilder.build(input, context: controller.makeVariableContext())

        #expect(output.request.url == "https://api.example.com/users")
        #expect(output.request.headers.contains { $0.name == "X-Token" && $0.value == "abc" })
        #expect(output.unresolved.isEmpty)
    }

    @Test("Deleting an environment clears it as the active one")
    func deletingActiveEnvironment() throws {
        let (controller, _) = try makeController()
        let workspace = try #require(controller.activeWorkspaceID)
        let environment = try controller.environments.createEnvironment(
            name: "Prod", inWorkspace: workspace
        )
        controller.setActiveEnvironment(environment.id)
        #expect(controller.activeEnvironmentID == environment.id)

        controller.setActiveEnvironment(nil)
        try controller.environments.deleteEnvironment(id: environment.id)
        controller.reloadTree()

        // A dangling activeEnvironmentID would resolve nothing while the picker
        // still showed a name.
        #expect(controller.activeEnvironmentID == nil)
        #expect(controller.environmentsForActiveWorkspace().isEmpty)
    }

    @Test("Collection variables are separate from environment variables")
    func separatesScopes() throws {
        let (controller, _) = try makeController()
        let workspace = try #require(controller.activeWorkspaceID)

        let environment = try controller.environments.createEnvironment(
            name: "Prod", inWorkspace: workspace
        )
        try controller.environments.addVariable(
            key: "inEnv", value: "1", isSecret: false, toEnvironment: environment.id
        )
        try controller.environments.addCollectionVariable(
            key: "inCollection", value: "2", isSecret: false, toWorkspace: workspace
        )

        let collection = try controller.environments.collectionVariables(forWorkspace: workspace)
        #expect(collection.map(\.key) == ["inCollection"])

        let environments = try controller.environments.environments(forWorkspace: workspace)
        #expect(environments.first?.variables.map(\.key) == ["inEnv"])
    }
}
