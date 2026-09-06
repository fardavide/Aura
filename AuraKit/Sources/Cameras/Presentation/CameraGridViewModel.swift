import Foundation
import Observation

import CamerasDomain
import CamerasEntities

@Observable
@MainActor
public final class CameraGridViewModel {
    public enum State: Equatable {
        case loading
        case loaded([Camera])
        case empty
        case failed(CamerasError)
    }

    public private(set) var state: State = .loading
    /// The activity Frigate is currently tracking, keyed by camera — empty when there is none or
    /// the (best-effort) fetch failed, so the grid still loads without badges.
    public private(set) var activity: [CameraName: CameraActivity] = [:]

    /// The user's camera groups (the filter chips) and the one currently selected (nil = All). All
    /// three summary fields below are best-effort and load-time only — a missing one just leaves its
    /// slot of the summary card blank; none of them are on the refresh loop.
    public private(set) var groups: [CameraGroup] = []
    public private(set) var selectedGroupName: String?
    /// Today's event tally (the summary card's TODAY column).
    public private(set) var todayEvents: EventCount?
    /// Recording-disk status (the summary card's RECORDING column).
    public private(set) var storage: RecordingStorage?

    private let observeCameras: ObserveCameras
    private let getCameraActivity: GetCameraActivity
    private let observeCameraGroups: ObserveCameraGroups
    private let getTodayEventCounts: GetTodayEventCounts
    private let observeRecordingStorage: ObserveRecordingStorage
    private let imageLoader: any CameraImageLoading
    private var observation: Task<Void, Never>?
    private var groupsObservation: Task<Void, Never>?
    private var storageObservation: Task<Void, Never>?
    private var previews: [CameraName: Data] = [:]
    private var offlineCameras: Set<CameraName> = []

    public init(
        observeCameras: ObserveCameras,
        getCameraActivity: GetCameraActivity,
        observeCameraGroups: ObserveCameraGroups,
        getTodayEventCounts: GetTodayEventCounts,
        observeRecordingStorage: ObserveRecordingStorage,
        imageLoader: any CameraImageLoading
    ) {
        self.observeCameras = observeCameras
        self.getCameraActivity = getCameraActivity
        self.observeCameraGroups = observeCameraGroups
        self.getTodayEventCounts = getTodayEventCounts
        self.observeRecordingStorage = observeRecordingStorage
        self.imageLoader = imageLoader
    }

    isolated deinit {
        observation?.cancel()
        groupsObservation?.cancel()
        storageObservation?.cancel()
    }

    /// Loaded cameras whose preview still failed to load — our one honest per-camera offline signal.
    /// Narrowed to `visibleCameras`: the chips describe exactly the cameras the wall shows.
    public var offlineCount: Int {
        visibleCameras.filter { offlineCameras.contains($0.name) }.count
    }

    /// The loaded cameras the selected group keeps — the full list when no group (or a stale one) is
    /// selected. What the grid actually renders.
    public var visibleCameras: [Camera] {
        guard case .loaded(let cameras) = state else { return [] }
        guard let name = selectedGroupName, let group = groups.first(where: { $0.name == name }) else {
            return cameras
        }
        return cameras.filter { group.contains($0.name) }
    }

    /// The wall's hero: the visible camera with the most recently started **alert** — never a mere
    /// detection, so the 2 s activity loop can't churn the layout for ordinary motion — else the
    /// first visible camera; nil when there is none to show.
    public var heroCamera: Camera? {
        let alertedCameras = visibleCameras.compactMap { camera -> (Camera, Date)? in
            guard let activity = activity[camera.name], activity.severity == .alert else { return nil }
            return (camera, activity.startedAt)
        }
        if let mostRecent = alertedCameras.max(by: { $0.1 < $1.1 }) {
            return mostRecent.0
        }
        return visibleCameras.first
    }

    /// The wall's ordered source: the hero first, then every other visible camera keeping their
    /// existing order. The single list `CameraGridView`'s one `ForEach` iterates.
    public var wallCameras: [Camera] {
        guard let heroCamera else { return visibleCameras }
        return [heroCamera] + visibleCameras.filter { $0.id != heroCamera.id }
    }

    /// The single most significant thing happening now (the chip row's activity chip): an alert
    /// outranks a detection, ties break on recency. Nil when all is quiet. Carries the camera so the
    /// chip can navigate straight to it. Narrowed to `visibleCameras`: the chips describe exactly the
    /// cameras the wall shows.
    public var rightNow: RightNow? {
        let active = visibleCameras.compactMap { camera in activity[camera.name].map { (camera, $0) } }
        guard let best = active.max(by: { lhs, rhs in
            (rank(lhs.1.severity), lhs.1.startedAt) < (rank(rhs.1.severity), rhs.1.startedAt)
        }) else {
            return nil
        }
        return RightNow(camera: best.0, label: best.1.label, severity: best.1.severity)
    }

    /// The most significant current activity, resolved to the camera it's on.
    public struct RightNow: Equatable, Sendable {
        public let camera: Camera
        public let label: String
        public let severity: CameraActivity.Severity
    }

    private func rank(_ severity: CameraActivity.Severity) -> Int {
        switch severity {
        case .alert: 1
        case .detection: 0
        }
    }

    /// "N today" for the chip row's second chip; nil while the day's tally hasn't loaded.
    public var todayChipText: String? {
        guard let todayEvents else { return nil }
        return "\(todayEvents.total) today"
    }

