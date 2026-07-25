//
//  GigPilotApp.swift
//  GigPilot
//
//  Earnings intelligence for multi-app drivers.
//

import SwiftUI
import SwiftData

@main
struct GigPilotApp: App {

    /// One on-disk store for the whole app. Built once here rather than with
    /// `.modelContainer(for:)` so a failure is loud instead of silent.
    private let container: ModelContainer = {
        let schema = Schema(GigPilotSchema.all)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create the GigPilot model container: \(error)")
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
    /// In-memory container seeded with the demo week, for `#Preview` blocks.
    @MainActor
    static var preview: ModelContainer = {
        let schema = Schema(GigPilotSchema.all)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        Seed.bootstrapIfNeeded(container.mainContext)
        return container
    }()
}
