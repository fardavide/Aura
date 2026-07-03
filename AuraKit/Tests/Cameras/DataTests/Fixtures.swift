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

extension ServerConfig {
    static let test = ServerConfig(
        scheme: .http,
        host: "frigate.test",
        port: 5000,
        username: nil,
        password: nil
    )
}
