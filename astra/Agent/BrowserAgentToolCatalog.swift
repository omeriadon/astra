#if os(macOS) && !ASTRA_WEBSITE_APP_HELPER
import MCP

/// Immutable descriptors are built once, outside the UI actor.
nonisolated enum BrowserAgentToolCatalog {
    static let pageActions: Set<String> = [
        "click", "double_click", "right_click", "hover", "move_pointer", "drag", "drag_and_drop",
        "scroll", "scroll_element", "scroll_into_view", "fill", "select_option", "set_checked",
        "select_radio", "clear_field", "submit_form", "press_key", "type_text", "key_down", "key_up",
        "focus_element", "blur_element", "find_elements", "inspect_element", "get_element_attributes",
        "get_element_geometry", "get_element_text", "get_element_state", "get_selected_text", "get_dom_fragment"
    ]
    static let waits: Set<String> = ["wait", "wait_for_element", "wait_for_text", "wait_for_url", "wait_for_navigation", "wait_for_load_state"]
    static let tools: ListTools.Result = {
        let string: Value = .object(["type": .string("string")])
        let number: Value = .object(["type": .string("number")])
        let boolean: Value = .object(["type": .string("boolean")])
        var output: [Tool] = []
        func add(_ name: String, _ description: String, _ extra: [String: Value] = [:], _ required: [String] = [], tab: Bool = true, read: Bool = false) {
            var properties = extra
            if tab { properties["tabID"] = string }
            output.append(Tool(name: name, description: description, inputSchema: .object([
                "type": .string("object"), "properties": .object(properties),
                "required": .array((required + (tab ? ["tabID"] : [])).map { .string($0) }),
                "additionalProperties": .bool(false)
            ]), annotations: .init(readOnlyHint: read, destructiveHint: !read, openWorldHint: true)))
        }
        add("list_tabs", "List explicitly granted tabs, excluding private and Mini windows.", tab: false, read: true)
        add("open_tab", "Create and share an HTTP(S) tab in the selected nonprivate window.", ["url": string, "windowID": string], ["url"], tab: false)
        add("navigate", "Start navigation. navigationStarted does not mean the destination finished loading.", ["url": string], ["url"])
        add("read_page", "Read bounded rendered text, excluding form values.", read: true)
        add("snapshot", "Create semantic refs across same-origin frames and open shadow roots; report inaccessible frames.", ["mode": string, "offset": number, "limit": number, "includeHidden": boolean], read: true)
        let common: [String: Value] = ["ref": string, "selector": string, "role": string, "name": string, "text": string,
            "value": string, "values": .object(["type": .string("array"), "items": string]), "checked": boolean,
            "dx": number, "dy": number, "x": number, "y": number, "targetRef": string, "inputMode": string, "maxLength": number, "block": string, "inline": string,
            "key": string, "modifiers": .object(["type": .string("array"), "items": string]), "limit": number, "offset": number]
        let reads: Set<String> = ["find_elements", "inspect_element", "get_element_attributes", "get_element_geometry", "get_element_text", "get_element_state", "get_selected_text", "get_dom_fragment"]
        for name in pageActions.sorted() {
            add(name, "\(name): target a granted page using a snapshot ref or an unambiguous selector. Input is synthetic and never claims trusted activation.", common, read: reads.contains(name))
        }
        for name in waits.sorted() {
            add(name, "Cancellation-aware readiness wait, bounded to 300 seconds. Timeout is seconds; success verifies the requested condition.", ["ref": string, "selector": string, "text": string, "url": string, "state": string, "timeout": number], read: true)
        }
        #if !ASTRA_BROWSER_USE_FIXTURE
        output += BrowserAgentNativeActions.tools
        output += BrowserAgentPageService.tools
        #else
        add("screenshot", "Capture viewport image.", read: true)
        #endif
        return .init(tools: output)
    }()
}
#endif
