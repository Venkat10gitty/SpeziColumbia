# SpeziColumbia — Project Documentation

**Course Project | Columbia University**
**Platform:** iOS 18+ (Swift / SwiftUI)
**Framework:** Stanford Spezi

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture Overview](#2-architecture-overview)
3. [Module Breakdown](#3-module-breakdown)
4. [Feature Deep-Dives](#4-feature-deep-dives)
   - 4.1 Onboarding Flow
   - 4.2 Schedule & Questionnaires
   - 4.3 Bluetooth Device Integration (Omron)
   - 4.4 AI Health Assistant (GPT-4o)
   - 4.5 Dual Backend System (Firebase / Amazon S3)
5. [Data Model & FHIR Compliance](#5-data-model--fhir-compliance)
6. [Backend Architecture](#6-backend-architecture)
7. [HealthKit Integration](#7-healthkit-integration)
8. [Firebase Integration](#8-firebase-integration)
9. [File & Directory Reference](#9-file--directory-reference)
10. [Setup & Configuration](#10-setup--configuration)
11. [Testing](#11-testing)
12. [Key Dependencies](#12-key-dependencies)

---

## 1. Project Overview

**SpeziColumbia** is a digital health research iOS application built on the [Stanford Spezi](https://github.com/StanfordSpezi/Spezi) open-source framework. The application demonstrates an end-to-end pipeline for:

- Collecting physiological data from consumer Bluetooth medical devices (Omron blood pressure cuffs)
- Storing that data in cloud backends (Google Firebase Firestore **or** Amazon S3) in a structured, FHIR-compatible format
- Scheduling and delivering health questionnaires to research participants
- Providing an AI-powered health assistant interface backed by OpenAI GPT-4o

The project extends the [Stanford Spezi Template Application](https://github.com/StanfordSpezi/SpeziTemplateApplication), which provides a production-quality scaffolding for iOS digital health studies. Our additions introduce Bluetooth device pairing, a flexible dual-backend upload system, an S3 path convention for organized data storage, and an in-app LLM chat assistant.

### Goals

| Goal | Status |
|------|--------|
| Firebase Firestore data pipeline | Complete |
| Omron BLE blood pressure cuff pairing & upload | Complete |
| Amazon S3 upload via API Gateway → Lambda | Complete |
| Runtime toggle between Firebase and S3 | Complete |
| FHIR-like data structure with LOINC codes | Complete |
| GPT-4o AI health assistant | Complete |
| Health questionnaire scheduling | Complete (from template) |

---

## 2. Architecture Overview

The application is organized around the **Spezi Module** pattern — each capability is encapsulated as a self-contained module that declares its dependencies and is composed in the `SpeziAppDelegate`.

```
SpeziColumbia
├── TemplateApplicationDelegate    ← Spezi DI container / module composer
├── TemplateApplicationStandard   ← Central data handler (HealthKit → Firestore)
│
├── Onboarding/                   ← Multi-step onboarding flow
├── HomeView                      ← Tab container (Schedule | Contacts | Devices | Assistant | Settings)
│
├── Schedule/                     ← SpeziScheduler integration
│
├── Backend/                      ← Dual backend routing layer (NEW)
│   ├── BackendRouter             ← Central upload switch (Firebase vs S3)
│   ├── BackendPrefs              ← UserDefaults persistence of backend selection
│   ├── S3Uploader                ← HTTP client → API Gateway → Lambda → S3
│   └── BackendSettingsView       ← In-app picker to switch backend at runtime
│
├── Upload/                       ← S3 path conventions (NEW)
│   └── S3PathBuilder             ← Maps HK type names → S3 bucket paths
│
├── LLM/                          ← AI assistant (NEW)
│   └── LLMAssistantView          ← SpeziLLM + OpenAI GPT-4o chat UI
│
└── DeviceTabView                 ← Omron BLE device management (NEW)
```

### Dependency Flow

```
SpeziAppDelegate
    └── Configuration
            ├── Firebase modules (Auth, Firestore, Storage)
            ├── Bluetooth modules (SpeziBluetooth, OmronBloodPressureCuff, HealthMeasurements)
            ├── HealthKit module (CollectSample: stepCount, heartRate)
            ├── TemplateApplicationScheduler (questionnaire scheduling)
            ├── Scheduler + Notifications (local push reminders)
            └── LLMRunner + LLMOpenAIPlatform (GPT-4o backend)
```

---

## 3. Module Breakdown

### 3.1 TemplateApplicationDelegate (`TemplateApplicationDelegate.swift`)

The root Spezi delegate that wires together all modules. Broken into three logical groups:

**Firebase Modules** (guarded by `FeatureFlags.disableFirebase`):
- `AccountConfiguration` — Firebase Auth with email/password and Sign in with Apple; account details stored in Firestore via `FirestoreAccountStorage`
- `Firestore` — Firestore SDK with optional emulator redirect
- `FirebaseStorageConfiguration` — Firebase Storage for file uploads

**Bluetooth Modules**:
- `Bluetooth` — BLE stack configured to discover `OmronBloodPressureCuff` devices by their `BloodPressureService` advertisement UUID
- `PairedDevices` — Manages the persisted list of paired Omron devices
- `HealthMeasurements` — Surfaces new BP readings from the cuff; sets `shouldPresentMeasurements = true` to trigger the upload sheet in `HomeView`

**Other Modules**:
- `TemplateApplicationScheduler` + `Scheduler` — Task scheduling engine
- `Notifications` — Local notification delivery for scheduled tasks
- `LLMRunner` + `LLMOpenAIPlatform` — OpenAI integration; token is supplied per-request from `UserDefaults` so no key is baked into the binary

### 3.2 TemplateApplicationStandard (`TemplateApplicationStandard.swift`)

Implements Spezi's `Standard` protocol. Acts as the central data handler:

- `handleNewSamples(_:ofType:)` — Called by the HealthKit module when new step count or heart rate samples arrive; writes them to Firestore under `users/{uid}/Observations_{SampleType}/{uuid}`
- `handleDeletedObjects(_:ofType:)` — Removes Firestore documents when HK samples are deleted
- `add(response:for:)` — Persists `QuestionnaireResponse` FHIR resources to Firestore under `QuestionnaireResponses_{questionnaireId}/{responseId}`
- `respondToEvent(_:)` — Handles account deletion by removing the user's Firestore document

---

## 4. Feature Deep-Dives

### 4.1 Onboarding Flow (`Onboarding/`)

A multi-step, managed navigation flow built on `SpeziOnboarding`. Steps are conditionally included based on the app's state:

| Step | File | Condition |
|------|------|-----------|
| Welcome | `Welcome.swift` | Always shown |
| Interesting Modules | `InterestingModules.swift` | Always shown |
| Account Sign-Up / Login | `AccountOnboarding.swift` | `!FeatureFlags.disableFirebase` |
| Consent Form | `Consent.swift` | Not on x86 simulator |
| HealthKit Permissions | `HealthKitPermissions.swift` | HealthKit available & not yet authorized |
| Notification Permissions | `NotificationPermissions.swift` | Not yet authorized |

Completion is stored in `UserDefaults` under `StorageKeys.onboardingFlowComplete`. Once set, the app routes to `HomeView` and does not show onboarding again.

The consent document is loaded from `ConsentDocument.md` in the app bundle, rendered as a scrollable text view, and accepted via an "I Agree" button.

### 4.2 Schedule & Questionnaires (`Schedule/`)

Uses `SpeziScheduler` and `SpeziSchedulerUI` to deliver time-triggered health questionnaires.

- `TemplateApplicationScheduler` — defines the schedule (questionnaire frequency, content)
- `ScheduleView` — shows upcoming and completed tasks via `EventScheduleList`
- `EventView` — presents the active questionnaire using ResearchKit/FHIR questionnaire JSON
- `Bundle+Questionnaire.swift` — helper to load `.json` questionnaire definitions from the bundle (e.g. `SocialSupportQuestionnaire.json`)

Completed responses are sent to `TemplateApplicationStandard.add(response:for:)` which persists them to Firestore.

### 4.3 Bluetooth Device Integration

#### DeviceTabView (`DeviceTabView.swift`)

A simple navigation wrapper around `SpeziDevicesUI`'s `DevicesView`. Users can:
- See their currently paired Omron devices
- Put a device in pairing mode and tap `+` to add it
- Remove paired devices

#### Blood Pressure Upload (`HomeView.swift`)

When an Omron cuff delivers a reading:

1. `HealthMeasurements.shouldPresentMeasurements` flips to `true`
2. `HomeView` presents `MeasurementsRecordedSheet` (from `SpeziDevicesUI`)
3. On confirmation, `handleSamples(_:)` is called with an array of `HKSample`
4. Each sample passes through `uploadBloodPressureSample(_:forUser:)`:
   - `extractBloodPressureData(from:)` — casts the sample to `HKCorrelation`, extracts systolic (LOINC 8480-6), diastolic (LOINC 8462-4), and pulse (LOINC 8867-4) as `Double` values in mmHg and count/min
   - `buildBloodPressurePayload(from:)` — assembles a FHIR-like dictionary with LOINC panel code 85354-9, an `effectivePeriod`, and a `component` array
   - `saveBloodPressurePayload(_:docId:forUser:)` — routes to `BackendRouter.uploadObservation`

### 4.4 AI Health Assistant (`LLM/LLMAssistantView.swift`)

An in-app chat interface backed by OpenAI GPT-4o, integrated via `SpeziLLM` and `SpeziLLMOpenAI`.

**Key design decisions:**
- The OpenAI API key is **never baked into the binary**. The user enters it in-app; it is stored in `UserDefaults` and passed at request time via `.closure { UserDefaults.standard.string(forKey: "openai.apiKey") }`
- The key is stored locally on device and only transmitted to OpenAI
- If no key is set, `LLMAssistantView` shows `APIKeySetupView` instead of the chat

**System prompt:**
> You are a helpful digital health assistant integrated into the Stanford Spezi research platform. You help users understand their health data, answer general health questions, and provide guidance on using the app. Always remind users to consult a healthcare professional for medical advice.

The chat model is `GPT-4o` (`LLMOpenAIModelType.gpt4o`).

### 4.5 Dual Backend System (`Backend/`)

The most significant architectural addition. Allows data to be routed to either Firebase Firestore or Amazon S3 at runtime without code changes.

#### Components

**`BackendTarget`** (enum):
```
case firebase   → "Firebase"
case s3         → "Amazon S3"
```

**`BackendPrefs`** (struct):
- Persists the user's selection in `UserDefaults` under key `"backend.target"`
- `get()` → reads and returns `BackendTarget`
- `set(_:)` → writes the new selection
- Defaults to `.firebase` if no value is stored

**`BackendRouter`** (enum):
- `uploadObservation(uid:collection:docId:payload:completion:)` — the single entry point for all observation uploads
- Reads `BackendPrefs.get()` and dispatches accordingly:
  - `.firebase` → `Firestore().collection("users").document(uid).collection(collection).document(docId).setData(payload)`
  - `.s3` → builds an S3 key via `s3Key(uid:collection:docId:)` then calls `S3Uploader.postJSON`

**`BackendSettingsView`** (view):
- A `Form` with a `Picker` showing all `BackendTarget` cases
- `onChange` persists the selection immediately via `BackendPrefs.set`
- Accessible from the Settings tab in `HomeView`

---

## 5. Data Model & FHIR Compliance

All health observations are stored using a FHIR-inspired structure with LOINC codes. This ensures interoperability with clinical systems.

### Blood Pressure Document Schema

```json
{
  "code": {
    "coding": [{
      "system": "http://loinc.org",
      "code": "85354-9",
      "display": "Blood pressure panel with all children"
    }]
  },
  "effectivePeriod": {
    "start": "<ISO-8601 date>",
    "end":   "<ISO-8601 date>",
    "id":    "<UUID from HKCorrelation>"
  },
  "component": [
    {
      "code": { "coding": [{ "system": "http://loinc.org", "code": "8480-6", "display": "Systolic blood pressure" }] },
      "valueQuantity": { "value": 122.0, "system": "http://unitsofmeasure.org", "unit": "mmHg" }
    },
    {
      "code": { "coding": [{ "system": "http://loinc.org", "code": "8462-4", "display": "Diastolic blood pressure" }] },
      "valueQuantity": { "value": 78.0, "system": "http://unitsofmeasure.org", "unit": "mmHg" }
    },
    {
      "code": { "coding": [{ "system": "http://loinc.org", "code": "8867-4", "display": "Heart rate" }] },
      "valueQuantity": { "value": 64.0, "system": "http://unitsofmeasure.org", "unit": "count/min" }
    }
  ],
  "identifier": [{ "id": "<UUID>" }],
  "source": "omron-direct",
  "device": "OmronBloodPressureCuff"
}
```

### Firestore Path

```
users/{uid}/Observations_BloodPressure/{correlationUUID}
```

### S3 Key Convention

```
_<uid>/HealthKit/<Category>/<Type>/<correlationUUID>.json
```

Example: `_abc123/HealthKit/Vital/bloodPressure/3F2504E0-4F89-11D3-9A0C-0305E82C3301.json`

---

## 6. Backend Architecture

### 6.1 S3 Upload Path (`Upload/S3PathBuilder.swift`)

`S3PathBuilder` maps every HealthKit type identifier to a structured S3 path. It supports all major HK categories:

| S3 Category | Example HK Types |
|-------------|-----------------|
| `Activity` | stepCount, distanceWalkingRunning, activeEnergyBurned, walkingSpeed |
| `Vital` | heartRate, restingHeartRate, oxygenSaturation, vo2Max, bloodPressure |
| `Body` | bodyMass, bodyMassIndex, height, bodyTemperature |
| `Blood` | bloodGlucose, bloodAlcoholContent |
| `Nutrition` | any type with "dietary" prefix |
| `Hearing` | environmentalAudioExposure, headphoneAudioExposure |
| `Sleep` | sleepAnalysis, mindfulSession |
| `CardioEvents` | highHeartRateEvent, irregularHeartRhythmEvent |
| `Workout` | HK Workout types |
| `Misc` | anything unrecognized |

The type is detected from either the FHIR `code.coding[*].code` field (e.g. `HKQuantityTypeIdentifierHeartRate` → `heartRate`) or from the Firestore collection name suffix (e.g. `Observations_BloodPressure` → `bloodPressure`).

### 6.2 S3Uploader (`Backend/S3Uploader.swift`)

A minimal HTTP client that POSTs JSON to an AWS API Gateway endpoint which proxies to a Lambda function that writes to S3.

**Endpoint:** `https://36u86irxi2.execute-api.us-east-1.amazonaws.com/default/SpezitoS3`

**Request payload:**
```json
{
  "uid": "<Firebase user ID>",
  "path": "_<uid>/HealthKit/Vital/bloodPressure/<docId>.json",
  "data": { ... FHIR observation ... }
}
```

The `JSONValue` enum handles recursive Encodable serialization of arbitrary `[String: Any]` dictionaries (including nested objects, arrays, dates as ISO-8601 strings, and all numeric Swift types).

---

## 7. HealthKit Integration

Configured in `TemplateApplicationDelegate`:

```swift
HealthKit {
    CollectSample(.stepCount)
    CollectSample(.heartRate)
}
```

**Background delivery** is handled by the Spezi HealthKit module. When new samples arrive, `TemplateApplicationStandard.handleNewSamples(_:ofType:)` is called, which:
- Converts the sample to a FHIR `Resource` via `HealthKitOnFHIR`
- Writes it to Firestore: `users/{uid}/Observations_{SampleType}/{uuid}`

**Blood pressure** is handled separately through the BLE path (Omron cuff → `HealthMeasurements` → `HomeView.handleSamples`) rather than background HealthKit delivery, because the Omron SDK delivers data as `HKCorrelation` objects directly through `MeasurementsRecordedSheet`.

### HealthKit Permissions Requested

| Type | Reason |
|------|--------|
| Step Count | Activity monitoring |
| Heart Rate | Cardiac health tracking |
| Blood Pressure (Systolic + Diastolic) | Via Omron device |
| Heart Rate (pulse) | Paired with BP readings |

---

## 8. Firebase Integration

### Authentication

Firebase Auth is configured with two providers:
- Email + password
- Sign in with Apple

Account details (name, email, gender identity, date of birth) are stored in Firestore via `FirestoreAccountStorage`, pointed at `FirebaseConfiguration.userCollection`.

### Firestore Collections (per user document)

```
users/{uid}/
├── Observations_StepCount/{uuid}         ← FHIR Observation (step count)
├── Observations_HeartRate/{uuid}          ← FHIR Observation (heart rate)
├── Observations_BloodPressure/{uuid}      ← FHIR BP panel (from Omron)
└── QuestionnaireResponses_{id}/{uuid}     ← FHIR QuestionnaireResponse
```

### Feature Flags

Controlled via launch arguments (useful for testing):

| Flag | Launch Arg | Effect |
|------|------------|--------|
| `disableFirebase` | `--disableFirebase` | Skip all Firebase init, log to console |
| `skipOnboarding` | `--skipOnboarding` | Jump directly to HomeView |
| `showOnboarding` | `--showOnboarding` | Always show onboarding |
| `useFirebaseEmulator` | `--useFirebaseEmulator` | Route to local Firebase emulators |
| `setupTestAccount` | `--setupTestAccount` | Auto sign in with a test account |

---

## 9. File & Directory Reference

```
SpeziColumbia/
│
├── TemplateApplication/
│   ├── TemplateApplication.swift              App entry point (@main)
│   ├── TemplateApplicationDelegate.swift      Spezi module configuration
│   ├── TemplateApplicationStandard.swift      Central data handler (Standard)
│   ├── TemplateApplicationTestingSetup.swift  Test helpers
│   │
│   ├── HomeView.swift                         Tab bar container + BP upload logic
│   ├── DeviceTabView.swift                    Omron BLE device management tab
│   │
│   ├── Backend/
│   │   ├── Backend.swift                      (archived / commented out)
│   │   ├── BackendRouter.swift                Central upload dispatcher
│   │   ├── BackendSettingsView.swift          Settings UI (Firebase vs S3 picker)
│   │   └── S3Uploader.swift                   HTTP client → API Gateway → S3
│   │
│   ├── Upload/
│   │   └── S3PathBuilder.swift                HK type → S3 path mapper
│   │
│   ├── LLM/
│   │   └── LLMAssistantView.swift             GPT-4o AI chat assistant
│   │
│   ├── Onboarding/
│   │   ├── OnboardingFlow.swift               Multi-step onboarding coordinator
│   │   ├── Welcome.swift                      Welcome screen
│   │   ├── InterestingModules.swift           Features overview screen
│   │   ├── AccountOnboarding.swift            Firebase sign-up/login
│   │   ├── Consent.swift                      Consent form (from .md file)
│   │   ├── HealthKitPermissions.swift         HealthKit permission request
│   │   └── NotificationPermissions.swift      Notification permission request
│   │
│   ├── Schedule/
│   │   ├── TemplateApplicationScheduler.swift Task/questionnaire scheduler
│   │   ├── ScheduleView.swift                 Schedule list UI
│   │   ├── EventView.swift                    Active task / questionnaire UI
│   │   └── Bundle+Questionnaire.swift         JSON questionnaire loader
│   │
│   ├── Firestore/
│   │   └── FirebaseConfiguration.swift        Firestore collection path helpers
│   │
│   ├── SharedContext/
│   │   ├── FeatureFlags.swift                 Launch argument feature flags
│   │   └── StorageKeys.swift                  UserDefaults / AppStorage key constants
│   │
│   └── Resources/
│       ├── SocialSupportQuestionnaire.json    FHIR Questionnaire resource
│       └── Localizable.xcstrings             Localization strings
│
├── Sources/Spezi/                             Local Spezi framework source
├── TemplateApplicationTests/                  Unit tests
├── TemplateApplicationUITests/                UI/integration tests
│   ├── OnboardingTests.swift
│   ├── SchedulerTests.swift
│   ├── ContactsTests.swift
│   └── ContributionsTest.swift
│
├── firebase/                                  Firebase project config & security rules
│   ├── firestore.rules
│   └── firebasestorage.rules
│
└── fastlane/                                  CI/CD automation
```

---

## 10. Setup & Configuration

### Prerequisites

- macOS 14+, Xcode 16+
- iOS 18 deployment target
- Firebase project with Authentication and Firestore enabled
- (Optional) AWS account with API Gateway + Lambda + S3 configured

### Step 1: Firebase

1. Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com)
2. Add an iOS app (Bundle ID: `edu.columbia.SpeziColumbia` or as configured)
3. Download `GoogleService-Info.plist` and place it in `TemplateApplication/Supporting Files/`
4. Enable **Email/Password** and **Sign in with Apple** in Firebase Auth
5. Create Firestore database in the same project

### Step 2: Xcode

1. Open `TemplateApplication.xcodeproj`
2. Set your development team in signing settings
3. Build and run on a device or simulator (`iPhone 16` target recommended)

### Step 3: (Optional) S3 Backend

The S3 upload endpoint is pre-configured in `S3Uploader.swift`:
```
https://36u86irxi2.execute-api.us-east-1.amazonaws.com/default/SpezitoS3
```

This points to a Lambda function that writes `{ uid, path, data }` payloads to an S3 bucket. To use a different endpoint, change `S3Uploader.apiURL`.

To switch to S3 at runtime: open the app → Settings tab → "Upload to: Amazon S3".

### Step 4: AI Assistant

In the app, navigate to the **Assistant** tab. On first use, you will be prompted to enter an OpenAI API key (`sk-...`). The key is stored in `UserDefaults` on-device only.

### Step 5: Omron Blood Pressure Cuff

1. Navigate to the **Devices** tab
2. Put your Omron device into BLE pairing mode
3. Tap `+` and follow the on-screen instructions
4. After pairing, take a blood pressure reading — the app will detect it automatically and prompt you to record and upload it

---

## 11. Testing

### Unit Tests (`TemplateApplicationTests/`)

Basic smoke tests for app initialization and standard configuration.

### UI Tests (`TemplateApplicationUITests/`)

| Test File | Coverage |
|-----------|----------|
| `OnboardingTests.swift` | Full onboarding flow (with `--skipOnboarding` flag) |
| `SchedulerTests.swift` | Schedule view and questionnaire presentation |
| `ContactsTests.swift` | Contacts tab rendering |
| `ContributionsTest.swift` | Open-source contributions / license view |

Tests use `--disableFirebase` and `--skipOnboarding` launch arguments to run without a live Firebase connection.

---

## 12. Key Dependencies

All dependencies are managed via Swift Package Manager and declared in `Package.resolved`.

| Package | Purpose |
|---------|---------|
| `StanfordSpezi/Spezi` | Core module/DI framework |
| `StanfordSpezi/SpeziAccount` | Account management UI and protocol |
| `StanfordSpezi/SpeziFirebase` | Firebase Auth, Firestore, Storage modules |
| `StanfordSpezi/SpeziHealthKit` | HealthKit background delivery + HealthKitOnFHIR |
| `StanfordSpezi/SpeziScheduler` | Task & questionnaire scheduling engine |
| `StanfordSpezi/SpeziOnboarding` | Managed navigation onboarding flow |
| `StanfordSpezi/SpeziNotifications` | Local notification management |
| `StanfordSpezi/SpeziDevices` | Paired device management |
| `StanfordSpezi/SpeziDevicesUI` | Device pairing/management UI |
| `StanfordSpezi/SpeziBluetooth` | BLE stack |
| `StanfordSpezi/SpeziBluetoothServices` | Standard BLE service profiles (GATT) |
| `StanfordSpezi/SpeziOmron` | Omron blood pressure cuff protocol |
| `StanfordSpezi/SpeziLLM` | LLM runner module |
| `StanfordSpezi/SpeziLLMOpenAI` | OpenAI GPT integration |
| `StanfordSpezi/SpeziQuestionnaire` | FHIR questionnaire rendering |
| `StanfordSpezi/SpeziViews` | Shared UI components |
| `firebase/firebase-ios-sdk` | Firebase iOS SDK (Auth, Firestore, Storage) |
| `apple/HealthKitOnFHIR` | HK sample → FHIR resource conversion |

---

## Appendix: Data Flow Diagram

```
User takes BP reading with Omron cuff
        │
        ▼
SpeziBluetooth / SpeziOmron (BLE GATT)
        │  raw BloodPressure characteristic data
        ▼
HealthMeasurements (Spezi module)
        │  shouldPresentMeasurements = true
        ▼
HomeView → MeasurementsRecordedSheet
        │  [HKSample] (HKCorrelation)
        ▼
extractBloodPressureData(from:)
        │  systolic / diastolic / pulse + timestamps
        ▼
buildBloodPressurePayload(from:)
        │  FHIR-like dict with LOINC codes
        ▼
BackendRouter.uploadObservation(...)
        │
        ├─── BackendPrefs == .firebase ──▶ Firestore.setData(payload)
        │                                    users/{uid}/Observations_BloodPressure/{uuid}
        │
        └─── BackendPrefs == .s3 ────────▶ S3PathBuilder.key(...)
                                             │  _<uid>/HealthKit/Vital/bloodPressure/<uuid>.json
                                             ▼
                                           S3Uploader.postJSON(uid:path:data:)
                                             │  POST { uid, path, data } as JSON
                                             ▼
                                           AWS API Gateway
                                             │
                                             ▼
                                           Lambda (SpezitoS3)
                                             │
                                             ▼
                                           S3 Bucket
```
