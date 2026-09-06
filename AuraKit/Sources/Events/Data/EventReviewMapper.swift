extension [EventReviewDto] {
    /// The union of `data.detections` over the items whose `severity == "alert"`. Unknown
    /// severities (`detection`, `significant_motion`, anything new) contribute nothing, so a
    /// future Frigate severity degrades to "not an alert" instead of crashing.
    func alertEventIds() -> Set<String> {
        reduce(into: Set<String>()) { ids, item in
            guard item.severity == "alert" else { return }
            ids.formUnion(item.data?.detections ?? [])
        }
    }
}
