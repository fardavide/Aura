import Foundation

import CommonFrigate
import CommonNetwork

/// The one `GET /api/config` read the Cameras feature shares. Frigate's config is a single heavy
/// document that three separate reads each need a different slice of (the camera list, the camera
/// groups, the recording retention), so it is fetched **once** here and handed to all of them
/// instead of once per reader.
public actor FrigateConfigProvider {
    private let api: FrigateApiClient
    private let configUrl: URL
    private let refreshInterval: Duration
    private var latest: Data?
    private var inFlight: Task<Result<Data, FrigateApiError>, Never>?
    private var observers: [UUID: AsyncStream<Result<Data, FrigateApiError>>.Continuation] = [:]
    private var polling: Task<Void, Never>?

    public init(config: ServerConfig, httpClient: any HttpClient, refreshInterval: Duration) {
        api = FrigateApiClient(config: config, httpClient: httpClient)
        configUrl = FrigateEndpoint.config.url(base: config.baseUrl)
        self.refreshInterval = refreshInterval
    }

    /// The config body, fetched on the first read and reused afterwards.
    public func config() async throws(FrigateApiError) -> Data {
        if let latest { return latest }
        switch await fetch() {
        case .success(let data): return data
        case .failure(let error): throw error
        }
    }

    /// Re-reads the config from the server and pushes it to every observer. Used by the read that
    /// must not serve a stale answer (the camera list behind a pull-to-refresh); it still coalesces
    /// with a fetch already in flight, so a screen load costs one request no matter how many
    /// consumers it has.
    public func reloadConfig() async throws(FrigateApiError) -> Data {
        switch await fetch() {
        case .success(let data): return data
        case .failure(let error): throw error
        }
    }

    /// Re-reads the config and pushes it to every observer. A failure is deliberately swallowed: the
    /// config is best-effort chrome for its consumers, so a trip keeps the last good value rather
    /// than blanking what is on screen.
    public func refresh() async {
        _ = await fetch()
    }

    /// The config as it changes: the loaded one first (fetched if this is the first read), then the
    /// outcome of every refresh. Failures are emitted too — a subscriber gating its first paint on
    /// this stream would otherwise wait forever on an unreachable server. Deciding what a failure
    /// means (blank the slot, or keep the last good value) is the subscriber's call.
    public func observeConfig() -> AsyncStream<Result<Data, FrigateApiError>> {
        AsyncStream { continuation in
            let id = UUID()
            observers[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.stopObserving(id) }
            }
            startPolling()
            if let latest {
                continuation.yield(.success(latest))
            } else {
                // Nothing loaded yet: fetch so a subscriber that got here before any read still
                // receives a first value. Coalesced, so it joins a fetch already in flight.
                Task { await self.refresh() }
            }
        }
    }

    /// Keeps the config current for as long as anyone is watching. One loop serves every observer,
    /// and it only runs while there is one — so a closed screen stops polling the server.
    private func startPolling() {
        guard polling == nil else { return }
        // `weak self` so the loop can't keep the provider alive through its own task.
        polling = Task { [weak self, refreshInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: refreshInterval)
                guard !Task.isCancelled, let self else { return }
                await refresh()
            }
        }
    }

    private func stopObserving(_ id: UUID) {
        observers.removeValue(forKey: id)
        guard observers.isEmpty else { return }
        polling?.cancel()
        polling = nil
    }

    private func broadcast(_ outcome: Result<Data, FrigateApiError>) {
        for continuation in observers.values {
            continuation.yield(outcome)
        }
    }

    /// Fetches the config, collapsing callers that arrive while a fetch is already running onto that
    /// one request. The `Result` keeps the typed error through `Task`, which can't express it.
    private func fetch() async -> Result<Data, FrigateApiError> {
        if let inFlight { return await inFlight.value }
        let task = Task<Result<Data, FrigateApiError>, Never> { [api, configUrl] in
            do throws(FrigateApiError) {
                return .success(try await api.get(configUrl))
            } catch {
                return .failure(error)
            }
        }
        inFlight = task
        let result = await task.value
        inFlight = nil
        if case .success(let data) = result {
            latest = data
        }
        broadcast(result)
        return result
    }
}
