//
// This source file is part of the Stanford Spezi Template Application open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

//
// S3Uploader.swift
// SpeziColumbia
//
// SPDX-FileCopyrightText: 2025 Stanford University
// SPDX-License-Identifier: MIT
//

import Foundation

/// Minimal client that POSTs a JSON payload to your API Gateway → Lambda → S3 pipeline.
struct S3Uploader {
    /// API Gateway endpoint provided by your team.
    /// Example: https://36u86irxi2.execute-api.us-east-1.amazonaws.com/default/SpezitoS3
    static let apiURL = URL(string: "https://36u86irxi2.execute-api.us-east-1.amazonaws.com/default/SpezitoS3")!

    // MARK: - JSON value wrapper (recursive, Encodable)

    /// Type that can encode arbitrary JSON values recursively.
    enum JSONValue: Encodable {
        case string(String)
        case int(Int)
        case double(Double)
        case bool(Bool)
        case object([String: JSONValue])
        case array([JSONValue])
        case null

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let string): try container.encode(string)
            case .int(let int): try container.encode(int)
            case .double(let double): try container.encode(double)
            case .bool(let bool): try container.encode(bool)
            case .object(let object): try container.encode(object)
            case .array(let array): try container.encode(array)
            case .null: try container.encodeNil()
            }
        }

        /// Convert common Swift types to `JSONValue`. Dates are encoded as ISO-8601 strings.
        static func from(_ any: Any) -> JSONValue {
            switch any {
            case let date as Date:
                return .string(ISO8601DateFormatter().string(from: date))

            case let string as String: return .string(string)
            case let bool as Bool: return .bool(bool)

            case let int as Int: return .int(int)
            case let int8 as Int8: return .int(Int(int8))
            case let int16 as Int16: return .int(Int(int16))
            case let int32 as Int32: return .int(Int(int32))
            case let int64 as Int64:
                // Avoid overflow on 32-bit (fallback to double if necessary)
                if int64 > Int64(Int.max) { return .double(Double(int64)) }
                return .int(Int(int64))
            case let uint as UInt: return .int(Int(uint))

            case let double as Double: return .double(double)
            case let float as Float: return .double(Double(float))

            case let dict as [String: Any]:
                var encoded: [String: JSONValue] = [:]
                for (key, value) in dict {
                    encoded[key] = JSONValue.from(value)
                }
                return .object(encoded)

            case let array as [Any]:
                return .array(array.map { JSONValue.from($0) })

            default:
                // Fallback: store a string description
                return .string(String(describing: any))
            }
        }
    }

    // MARK: - Payload

    struct Payload: Encodable {
        let uid: String
        let path: String
        let data: JSONValue

        init(uid: String, path: String, data: [String: Any]) {
            self.uid = uid
            self.path = path
            self.data = .object(data.mapValues { JSONValue.from($0) })
        }
    }

    // MARK: - Public API

    /// POST `{ uid, path, data }` to the API Gateway endpoint.
    static func postJSON(
        uid: String,
        path: String,
        data: [String: Any],
        extraHeaders: [String: String] = [:],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let payload = Payload(uid: uid, path: path, data: data)

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (headerField, headerValue) in extraHeaders {
            request.setValue(headerValue, forHTTPHeaderField: headerField)
        }

        do {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(payload)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "S3Uploader", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "No HTTPURLResponse"
                ])))
                return
            }
            guard (200...299).contains(http.statusCode) else {
                completion(.failure(NSError(domain: "S3Uploader", code: http.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: "Non-2xx response: \(http.statusCode)"
                ])))
                return
            }
            completion(.success(()))
        }.resume()
    }
}
