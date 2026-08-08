#if SAVED_LAYOUT_STANDALONE_TESTS
import CoreGraphics
import Foundation

@main
enum SavedLayoutFoundationStandaloneTests {
    static func main() async throws {
        try testThreeFixedSlots()
        try testFullHeightNormalization()
        try testExactAndFallbackVariantSelection()
        try testConservativePartialWindowMatching()
        try await testStoreRoundTripAndMigration()
        print("SavedLayoutFoundationStandaloneTests: 5 passed")
    }

    private static func testThreeFixedSlots() throws {
        try expect(SavedLayoutSlot.fixedSlots == [.work, .focus, .macBook], "Slots must remain fixed")
        try expect(Set(SavedLayoutSlot.fixedSlots).count == 3, "Exactly three slots are allowed")
    }

    private static func testFullHeightNormalization() throws {
        let bounds = CGRect(x: 100, y: 40, width: 1_000, height: 600)
        let rail = CGRect(x: 350, y: 40, width: 500, height: 600)
        try expect(SavedLayoutGeometry.isFullHeightRail(rail, in: bounds, tolerance: 1), "Rail rejected")
        try expect(
            !SavedLayoutGeometry.isFullHeightRail(
                CGRect(x: 350, y: 100, width: 500, height: 300),
                in: bounds,
                tolerance: 1
            ),
            "Partial-height window accepted"
        )

        let placement = SavedLayoutGeometry.normalizedPlacement(for: rail, in: bounds)
        try expect(placement?.normalizedX == 0.25, "Unexpected normalized x")
        try expect(placement?.normalizedWidth == 0.5, "Unexpected normalized width")
        try expect(placement?.fullHeightReference == .displayVisibleFrame, "Full-height invariant lost")
    }

    private static func testExactAndFallbackVariantSelection() throws {
        let configuration = displayConfiguration()
        let fingerprintOnly = DisplayIdentity(uuid: nil, configuration: configuration)
        let identified = DisplayIdentity(
            uuid: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"),
            configuration: configuration
        )
        let savedConfiguration = try ConnectedDisplayConfiguration(displays: [fingerprintOnly])
        let currentConfiguration = try ConnectedDisplayConfiguration(displays: [identified])
        let snapshot = try WindowAwarenessSnapshot(
            display: fingerprintOnly,
            windows: [],
            primaryTileID: nil
        )
        let variant = try SavedLayoutVariant(
            displayConfiguration: savedConfiguration,
            displays: [snapshot]
        )

        let exact = SavedLayoutVariantSelector.select(from: [variant], for: savedConfiguration)
        try expect(exact?.basis == .exactConfiguration, "Exact selection not preferred")

        let fallback = SavedLayoutVariantSelector.select(from: [variant], for: currentConfiguration)
        try expect(fallback?.basis == .conservativeDisplayFallback, "Safe fallback not selected")
        try expect(
            SavedLayoutVariantSelector.select(from: [variant, variantWithNewID(variant)], for: currentConfiguration) == nil,
            "Ambiguous fallback should be rejected"
        )
    }

    private static func testConservativePartialWindowMatching() throws {
        let salt = Data(0 ..< 32)
        let placementA = try NormalizedHorizontalPlacement(normalizedX: 0, normalizedWidth: 0.5)
        let placementB = try NormalizedHorizontalPlacement(normalizedX: 0.5, normalizedWidth: 0.5)
        let identityA = try PersistentWindowIdentity(
            bundleIdentifier: "com.example.editor",
            titleOrDocumentHint: PrivateWindowHint(rawValue: "document-a", salt: salt),
            role: "AXWindow",
            ordinalHint: 0,
            frameHint: placementA
        )
        let identityB = try PersistentWindowIdentity(
            bundleIdentifier: "com.example.browser",
            titleOrDocumentHint: PrivateWindowHint(rawValue: "document-b", salt: salt),
            role: "AXWindow",
            ordinalHint: 0,
            frameHint: placementB
        )
        let tileA = try ManagedWindowSnapshot(identity: identityA, placement: placementA, relativeOrder: 0)
        let tileB = try ManagedWindowSnapshot(identity: identityB, placement: placementB, relativeOrder: 1)
        let token = RuntimeWindowToken()
        let result = WindowMatcher.match(
            [tileA, tileB],
            against: [ObservedWindow(token: token, identity: identityA)]
        )

        try expect(result.matched.map(\.runtimeToken) == [token], "Safe partial match was not retained")
        try expect(result.missing.map(\.id) == [tileB.id], "Missing window was not reported")
        try expect(result.ambiguous.isEmpty, "Unambiguous match was rejected")
    }

    private static func testStoreRoundTripAndMigration() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("saved-layout-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("layouts.json")
        let store = AtomicFileSavedLayoutStore(fileURL: fileURL)
        let variant = try makeVariant()
        let library = try SavedLayoutLibrary(work: [variant])

        try await store.save(library)
        let loaded = try await store.load()
        try expect(loaded == library, "Atomic store round-trip failed")

        let encoded = try JSONEncoder().encode(library)
        var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        object["schemaVersion"] = 0
        let migrated = try SavedLayoutLibraryMigrator.decodeAndMigrate(
            JSONSerialization.data(withJSONObject: object)
        )
        try expect(migrated.schemaVersion == SavedLayoutLibrary.currentSchemaVersion, "Migration version failed")
        try expect(migrated.variants(in: .work) == [variant], "Migration changed variants")
    }

    private static func makeVariant() throws -> SavedLayoutVariant {
        let display = DisplayIdentity(uuid: nil, configuration: displayConfiguration())
        let configuration = try ConnectedDisplayConfiguration(displays: [display])
        let snapshot = try WindowAwarenessSnapshot(display: display, windows: [], primaryTileID: nil)
        return try SavedLayoutVariant(displayConfiguration: configuration, displays: [snapshot])
    }

    private static func variantWithNewID(_ variant: SavedLayoutVariant) -> SavedLayoutVariant {
        try! SavedLayoutVariant(
            id: UUID(),
            capturedAt: variant.capturedAt,
            displayConfiguration: variant.displayConfiguration,
            displays: variant.displays
        )
    }

    private static func displayConfiguration() -> DisplayConfiguration {
        DisplayConfiguration(
            vendorID: 1,
            modelID: 2,
            serialNumber: 3,
            pixelWidth: 5120,
            pixelHeight: 1440,
            physicalWidthMillimeters: 1_200,
            physicalHeightMillimeters: 340,
            isBuiltin: false
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw TestFailure(message: message) }
    }

    private struct TestFailure: Error {
        let message: String
    }
}
#endif
