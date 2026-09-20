import Foundation
import Observation

import CamerasDomain
import CamerasEntities
import ExportsDomain

@Observable
@MainActor
public final class ExportsListViewModel {

    /// What the list is showing. Never returns to `.loading` once rows have rendered.
    public private(set) var state: ExportsListState = .loading
    /// A refresh Aura started itself has been running long enough to be worth saying so. Separate
    /// from `state` on purpose: it draws the header's Updating pill and can never blank the rows
    /// underneath. Deliberately *not* set the instant a refresh starts — the tab's own re-entry
    /// refresh usually finishes in a few milliseconds, and a pill that flashes on every visit is
    /// noise that teaches the user to ignore it.
    public private(set) var isRefreshing = false
    /// When the content on screen was fetched. The stale banner quotes it, so the user is told how
    /// old what they are looking at is rather than just that something went wrong.
    public private(set) var lastUpdated: Date?
    /// The last refresh failed while content was on screen. Costs the banner, never the rows.
    public private(set) var hasStaleContent = false
    /// A retry of the *first* load is running — the unreachable screen's own state.
    public private(set) var isRetrying = false

    /// How the server is addressed, for the unreachable screen to name what it could not reach —
    /// "frigate.local:5000". Injected rather than read here: the connection config belongs to
    /// Settings and the Data layer, and Presentation has no business importing either.
    public let serverLabel: String

    private let getExports: GetExports
    private let getCameras: GetCameras
    private let thumbnailLoader: any ExportThumbnailLoading
    private let now: @MainActor () -> Date
    private let calendar: Calendar
    /// How often the library is re-read while anything is still being cut. The server has no push,
    /// and this stops the moment nothing is in progress.
    private let processingPollInterval: Duration
    /// The retry control stays visibly busy for at least this long, so a server that refuses
    /// instantly still reads as an attempt rather than a control that did nothing.
    private let minimumRetryDuration: Duration
    /// How long a refresh has to run before the Updating pill appears at all.
    private let refreshIndicatorDelay: Duration
    private var cameraNames: [CameraName: String] = [:]
    /// A fetch is running, whether or not it has earned the pill yet.
    private var isFetching = false

    public init(
        getExports: GetExports,
        getCameras: GetCameras,
        thumbnailLoader: any ExportThumbnailLoading,
        serverLabel: String,
        now: @escaping @MainActor () -> Date,
        calendar: Calendar,
        processingPollInterval: Duration,
        minimumRetryDuration: Duration,
        refreshIndicatorDelay: Duration
    ) {
        self.refreshIndicatorDelay = refreshIndicatorDelay
        self.serverLabel = serverLabel
        self.getExports = getExports
        self.getCameras = getCameras
        self.thumbnailLoader = thumbnailLoader
        self.now = now
        self.calendar = calendar
        self.processingPollInterval = processingPollInterval
        self.minimumRetryDuration = minimumRetryDuration
    }

    public var groups: [ExportDayGroup] {
        if case .loaded(let groups) = state { return groups }
        return []
    }

    private var allExports: [Export] {
        groups.flatMap(\.exports)
    }

    /// The header subtitle's numbers. Nil in `.loading` and `.failed`, which know nothing yet;
    /// `.empty` reports a real pair of zeroes.
    public var summary: ExportsSummary? {
        switch state {
        case .loading, .failed: nil
        case .empty: ExportsSummary(clipCount: 0, cameraCount: 0)
        case .loaded: allExports.summary
        }
    }

    /// Whether anything is still being cut — the poll's own on/off switch.
    public var hasProcessingExports: Bool {
        allExports.contains { $0.isProcessing }
    }

    /// The screen's self-load. Only the very first one shows the full-screen spinner; a
    /// re-appearance re-fetches behind the content already on screen.
    public func load() async {
        if state.hasContent {
            await refresh()
        } else {
            await fetch()
        }
    }

    /// A refresh over content: the rows stay, a failure costs only the banner.
    public func refresh() async {
        guard !isFetching else { return }
        isFetching = true
        let indicator = Task { [refreshIndicatorDelay] in
            try? await Task.sleep(for: refreshIndicatorDelay)
            guard !Task.isCancelled, isFetching else { return }
            isRefreshing = true
        }
        await fetch()
        indicator.cancel()
        isFetching = false
        isRefreshing = false
    }

    /// The unreachable screen's Retry. Held visibly busy for `minimumRetryDuration` so an instant
    /// refusal still reads as an attempt.
    public func retry() async {
        guard !isRetrying else { return }
        isRetrying = true
        defer { isRetrying = false }
        async let settled: Void = Task.sleep(for: minimumRetryDuration)
        await fetch()
        try? await settled
    }

    /// Re-reads the library while anything is still being cut, and stops the moment nothing is.
    /// Readiness is the server's answer, so there is nothing to infer locally between polls.
    public func followProcessingExports() async {
        while !Task.isCancelled, hasProcessingExports {
            try? await Task.sleep(for: processingPollInterval)
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    public func displayName(for camera: CameraName) -> String {
        cameraNames[camera] ?? camera.value
    }

    /// "Today", "Yesterday", else the date — the day headings the Headings rotor jumps between.
    /// Relative wording only reaches back one day: "3 days ago" is harder to place than a date.
    public func dayTitle(for group: ExportDayGroup) -> String {
        let today = calendar.startOfDay(for: now())
        if calendar.isDate(group.dayStart, inSameDayAs: today) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           calendar.isDate(group.dayStart, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return group.dayStart.formatted(.dateTime.day().month(.wide))
    }

    public func thumbnail(for export: Export) async -> Data? {
        await thumbnailLoader.thumbnail(for: export)
    }

    private func fetch() async {
        do {
            let exports = try await getExports.execute()
            state = exports.isEmpty ? .empty : .loaded(exports.groupedByDay(calendar: calendar))
            lastUpdated = now()
            hasStaleContent = false
        } catch {
            // Content already on screen is never replaced by an error — that is the whole reason
            // `.loading` and `.failed` are unreachable once rows exist.
            if state.hasContent {
                hasStaleContent = true
            } else {
                state = .failed(error)
            }
        }
        // Best effort: a failed camera read leaves the map empty and cards fall back to the slug.
        cameraNames = ((try? await getCameras.execute()) ?? []).reduce(into: [:]) {
            $0[$1.name] = $1.friendlyName
        }
    }
}
