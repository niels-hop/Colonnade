//
//  PrivilegedInstallerProtocol.swift
//  Loop
//
//  Created by Kai Azim on 2026-02-23.
//

import Foundation

@objc protocol PrivilegedInstallerProtocol {
    /// Performs a privileged swap using a validated rollback token-derived path set.
    func atomicSwap(
        rollbackID: String,
        withReply reply: @escaping (NSError?) -> ()
    )

    /// Restores the current app from the rollback snapshot identified by the rollback token.
    func restoreFromBackup(
        rollbackID: String,
        withReply reply: @escaping (NSError?) -> ()
    )

    /// Removes the authenticated client's current app bundle.
    func removeCurrentBundle(
        withReply reply: @escaping (NSError?) -> ()
    )
}

enum PrivilegedInstallerConstants {
    static let helperExecutableName = "LoopUpdaterHelper"
    static let serviceName = "com.nielshop.Colonnade.UpdaterJob"
    static let appBundleIdentifier = "com.nielshop.Colonnade"
    static let authorizedClientRequirement = "identifier \"com.nielshop.Colonnade\" and anchor apple generic"
}
