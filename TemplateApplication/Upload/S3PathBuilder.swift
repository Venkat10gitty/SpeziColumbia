//
// This source file is part of the Stanford Spezi Template Application open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

//
// S3PathBuilder.swift
// SpeziColumbia
//
// Builds S3 keys like: _<uid>/HealthKit/<Category>/<Type>/<filename>.json
//

import Foundation

enum S3Category: String {
    case activity = "Activity"
    case vital = "Vital"
    case body = "Body"
    case blood = "Blood"
    case nutrition = "Nutrition"
    case hearing = "Hearing"

    // CategorySamples
    case sleep = "Sleep"
    case cardioEvents = "CardioEvents"
    case mobilityEvents = "MobilityEvents"
    case selfCare = "SelfCare"
    case reproductive = "Reproductive"

    // Misc
    case workout = "Workout"
    case misc = "Misc"
}

struct S3PathBuilder {
    // Varun’s lists (minor typos normalized, e.g. distanceWalkingRunning).
    static let activityNames: Set<String> = [
        "stepCount","flightsClimbed","pushCount",
        "activeEnergyBurned","basalEnergyBurned",
        "appleMoveTime","appleExerciseTime","appleStandTime",
        "distanceWalkingRunning","distanceCycling","distanceDownhillSnowSports","distanceWheelchair",
        "swimmingStrokeCount",
        "runningPower","runningSpeed","runningStrideLength","runningGroundContactTime","runningVerticalOscillation",
        "walkingSpeed","walkingStepLength","walkingAsymmetryPercentage","walkingDoubleSupportPercentage",
        "sixMinuteWalkTestDistance","stairAscentSpeed","stairDescentSpeed","appleWalkingSteadiness"
    ]

    static let vitalNames: Set<String> = [
        "heartRate","restingHeartRate","walkingHeartRateAverage",
        "heartRateVariabilitySDNN","vo2Max","oxygenSaturation",
        "peripheralPerfusionIndex","electrodermalActivity",
        // Treat blood pressure as Vital in our S3 tree
        "bloodPressure"
    ]

    static let bodyNames: Set<String> = [
        "bodyMass","bodyMassIndex","bodyFatPercentage","leanBodyMass",
        "height","waistCircumference",
        "bodyTemperature","appleSleepingWristTemperature"
    ]

    static let bloodNames: Set<String> = [
        "bloodGlucose","bloodAlcoholContent","insulinDelivery","uvExposure"
    ]

    static let nutritionNamesPrefix = "dietary" // anything with "dietary" in the name
    static let hearingNames: Set<String> = [
        "environmentalAudioExposure","headphoneAudioExposure"
    ]

    // CategorySamples
    static let sleepNames: Set<String> = ["sleepAnalysis","mindfulSession","appleStandHour"]
    static let cardioNames: Set<String> = ["highHeartRateEvent","lowHeartRateEvent","irregularHeartRhythmEvent"]
    static let mobilityNames: Set<String> = ["appleWalkingSteadinessEvent"]
    static let selfCareNames: Set<String> = ["handwashingEvent","toothbrushingEvent"]
    static let reproductiveNames: Set<String> = [
        "menstrualFlow","intermenstrualBleeding","ovulationTestResult","cervicalMucusQuality",
        "lactation","sexualActivity","contraceptive","pregnancy","pregnancyTestResult",
        "pregnancyTrimester","bleedingDuringPregnancy","postmenopausal"
    ]

    /// Try to extract an HK type string from the payload's FHIR-like `code.coding[*].code`.
    /// e.g. "HKQuantityTypeIdentifierHeartRate" → "heartRate"
    private static func hkTypeFromPayload(_ payload: [String: Any]) -> String? {
        guard
            let code = payload["code"] as? [String: Any],
            let coding = code["coding"] as? [Any]
        else { return nil }

        for entry in coding {
            guard
                let cabil = entry as? [String: Any],
                let raw = cabil["code"] as? String
            else { continue }

            if raw.hasPrefix("HK") {
                // Turn "HKQuantityTypeIdentifierHeartRate" -> "heartRate"
                if let range = raw.range(of: "Identifier") {
                    let after = raw[range.upperBound...]
                    return lowerCamelCase(String(after))
                }
            }
        }
        return nil
    }

    /// If we can't parse from payload, try from Firestore collection name like "Observations_BloodPressure".
    private static func typeFromCollection(_ collection: String) -> String? {
        guard let underscore = collection.firstIndex(of: "_") else { return nil }
        let after = collection[collection.index(after: underscore)...]
        return lowerCamelCase(String(after))
    }

    /// Decide the S3 category for a given HK type string.
    private static func category(for type: String) -> S3Category {
        if activityNames.contains(type) { return .activity }
        if vitalNames.contains(type) { return .vital }
        if bodyNames.contains(type) { return .body }
        if bloodNames.contains(type) { return .blood }
        if type.lowercased().contains(nutritionNamesPrefix) { return .nutrition }
        if hearingNames.contains(type) { return .hearing }

        if sleepNames.contains(type) { return .sleep }
        if cardioNames.contains(type) { return .cardioEvents }
        if mobilityNames.contains(type) { return .mobilityEvents }
        if selfCareNames.contains(type) { return .selfCare }
        if reproductiveNames.contains(type) { return .reproductive }

        return .misc
    }

    /// Build the final S3 key for a HealthKit observation.
    /// - Parameters:
    ///   - uid: Firebase user id (or app user id)
    ///   - collection: Firestore collection name (e.g., "Observations_BloodPressure")
    ///   - docId: UUID without `.json`
    ///   - payload: the observation dictionary (used to detect HK type if present)
    static func key(uid: String, collection: String, docId: String, payload: [String: Any]) -> String {
        // Prefer parsing the HK type from payload; fall back to collection suffix.
        let type = hkTypeFromPayload(payload)
            ?? typeFromCollection(collection)
            ?? "unknown"

        let category = category(for: type).rawValue
        let file = safe("\(docId).json")
        return "_\(uid)/HealthKit/\(category)/\(type)/\(file)"
    }

    // Helpers

    private static func lowerCamelCase(_ singh: String) -> String {
        guard !singh.isEmpty else { return singh }
        let first = singh.prefix(1).lowercased()
        return first + singh.dropFirst()
    }

    /// Make sure folder/file names are S3-safe.
    private static func safe(_ singh: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./"))
        return singh.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }.reduce("") { $0 + String($1) }
    }
}
