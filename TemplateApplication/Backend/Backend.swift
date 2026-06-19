//
// This source file is part of the Stanford Spezi Template Application open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

//import Foundation
//
//public enum BackendTarget: String, CaseIterable, Identifiable {
//    case firebase
//    case s3
//
//    public var id: String { rawValue }
//    public var displayName: String {
//        switch self {
//        case .firebase: return "Firebase"
//        case .s3: return "Amazon S3"
//        }
//    }
//}

/// Single source of truth for reading/writing the selected backend.
//enum BackendPrefs {
//    private static let key = "backend.target"
//
//    static func get() -> BackendTarget {
//        let raw = UserDefaults.standard.string(forKey: key) ?? BackendTarget.firebase.rawValue
//        return BackendTarget(rawValue: raw) ?? .firebase
//    }
//
//    static func set(_ target: BackendTarget) {
//        UserDefaults.standard.set(target.rawValue, forKey: key)
//    }
//}
