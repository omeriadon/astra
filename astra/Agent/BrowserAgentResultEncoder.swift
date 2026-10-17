#if os(macOS) && !ASTRA_WEBSITE_APP_HELPER
	import Foundation
	import MCP

	/// Browser DTOs cross to this actor before text serialization and output budgeting.
	actor BrowserAgentResultEncoder {
		static let shared = BrowserAgentResultEncoder()
		func decode(_ json: String) throws -> CallTool.Result {
			try Task.checkCancellation()
			guard json.utf8.count <= 1_048_576 else {
				return .init(content: [.text(text: "OUTPUT_LIMIT: Request a smaller page or collection.", annotations: nil, _meta: nil)],
				             structuredContent: .object(["code": .string("OUTPUT_LIMIT")]), isError: true)
			}
			let value = try JSONDecoder().decode(Value.self, from: Data(json.utf8))
			try Task.checkCancellation()
			return try .init(content: [.text(text: json, annotations: nil, _meta: nil)], structuredContent: value)
		}

		func encode(_ value: Value) throws -> CallTool.Result {
			try Task.checkCancellation()
			let data = try JSONEncoder().encode(value)
			guard data.count <= 1_048_576 else {
				return .init(content: [.text(text: "OUTPUT_LIMIT: Request a smaller page or collection.", annotations: nil, _meta: nil)],
				             structuredContent: .object(["code": .string("OUTPUT_LIMIT")]), isError: true)
			}
			return try .init(content: [.text(text: String(decoding: data, as: UTF8.self), annotations: nil, _meta: nil)], structuredContent: value)
		}
	}
#endif
