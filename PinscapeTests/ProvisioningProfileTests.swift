import XCTest
#if canImport(PinscapeCore)
@testable import PinscapeCore
#endif

/// Finding the App Group a sideloading tool actually granted, from the profile it embedded.
final class ProvisioningProfileTests: XCTestCase {
    private func profile(groups: [String]?) -> Data {
        var entitlements = "<key>application-identifier</key><string>ABCDE12345.com.pinscape.app.ABCDE12345</string>"
        if let groups {
            entitlements += "<key>com.apple.security.application-groups</key><array>" + groups.map { "<string>\($0)</string>" }.joined() + "</array>"
        }
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>Name</key><string>Sideloaded</string><key>Entitlements</key><dict>\(entitlements)</dict></dict></plist>
        """
        // The plist sits between binary CMS signature data.
        return Data([0x30, 0x82, 0x2D, 0x4F, 0x06, 0x09, 0x2A, 0x86, 0x00, 0xFF]) + Data(plist.utf8) + Data([0xA0, 0x82, 0x0D, 0x00, 0x3C, 0x3F])
    }

    func testReadsARenamedGroup() {
        XCTAssertEqual(ProvisioningProfile.appGroups(in: profile(groups: ["group.com.pinscape.app.ABCDE12345"])), ["group.com.pinscape.app.ABCDE12345"])
    }

    func testIgnoresWildcards() {
        XCTAssertEqual(ProvisioningProfile.appGroups(in: profile(groups: ["group.*", "group.com.pinscape.app"])), ["group.com.pinscape.app"])
    }

    func testNoGroupsGranted() {
        XCTAssertTrue(ProvisioningProfile.appGroups(in: profile(groups: nil)).isEmpty)
        XCTAssertTrue(ProvisioningProfile.appGroups(in: Data([0x00, 0x01, 0x02])).isEmpty)
    }
}
