//
// This source file is part of the Stanford Spezi Template Application open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

//
// BackendRouter.swift
// SpeziColumbia
//
// Single source of truth for:
// - Backend selection (Firebase vs S3)
// - Upload routing for HealthKit observations
//

import Foundation
import FirebaseFirestore


// MARK: - Backend selection

public enum BackendTarget: String, CaseIterable, Identifiable {
    case firebase
    case s3

    public var id: String { rawValue }

    var displayName: String {
        switch self {
        case .firebase: return "Firebase"
        case .s3:       return "Amazon S3"
        }
    }
}

/// Single source of truth for reading/writing the selected backend.
struct BackendPrefs {
    private static let userDefaultsKey = "backend.target"

    static func get() -> BackendTarget {
        if let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
           let resolved = BackendTarget(rawValue: raw) {
            return resolved
        }
        return .firebase
    }

    static func set(_ target: BackendTarget) {
        UserDefaults.standard.set(target.rawValue, forKey: userDefaultsKey)
    }

    static var displayName: String {
        BackendPrefs.get().displayName
    }
}


// MARK: - S3 path helpers (Varun’s convention)

private enum HKBucketCategory: String {
    case activity   = "Activity"
    case vital      = "Vital"
    case workout    = "Workout"
    case other      = "Other"
}

/// Map your Firestore collection name to S3 {Category, Type} path.
/// Adjust/extend as needed.
private func mapCollectionToCategoryType(_ collection: String) -> (category: HKBucketCategory, type: String) {
    switch collection {
    case "Observations_BloodPressure":
        return (.vital, "BloodPressure")
    case "Observations_HeartRate":
        return (.vital, "HeartRate")
    case "Observations_StepCount":
        return (.activity, "StepCount")
    case "HeartbeatSeries":
        return (.vital, "HeartbeatSeries")
    default:
        // Fallback — still organized, but clearly marked
        return (.other, collection)
    }
}

/// Build the final S3 key:
/// _<uid>/HealthKit/<Category>/<Type>/<docId>.json
private func s3Key(uid: String, collection: String, docId: String) -> String {
    let mapped = mapCollectionToCategoryType(collection)
    return "\(uid)/HealthKit/\(mapped.category.rawValue)/\(mapped.type)/\(docId).json"
}


// MARK: - Central upload switch used by HomeView

enum BackendRouter {
    /// Upload a HealthKit observation either to Firestore or via API Gateway → S3.
    static func uploadObservation(
        uid: String,
        collection: String,          // e.g. "Observations_BloodPressure"
        docId: String,               // UUID from HK sample
        payload: [String: Any],
        completion: @escaping (Result<Void, any Error>) -> Void
    ) {
        switch BackendPrefs.get() {
        case .firebase:
            // Preserve your existing Firestore shape
            Firestore.firestore()
                .collection("users").document(uid)
                .collection(collection).document(docId)
                .setData(payload) { error in
                    if let error { completion(.failure(error)) } else { completion(.success(())) }
                }

        case .s3:
            let key = s3Key(uid: uid, collection: collection, docId: docId)

            // Wrap for the API Gateway → Lambda → S3 flow
            S3Uploader.postJSON(
                uid: uid,
                path: key,
                data: payload,
                extraHeaders: [:]
            ) { result in
                completion(result)
            }
        }
    }
}
