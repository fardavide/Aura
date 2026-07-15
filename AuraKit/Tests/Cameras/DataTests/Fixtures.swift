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

extension ServerConfig {
    static let test = ServerConfig(
        scheme: .http,
        host: "frigate.test",
        port: 5000,
        username: nil,
        password: nil
    )
}
