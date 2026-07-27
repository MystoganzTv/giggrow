//
//  GigGrowApp.swift
//  GigGrow
//
//  Earnings intelligence for multi-app drivers.
//

import SwiftUI
import SwiftData

@main
struct GigGrowApp: App {

    /// One on-disk store for the whole app. Built once here rather than with
    /// `.modelContainer(for:)` so a failure is loud instead of silent.
    private let container: ModelContainer = {
        let schema = Schema(GigGrowSchema.all)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create the GigGrow model container: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}

// MARK: - Previews

extension ModelContainer {

    /// In-memory container with the demo week loaded, for `#Preview` blocks.
    /// `let`, not `var` — a mutable static is shared global state and trips
    /// concurrency checking the moment the project moves to Swift 6.
    @MainActor
    static let preview: ModelContainer = {
        let container = makeInMemory()
        #if DEBUG
        Seed.loadDemoData(container.mainContext)
        #endif
        return container
    }()

    /// In-memory container with only the platform catalogue — the state a
    /// real first launch is in. Used by the onboarding and empty-state previews.
    @MainActor
    static let previewEmpty: ModelContainer = {
        let container = makeInMemory()
        Seed.bootstrapPlatformsIfNeeded(container.mainContext)
        return container
    }()

    private static func makeInMemory() -> ModelContainer {
        let schema = Schema(GigGrowSchema.all)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Preview container: \(error)")
        }
    }
}
