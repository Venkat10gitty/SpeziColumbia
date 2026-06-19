//
// HomeView.swift
// SpeziColumbia
//
// Main post-onboarding screen. Shows tabs for Schedule, Contacts, Devices.
// Also listens for new Omron blood pressure measurements and uploads them
// to Firestore in Observations_BloodPressure.
//

@_spi(TestingSupport) import SpeziAccount
import FirebaseAuth
import FirebaseFirestore
import HealthKit
import SpeziDevices
import SpeziDevicesUI
import SwiftUI


struct HomeView: View {
    enum Tabs: String {
        case schedule
        case contact
        case devices
        case assistant
        case settings
    }

    @AppStorage(StorageKeys.homeTabSelection) private var selectedTab = Tabs.schedule
    @AppStorage(StorageKeys.tabViewCustomization) private var tabViewCustomization = TabViewCustomization()

    @State private var presentingAccount = false

    // SpeziDevices / HealthMeasurements environment object.
    @Environment(HealthMeasurements.self) private var measurements

    var body: some View {
        @Bindable var measurements = measurements
        
        TabView(selection: $selectedTab) {
            // MARK: Schedule tab (existing)
            Tab("Schedule", systemImage: "list.clipboard", value: .schedule) {
                ScheduleView(presentingAccount: $presentingAccount)
            }
            .customizationID("home.schedule")

            // MARK: Contacts tab (existing)
            Tab("Contacts", systemImage: "person.fill", value: .contact) {
                Contacts(presentingAccount: $presentingAccount)
            }
            .customizationID("home.contacts")

            // MARK: Devices tab (NEW)
            Tab("Devices", systemImage: "sensor.fill", value: .devices) {
                DeviceTabView()
            }
            .customizationID("home.devices")
            
            // MARK: AI Assistant tab
            Tab("Assistant", systemImage: "brain.head.profile", value: .assistant) {
                NavigationStack { LLMAssistantView() }
            }
            .customizationID("home.assistant")

            // MARK: Settings tab (NEW)
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                NavigationStack { BackendSettingsView() }
            }
            .customizationID("home.settings")
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewCustomization($tabViewCustomization)

        // Sheet #1: account sheet (existing behavior)
        .sheet(isPresented: $presentingAccount) {
            // user tapped account UI → don't auto-dismiss
            AccountSheet(dismissAfterSignIn: false)
        }

        // Require sign-in if Firebase is enabled & onboarding wasn't skipped
        .accountRequired(!FeatureFlags.disableFirebase && !FeatureFlags.skipOnboarding) {
            AccountSheet()
        }

        // Sheet #2: new BP measurements from Omron
        // When an Omron cuff sends data, HealthMeasurements flips
        // shouldPresentMeasurements to true. This sheet surfaces that data;
        // we also push it to Firestore.
        .sheet(isPresented: $measurements.shouldPresentMeasurements) {
            MeasurementsRecordedSheet { samples in
                handleSamples(samples)
            }
        }
    }
}


/// A small struct holding parsed BP data before it's serialized for Firestore.
struct BPMeasurementData {
    let docId: String
    let startDate: Date
    let endDate: Date
    let systolic: Double?
    let diastolic: Double?
    let pulse: Double?
}


// MARK: - Measurement handling / Firestore upload
extension HomeView {
    /// Called from MeasurementsRecordedSheet whenever we get new samples.
    func handleSamples(_ samples: [HKSample]) {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("No Firebase user; can't upload.")
            return
        }

