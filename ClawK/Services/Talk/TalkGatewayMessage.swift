//
//  TalkGatewayMessage.swift
//  ClawK
//
//  WebSocket protocol message types for Talk Mode gateway communication
//

import Foundation

// MARK: - Outgoing: Generic request envelope

struct TalkGatewayRequest: Encodable, Sendable {
    let type = "req"
    let id: String
    let method: String
    let params: [String: TalkAnyCodable]

    init(method: String, params: [String: TalkAnyCodable] = [:]) {
        self.id = UUID().uuidString.lowercased()
        self.method = method
        self.params = params
    }
}

// MARK: - AnyCodable helper

struct TalkAnyCodable: Encodable, @unchecked Sendable {
    let value: Any

    init(_ value: Any) { self.value = value }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as String: try container.encode(v)
        case let v as Int: try container.encode(v)
        case let v as Double: try container.encode(v)
        case let v as Bool: try container.encode(v)
        case let v as [String]: try container.encode(v)
        case let v as [String: TalkAnyCodable]: try container.encode(v)
        default: try container.encodeNil()
        }
    }
}

// MARK: - Incoming: typed Codable structs

struct TalkGatewayIncoming: Decodable, Sendable {
    let type: String
    let id: String?
    let event: String?
    let ok: Bool?
    let payload: TalkGatewayPayload?
    let error: TalkGatewayErrorInfo?
}

struct TalkGatewayPayload: Decodable, Sendable {
    let nonce: String?
    let snapshot: TalkAnyCodableValue?
    let state: String?
    let message: TalkGatewayMessageContent?
    let errorMessage: String?
}

struct TalkGatewayMessageContent: Decodable, Sendable {
    let content: TalkMessageContent?
    let text: String?
}

enum TalkMessageContent: Decodable, Sendable {
    case blocks([TalkContentBlock])
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let blocks = try? container.decode([TalkContentBlock].self) {
            self = .blocks(blocks)
        } else if let str = try? container.decode(String.self) {
            self = .string(str)
        } else {
            throw DecodingError.typeMismatch(
                TalkMessageContent.self,
                .init(codingPath: decoder.codingPath,
                      debugDescription: "Expected array of content blocks or string"))
        }
    }

    var textValue: String? {
        switch self {
        case .blocks(let blocks):
            let texts = blocks.compactMap { $0.type == "text" ? $0.text : nil }
            return texts.isEmpty ? nil : texts.joined(separator: "\n")
        case .string(let str):
            return str
        }
    }
}

struct TalkContentBlock: Decodable, Sendable {
    let type: String
    let text: String?
}

struct TalkGatewayErrorInfo: Decodable, Sendable {
    let message: String?
}

enum TalkAnyCodableValue: Decodable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: TalkAnyCodableValue])
    case array([TalkAnyCodableValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode(Double.self) { self = .double(v) }
        else if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode([String: TalkAnyCodableValue].self) { self = .object(v) }
        else if let v = try? container.decode([TalkAnyCodableValue].self) { self = .array(v) }
        else if container.decodeNil() { self = .null }
        else { self = .null }
    }
}
