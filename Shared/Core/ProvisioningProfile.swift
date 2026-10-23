import Foundation

/// Reads the App Groups an install's provisioning profile grants. Sideloading tools re-sign with
/// their own profile and often rename the group, so the name Pinscape was built with may not exist.
enum ProvisioningProfile {
    /// The groups in an `embedded.mobileprovision`: a signed blob wrapping an XML property list.
    static func appGroups(in data: Data) -> [String] {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: Data(data[start.lowerBound..<end.upperBound]), format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String]
        else { return [] }
        return groups.filter { !$0.contains("*") }
    }
}
