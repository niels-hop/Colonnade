//
//  WindowAwarenessCoreGraphicsAdapter.swift
//  Colonnade
//
//  Ephemeral CoreGraphics bindings kept outside the persistent awareness model.
//

import ColorSync
import CoreGraphics
import Foundation

// MARK: - RuntimeWindowBinding

/// Launch-local bridge from a pure matching token to WindowServer identifiers.
/// This type is intentionally not Codable and must never be written to the store.
struct RuntimeWindowBinding: Sendable {
    let token: RuntimeWindowToken
    let cgWindowID: CGWindowID
    let processIdentifier: pid_t
}

// MARK: - CoreGraphicsDisplayIdentityAdapter

enum CoreGraphicsDisplayIdentityAdapter {
    static func identity(for displayID: CGDirectDisplayID) -> DisplayIdentity {
        let physicalSize = CGDisplayScreenSize(displayID)
        let configuration = DisplayConfiguration(
            vendorID: CGDisplayVendorNumber(displayID),
            modelID: CGDisplayModelNumber(displayID),
            serialNumber: CGDisplaySerialNumber(displayID),
            pixelWidth: CGDisplayPixelsWide(displayID),
            pixelHeight: CGDisplayPixelsHigh(displayID),
            physicalWidthMillimeters: Int(physicalSize.width.rounded()),
            physicalHeightMillimeters: Int(physicalSize.height.rounded()),
            isBuiltin: CGDisplayIsBuiltin(displayID) != 0
        )

        let displayUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
        let uuid = displayUUID.flatMap {
            UUID(uuidString: CFUUIDCreateString(nil, $0) as String)
        }
        return DisplayIdentity(uuid: uuid, configuration: configuration)
    }
}
