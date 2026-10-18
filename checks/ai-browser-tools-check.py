#!/usr/bin/env python3
"""Source-contract checks for the AI browser action boundary.

Runs on hosts without AppKit/WebKit. Runtime UI tests remain necessary.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
tools = (root / "astra/AI/BrowserAITools.swift").read_text()
chat = (root / "astra/AI/BrowserAIChat.swift").read_text()
prompts = (root / "astra/AI/BrowserAIPrompts.swift").read_text()

def check(condition: bool, reason: str) -> None:
    if not condition:
        raise AssertionError(reason)

for action in ("list_tabs", "github_account", "move_tabs_to_space", "close_tab"):
    check(f'"{action}"' in tools, f"Missing action {action}")

check("browser.workspace.spaces" in tools and "spaceID=" in tools,
      "Space inventory must expose space identities")
check("offset + page.count < rows.count" in tools and "prefix(limit)" in tools,
      "Large account inventory must paginate")
check('url.host?.lowercased() == domain' in tools,
      "Domain filtering must compare exact hostnames")
check("found.count == 1" in tools and "githubAccount(in: browser" in tools,
      "GitHub owner discovery must detect conflicting account metadata")
check("components.count >= 2" in tools and "caseInsensitiveCompare(owner)" in tools,
      "GitHub owner exclusions must compare repository owner path components")
check("sameTab($0, in: browser)" in tools and "current.url == expected.url" in tools,
      "Bulk action must detect navigation between preview and apply")
check("current.sourceSpaceID == expected.sourceSpaceID" in tools,
      "Bulk action must detect membership changes")
check("current.pinned == expected.pinned" in tools and "current.favourite == expected.favourite" in tools,
      "Bulk action must detect changed pin/favourite state")
check("plan.windowID == browser.windowID" in tools
      and "plan.originatingSpaceID == browser.selectedSpace.id" in tools,
      "Bulk plans must be bound to the origin window and space")
check("now.timeIntervalSince(plan.createdAt) < 180" in tools
      and "bulkPlans.removeValue(forKey: token)" in tools,
      "Apply must reject expired and reused plan IDs")
check("try checkClosable(plan.tabs, in: browser)" in tools,
      "Close must check all protected tabs before first mutation")
check("hasUnsavedChanges || $0.requiresMediaTeardownConfirmation" in tools,
      "Bulk close must reject unsaved changes and protected media")
check("browser.tab(withID: item.id) == nil" in tools,
      "Bulk close must verify actual removal rather than claim success")
check("browser.moveTabs(pinned, to: .pinned, in: destination)" in tools
      and "browser.moveTabs(normal, to: .normal, in: destination)" in tools,
      "Cross-space bulk moves must preserve pinned state")
check(chat.index("let turn = try await BrowserAI.shared.performStreaming") < chat.index("for call in turn.actions") < chat.index("BrowserAITools.execute"),
      "Actions must execute only after complete output validation")
check("BrowserAIOutput.completedObjects(in: snapshot)" not in chat,
      "Partial streaming objects must never execute actions")
for action in ("list_tools", "get_page_structure", "augment_website"):
    check(f'"{action}"' in tools, f"Missing Website Augment action {action}")
check("augmentArtifacts: turnArtifacts" in chat and "toolCalls: toolCalls" in chat,
      "Augment artifacts and tool history must persist with chat")
check("Never guess an owner" in prompts and "planID" in prompts,
      "The model must not guess GitHub owners or bypass action previews")
check("self == .deleteBookmark || self == .closeTab" in tools,
      "The pre-existing destructive action default must remain disabled")
check('!browser.isPrivate' in tools and 'browser.selectedSpace.id == spaceID' in tools,
      "Private browsing and originating space must remain enforced")
print("AI browser tool source-contract checks passed")
