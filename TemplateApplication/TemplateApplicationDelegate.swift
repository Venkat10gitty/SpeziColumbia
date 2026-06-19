//
// This source file is part of the Stanford Spezi Template Application open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

//
// TemplateApplicationDelegate.swift
//

//
// TemplateApplicationDelegate.swift
//

import class FirebaseFirestore.FirestoreSettings
import class FirebaseFirestore.MemoryCacheSettings
import Spezi
import SpeziAccount
import SpeziFirebaseAccount
import SpeziFirebaseAccountStorage
import SpeziFirebaseStorage
import SpeziFirestore
import SpeziHealthKit
import SpeziNotifications
import SpeziOnboarding
import SpeziScheduler
import SwiftUI

import SpeziBluetooth
import SpeziBluetoothServices
import SpeziDevices
import SpeziLLM
import SpeziLLMOpenAI
import SpeziOmron


class TemplateApplicationDelegate: SpeziAppDelegate {
    override var configuration: Configuration {
        Configuration(standard: TemplateApplicationStandard()) {
            firebaseModules
            bluetoothModules
            healthKit
            TemplateApplicationScheduler()
            Scheduler()
            Notifications()
            LLMRunner {
                LLMOpenAIPlatform(
                    configuration: .init(authToken: .none)
                )
            }
        }
    }
}


// MARK: - Grouped module blocks for lint friendliness
extension TemplateApplicationDelegate {
    /// All Firebase-related modules (AccountConfiguration, Firestore, Storage).
    /// Excluded if FeatureFlags.disableFirebase is true.
    @ModuleBuilder
    private var firebaseModules: some ModuleCollection {
        if !FeatureFlags.disableFirebase {
            AccountConfiguration(
                service: FirebaseAccountService(
                    // If you disabled Sign in with Apple, change to [.emailAndPassword]
                    providers: [.emailAndPassword, .signInWithApple],
                    emulatorSettings: accountEmulator
                ),
                storageProvider: FirestoreAccountStorage(storeIn: FirebaseConfiguration.userCollection),
                configuration: [
                    .requires(\.userId),
                    .requires(\.name),
                    // stored using FirestoreAccountStorage in TemplateApplicationStandard
                    .collects(\.genderIdentity),
                    .collects(\.dateOfBirth)
                ]
            )

            firestore

            if FeatureFlags.useFirebaseEmulator {
                FirebaseStorageConfiguration(
                    emulatorSettings: (host: "localhost", port: 9199)
                )
            } else {
                FirebaseStorageConfiguration()
            }
        }
    }

    /// All Bluetooth / device pairing / measurement modules (Omron, etc.).
    @ModuleBuilder
    private var bluetoothModules: some ModuleCollection {
        Bluetooth {
            // Discover Omron BP cuffs via the standard BloodPressureService.
            Discover(
                OmronBloodPressureCuff.self,
                by: .advertisedService(BloodPressureService.self)
            )

            // Optional: Omron weight scale support.
            // Discover(
            //     OmronWeightScale.self,
            //     by: .advertisedService(WeightScaleService.self)
            // )
        }

        // Manage pairing list ("Devices" tab uses this).
        PairedDevices()

        // Listen for new health measurements from paired devices
        // and surface them via HealthMeasurements.shouldPresentMeasurements
        // (which we observe in HomeView).
        HealthMeasurements()
    }
}


// MARK: - Helpers / submodules
extension TemplateApplicationDelegate {
    /// Firebase Auth emulator settings (if enabled)
    private var accountEmulator: (host: String, port: Int)? {
        if FeatureFlags.useFirebaseEmulator {
            (host: "localhost", port: 9099)
        } else {
            nil
        }
    }

    /// Firestore module with optional emulator settings
    private var firestore: Firestore {
        let settings = FirestoreSettings()
        if FeatureFlags.useFirebaseEmulator {
            settings.host = "localhost:8080"
            settings.cacheSettings = MemoryCacheSettings()
            settings.isSSLEnabled = false
        }

        return Firestore(
            settings: settings
        )
    }

    /// HealthKit module: what we read/collect from Apple Health.
    /// Keep this minimal so it's stable and you avoid permissions explosions.
    private var healthKit: HealthKit {
        HealthKit {
            // step count, heart rate are already working in your project
            CollectSample(.stepCount)
            CollectSample(.heartRate)

            // You can expand later (restingHeartRate, bloodPressure, etc.)
            // once you're happy with permissions and mappings.
        }
    }
}