    /// The two most frequent labels ("9 person · 5 car"), appended to the today chip on regular
    /// width; nil while the tally hasn't loaded or carries no breakdown.
    public var todayBreakdownText: String? {
        guard let todayEvents, !todayEvents.breakdown.isEmpty else { return nil }
        return todayEvents.breakdown.prefix(2).map { "\($0.count) \($0.label)" }.joined(separator: " · ")
    }

    /// "N day(s) kept", appended to the storage chip on regular width; nil without a retention figure.
    public var retentionChipText: String? {
        guard let days = storage?.retentionDays else { return nil }
        return "\(days) day\(days == 1 ? "" : "s") kept"
    }

    /// "N offline" for the chip row's fourth chip; nil while every visible camera is reachable.
    public var offlineChipText: String? {
        guard offlineCount > 0 else { return nil }
        return "\(offlineCount) offline"
    }

    /// Whether the chip row has anything to show — gates it so a quiet screen whose best-effort reads
    /// both failed never renders an empty `ScrollView` between two gaps.
    public var hasSummaryChips: Bool {
        rightNow != nil || todayChipText != nil || storage != nil || offlineChipText != nil
    }

    /// Picks the group to filter by; nil shows every camera.
    public func selectGroup(_ name: String?) {
        selectedGroupName = name
    }

    /// Fetches and replaces the content. Only the very first load shows the full-screen spinner: a
    /// re-appearance re-fetches behind the current content, and a failed refresh keeps the last good
    /// content. The view model owns preview and activity loading so the tiles stay pure — they never
    /// write back into it mid-render.
    public func load() async {
        do {
            let cameras = try await observeCameras.execute()
            // A racing load() may have assigned a fresh observation while we were suspended
            // above — cancel it too, or it would leak and keep writing state forever.
            observation?.cancel()
            await withCheckedContinuation { continuation in
                observation = Task { [weak self] in
                    var firstEmission: CheckedContinuation<Void, Never>? = continuation
                    for await list in cameras {
                        self?.state = list.isEmpty ? .empty : .loaded(list)
                        firstEmission?.resume()
                        firstEmission = nil
                    }
                    firstEmission?.resume()
                }
            }
        } catch {
            if case .loaded = state { return }
            state = .failed(error)
            return
        }
        guard case .loaded(let cameras) = state else { return }
        await refreshContent(for: cameras)
        await loadSummary()
    }

    /// Re-pulls the stills and activity for the cameras already on screen — the grid drives this on
    /// a timer so the "LIVE" tiles and badges stay current without a manual pull-to-refresh. Cheaper
    /// than `load()`: it doesn't re-subscribe to the camera list, nor re-pull the (slow-moving)
    /// groups and summary card.
    public func refresh() async {
        guard case .loaded(let cameras) = state else { return }
        await refreshContent(for: cameras)
    }

    public func activity(for camera: Camera) -> CameraActivity? {
        activity[camera.name]
    }

    public func previewImage(for camera: Camera) -> Data? {
        previews[camera.name]
    }

    /// Whether the grid saw this camera's preview still fail to load.
    public func isOffline(_ camera: Camera) -> Bool {
        offlineCameras.contains(camera.name)
    }

    private func refreshContent(for cameras: [Camera]) async {
        // Best-effort: a missing badge must never fail the grid.
        activity = (try? await getCameraActivity.execute()) ?? [:]
        await loadPreviews(for: cameras)
    }

    /// The grid's chrome — filter chips + the summary card. Every piece is best-effort: a slot that
    /// fails to load just stays blank, never failing the grid.
    ///
    /// Groups and storage are *observed*: both are read out of the shared server config, which
    /// re-reads itself periodically, so they keep up on their own instead of only at load time.
    /// Each observation still awaits its first value here, so a settled `load()` means a settled
    /// screen — what the snapshot suite and the pull-to-refresh spinner both expect.
    private func loadSummary() async {
        await observeGroups()
        todayEvents = try? await getTodayEventCounts.execute()
        await observeStorage()
    }

    private func observeGroups() async {
        guard groupsObservation == nil else { return }
        let stream = observeCameraGroups.execute()
        await withCheckedContinuation { continuation in
            groupsObservation = Task { [weak self] in
                var firstEmission: CheckedContinuation<Void, Never>? = continuation
                for await list in stream {
                    self?.groups = list
                    firstEmission?.resume()
                    firstEmission = nil
                }
                firstEmission?.resume()
                // Cleared so a later load() re-subscribes if the stream ended.
                self?.groupsObservation = nil
            }
        }
    }

    private func observeStorage() async {
        guard storageObservation == nil else { return }
        let stream = observeRecordingStorage.execute()
        await withCheckedContinuation { continuation in
            storageObservation = Task { [weak self] in
                var firstEmission: CheckedContinuation<Void, Never>? = continuation
                for await value in stream {
                    self?.storage = value
                    firstEmission?.resume()
                    firstEmission = nil
                }
                firstEmission?.resume()
                self?.storageObservation = nil
            }
        }
    }

    private func loadPreviews(for cameras: [Camera]) async {
        await withTaskGroup(of: (CameraName, Data?).self) { group in
            for camera in cameras {
                group.addTask { [imageLoader] in
                    (camera.name, await imageLoader.previewImage(for: camera.name))
                }
            }
            for await (name, data) in group {
                if let data {
                    previews[name] = data
                    offlineCameras.remove(name)
                } else {
                    offlineCameras.insert(name)
                }
            }
        }
    }
}
