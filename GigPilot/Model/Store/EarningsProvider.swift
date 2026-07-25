//
//  EarningsProvider.swift
//  GigPilot
//
//  The seam between "where shifts come from" and everything that reads them.
//
//  Today there is one provider: the driver typing a shift in. Later there
//  will be an aggregator — Argyle, Pinwheel, Truv, whichever survives the
//  pricing conversation. Both competitors in this category buy that sync
//  from the same kind of vendor, so it's a commodity input, and commodity
//  inputs belong behind a protocol rather than woven through the store.
//
//  Nothing above this file knows which provider produced a Shift.
//

import Foundation
import SwiftData

// MARK: - Connection state

enum ConnectionStatus: String, Codable {
    /// Never linked.
    case disconnected
    /// Linked and syncing normally.
    case connected
    /// Linked, but the platform wants the driver to log in again. The single
    /// most common failure in this category — treat it as a first-class state,
    /// not an error, because it will happen routinely.
    case needsReauth
    /// Linked, initial backfill still running.
    case syncing

    var label: String {
        switch self {
        case .disconnected: return "Not connected"
        case .connected:    return "Connected"
        case .needsReauth:  return "Sign in again"
        case .syncing:      return "Syncing…"
        }
    }
}

// MARK: - Provider

/// A source of shift data.
protocol EarningsProvider {
    /// Identifier stored on `PlatformAccount` so a row can be traced back.
    var identifier: String { get }

    /// Whether this provider can link accounts at all. Manual entry can't.
    var supportsLinking: Bool { get }

    /// Pulls anything new for `account` since `since`, returning shifts that
    /// have not been persisted yet. The caller owns insertion, so a provider
    /// can be tested without a `ModelContext`.
    func fetchShifts(
        for account: PlatformAccount,
        since: Date,
        context: ModelContext
    ) async throws -> [Shift]

    /// Current link state for an account.
    func status(for account: PlatformAccount) -> ConnectionStatus
}

// MARK: - Manual

/// What ships today: the driver enters shifts through `LogShiftView`, so
/// there is nothing to fetch. Modelling manual entry as a provider rather
/// than a special case means the sync path has no privileged position.
struct ManualEarningsProvider: EarningsProvider {
    let identifier = "manual"
    let supportsLinking = false

    func fetchShifts(
        for account: PlatformAccount,
        since: Date,
        context: ModelContext
    ) async throws -> [Shift] {
        []   // Nothing to pull; the driver already typed it.
    }

    func status(for account: PlatformAccount) -> ConnectionStatus {
        .disconnected
    }
}

// MARK: - Aggregator

enum ProviderError: LocalizedError {
    case notConfigured
    case reauthRequired(platform: String)
    case rateLimited(retryAfter: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "No earnings provider is configured yet."
        case .reauthRequired(let platform):
            return "\(platform) needs you to sign in again."
        case .rateLimited(let retryAfter):
            return "Too many requests. Try again in \(Int(retryAfter)) seconds."
        }
    }
}

/// Placeholder for a consumer-permissioned aggregator.
///
/// Deliberately unimplemented. Wiring this up costs money per connected
/// account per month, which is a commercial decision that has to be settled
/// before it's a technical one — so the shape is fixed here and the work
/// waits. When the contract exists, this is the only type to fill in.
struct AggregatorEarningsProvider: EarningsProvider {
    let identifier: String
    let supportsLinking = true

    /// Injected rather than compiled in, so keys never reach the repository.
    let apiKey: String?

    init(identifier: String = "aggregator", apiKey: String? = nil) {
        self.identifier = identifier
        self.apiKey = apiKey
    }

    func fetchShifts(
        for account: PlatformAccount,
        since: Date,
        context: ModelContext
    ) async throws -> [Shift] {
        guard apiKey != nil else { throw ProviderError.notConfigured }

        // Shape of the eventual implementation:
        //   1. GET the account's gigs and payouts since `since`
        //   2. Group them into blocks of time — the vendor returns per-gig
        //      rows, and this app's unit is a block that may span several
        //      platforms at once, so overlapping windows must be merged
        //      rather than turned into one Shift each
        //   3. Map each platform's total onto a PlatformEarning
        //   4. Deduplicate against existing shifts by (start, platform)
        //
        // Step 2 is the one that matters: emitting one Shift per platform
        // would reintroduce the double-counted hours the data model exists
        // to avoid.
        throw ProviderError.notConfigured
    }

    func status(for account: PlatformAccount) -> ConnectionStatus {
        apiKey == nil ? .disconnected : .connected
    }
}

// MARK: - Registry

/// Resolves which provider backs an account. A single place to change when
/// sync arrives, and a single place to look when a row's origin is unclear.
struct ProviderRegistry {
    private let manual = ManualEarningsProvider()
    private let aggregator: AggregatorEarningsProvider?

    init(aggregator: AggregatorEarningsProvider? = nil) {
        self.aggregator = aggregator
    }

    /// Whether automatic sync is available at all in this build.
    var supportsSync: Bool { aggregator != nil }

    func provider(for account: PlatformAccount) -> EarningsProvider {
        guard let aggregator, account.isLinked else { return manual }
        return aggregator
    }

    /// Refreshes every linked account, skipping any that aren't. Errors are
    /// returned per-account rather than thrown, so one platform needing
    /// re-auth doesn't abort the whole sync.
    func refreshAll(
        accounts: [PlatformAccount],
        since: Date,
        context: ModelContext
    ) async -> [(account: PlatformAccount, result: Result<[Shift], Error>)] {
        // Labels declared here too — an array of unlabelled tuples is a
        // different type and won't convert on return.
        var results: [(account: PlatformAccount, result: Result<[Shift], Error>)] = []
        for account in accounts where account.isLinked {
            do {
                let shifts = try await provider(for: account)
                    .fetchShifts(for: account, since: since, context: context)
                results.append((account, .success(shifts)))
            } catch {
                results.append((account, .failure(error)))
            }
        }
        return results
    }
}
