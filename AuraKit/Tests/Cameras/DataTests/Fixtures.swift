import Foundation

import CommonFrigate
import CommonNetwork

/// A representative `/api/config` body covering the cases the mapper must handle:
/// an enabled camera with friendly name + streams, a disabled camera, and a camera
/// with no `enabled` field (defaults to enabled) and empty streams.
let configJson = """
{
  "cameras": {
    "driveway": {
      "enabled": true,
      "friendly_name": "Driveway",
      "live": { "streams": { "Driveway HD": "driveway", "Driveway SD": "driveway_sub" } }
    },
    "garage": {
      "enabled": false
    },
    "porch": {
      "friendly_name": "Front Porch",
      "live": { "streams": {} }
    }
  }
}
"""

/// A representative `/api/review` body covering the cases the activity mapper must handle: an
/// in-progress alert with a tracked object, an in-progress detection, a completed item (has an
/// `end_time` — dropped), and a `significant_motion` item (severity we don't badge — dropped).
let reviewJson = """
[
  { "id": "1-a", "camera": "front_door", "start_time": 1000.0, "end_time": null,
    "severity": "alert", "data": { "objects": ["person"] } },
  { "id": "1-b", "camera": "driveway", "start_time": 1005.0, "end_time": null,
    "severity": "detection", "data": { "objects": ["car"] } },
  { "id": "1-c", "camera": "backyard", "start_time": 900.0, "end_time": 950.0,
    "severity": "alert", "data": { "objects": ["person"] } },
  { "id": "1-d", "camera": "garage", "start_time": 1010.0, "end_time": null,
    "severity": "significant_motion", "data": { "objects": [] } }
]
"""

/// A representative `camera_groups` slice of `/api/config` covering the cases the groups mapper must
/// handle: an array-form membership, a comma-joined-string membership (what Frigate's UI writes), and
/// a group naming only the Birdseye composite (stripped → empty). `order` drives sorting.
let groupsConfigJson = """
{
  "camera_groups": {
    "Outdoor": { "cameras": ["driveway", "front_door"], "icon": "cctv", "order": 1 },
    "Indoor": { "cameras": "kitchen,garage", "icon": "home", "order": 0 },
    "Overview": { "cameras": "birdseye", "order": 2 }
  }
}
"""

/// A representative `/api/stats` body: the recordings mount plus another volume. Values are MiB.
let statsJson = """
{
  "service": {
    "version": "0.17.2",
    "storage": {
      "/media/frigate/recordings": { "total": 1953125.0, "used": 488281.0, "free": 1464844.0, "mount_type": "ext4" },
      "/tmp/cache": { "total": 1000.0, "used": 100.0, "free": 900.0, "mount_type": "tmpfs" }
    }
  }
}
"""

/// A representative `record` slice of `/api/config` — the four retention knobs; the effective
/// "days kept" is their max (14 here).
let recordConfigJson = """
{
  "record": {
    "enabled": true,
    "continuous": { "days": 7 },
    "motion": { "days": 0 },
    "alerts": { "retain": { "days": 14, "mode": "motion" } },
    "detections": { "retain": { "days": 10, "mode": "motion" } }
  }
}
"""

/// A representative `/api/events` body for the "today" tally — only `label` is read.
let todayEventsJson = """
[
  { "id": "e1", "camera": "driveway", "label": "person", "start_time": 1000.0 },
  { "id": "e2", "camera": "front_door", "label": "car", "start_time": 1001.0 },
  { "id": "e3", "camera": "driveway", "label": "person", "start_time": 1002.0 }
]
"""

extension ServerConfig {
    static let test = ServerConfig(
        scheme: .http,
        host: "frigate.test",
        port: 5000,
        username: nil,
        password: nil
    )
}