        for sample in samples {
            uploadBloodPressureSample(sample, forUser: uid)
        }
    }

    /// Top-level wrapper: parse a BP correlation, build payload, upload it.
    func uploadBloodPressureSample(_ sample: HKSample, forUser uid: String) {
        guard let bpData = extractBloodPressureData(from: sample) else {
            // Not a BP correlation or couldn't parse fields.
            return
        }

        let payload = buildBloodPressurePayload(from: bpData)
        saveBloodPressurePayload(payload,
                                 docId: bpData.docId,
                                 forUser: uid)
    }

    /// Pull systolic / diastolic / pulse + timestamps out of an HKCorrelation.
    /// Returns nil if the sample isn't a BP correlation.
    func extractBloodPressureData(from sample: HKSample) -> BPMeasurementData? {
        // Ensure this is a blood pressure correlation.
        guard
            let correlation = sample as? HKCorrelation,
            correlation.correlationType == HKObjectType.correlationType(forIdentifier: .bloodPressure)
        else {
            return nil
        }

        // Safely build the HKQuantityTypes we care about.
        guard
            let systolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic),
            let diastolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic),
            let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)
        else {
            print("Couldn't build HKQuantityTypes for BP.")
            return nil
        }

        let mmHg = HKUnit.millimeterOfMercury()
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())

        let systolic = correlation
            .objects(for: systolicType)
            .compactMap { $0 as? HKQuantitySample }
            .first?
            .quantity
            .doubleValue(for: mmHg)

        let diastolic = correlation
            .objects(for: diastolicType)
            .compactMap { $0 as? HKQuantitySample }
            .first?
            .quantity
            .doubleValue(for: mmHg)

        let pulse = correlation
            .objects(for: heartRateType)
            .compactMap { $0 as? HKQuantitySample }
            .first?
            .quantity
            .doubleValue(for: bpmUnit)

        let docId = correlation.uuid.uuidString

        return BPMeasurementData(
            docId: docId,
            startDate: correlation.startDate,
            endDate: correlation.endDate,
            systolic: systolic,
            diastolic: diastolic,
            pulse: pulse
        )
    }

    // MARK: Build Firestore payload pieces

    /// Helper for systolic component (optional).
    func bpComponentForSystolic(_ value: Double?) -> [String: Any]? {
        guard let value else {
            return nil
        }

        return [
            "code": ["coding": [[
                "system": "http://loinc.org",
                "code": "8480-6",
                "display": "Systolic blood pressure"
            ]]],
            "valueQuantity": [
                "value": value,
                "system": "http://unitsofmeasure.org",
                "unit": "mmHg"
            ]
        ]
    }

    /// Helper for diastolic component (optional).
    func bpComponentForDiastolic(_ value: Double?) -> [String: Any]? {
        guard let value else {
            return nil
        }

        return [
            "code": ["coding": [[
                "system": "http://loinc.org",
                "code": "8462-4",
                "display": "Diastolic blood pressure"
            ]]],
            "valueQuantity": [
                "value": value,
                "system": "http://unitsofmeasure.org",
                "unit": "mmHg"
            ]
        ]
    }

    /// Helper for pulse / heart rate component (optional).
    func bpComponentForPulse(_ value: Double?) -> [String: Any]? {
        guard let value else {
            return nil
        }

        return [
            "code": ["coding": [[
                "system": "http://loinc.org",
                "code": "8867-4",
                "display": "Heart rate"
            ]]],
            "valueQuantity": [
                "value": value,
                "system": "http://unitsofmeasure.org",
                "unit": "count/min"
            ]
        ]
    }

    /// Assemble the final Firestore payload (clean + short).
    func buildBloodPressurePayload(from data: BPMeasurementData) -> [String: Any] {
        var componentArray: [[String: Any]] = []

        if let systolicComp = bpComponentForSystolic(data.systolic) {
            componentArray.append(systolicComp)
        }
        if let diastolicComp = bpComponentForDiastolic(data.diastolic) {
            componentArray.append(diastolicComp)
        }
        if let pulseComp = bpComponentForPulse(data.pulse) {
            componentArray.append(pulseComp)
        }

        return [
            "code": ["coding": [[
                "system": "http://loinc.org",
                "code": "85354-9",
                "display": "Blood pressure panel with all children"
            ]]],
            "effectivePeriod": [
                "start": data.startDate,
                "end": data.endDate,
                "id": data.docId
            ],
            "component": componentArray,
            "identifier": [["id": data.docId]],
            "source": "omron-direct",
            "device": "OmronBloodPressureCuff"
        ]
    }

    /// Actually writes the dictionary to Firestore.
//    func saveBloodPressurePayload(_ payload: [String: Any],
//                                  docId: String,
//                                  forUser uid: String) {
//        let ref = Firestore.firestore()
//            .collection("users")
//            .document(uid)
//            .collection("Observations_BloodPressure")
//            .document(docId)
//
//        ref.setData(payload) { error in
//            if let error {
//                print("❌ BP upload error:", error)
//            } else {
//                print("✅ BP uploaded to Firestore")
//            }
//        }
//    }
    // NEW: route to Firebase or S3 depending on toggle
    func saveBloodPressurePayload(_ payload: [String: Any], docId: String, forUser uid: String) {
        BackendRouter.uploadObservation(
            uid: uid,
            collection: "Observations_BloodPressure",
            docId: docId,
            payload: payload
        ) { result in
            switch result {
            case .success:
                print("Blood pressure uploaded via \(BackendPrefs.get().displayName)")
            case .failure(let error):
                print("Upload error (\(BackendPrefs.get().displayName)): \(error)")
            }
        }
    }
}


// MARK: - Preview
#if DEBUG
#Preview {
    var details = AccountDetails()
    details.userId = "lelandstanford@stanford.edu"
    details.name = PersonNameComponents(
        givenName: "Leland",
        familyName: "Stanford"
    )

    return HomeView()
        .previewWith(standard: TemplateApplicationStandard()) {
            TemplateApplicationScheduler()
            AccountConfiguration(
                service: InMemoryAccountService(),
                activeDetails: details
            )
        }
}
#endif
