#!/bin/zsh
set -euo pipefail
# Compile against the exact SDK artifacts used by the app; no package download.
SDK_PRODUCTS=${1:?Supply Xcode Build/Products/Debug directory}
TASK_ROOT=${0:A:h:h}
TASK_OUTPUT=$(mktemp -d /tmp/astra-agent-protocol.XXXXXX)
trap 'rm -rf "$TASK_OUTPUT"' EXIT
cd "$TASK_ROOT"
swiftc -swift-version 6 -parse-as-library -strict-concurrency=complete \
  -I "$SDK_PRODUCTS" \
  -I "$SDK_PRODUCTS/../../Intermediates.noindex/GeneratedModuleMaps" \
  astra/Agent/BrowserAgentHTTP.swift astra/Agent/BrowserAgentProtocol.swift \
  checks/browser-use-protocol.swift \
  "$SDK_PRODUCTS/MCP.o" "$SDK_PRODUCTS/SystemPackage.o" \
  "$SDK_PRODUCTS/CSystem.o" "$SDK_PRODUCTS/Logging.o" \
  "$SDK_PRODUCTS/EventSource.o" "$SDK_PRODUCTS/DequeModule.o" \
  "$SDK_PRODUCTS/InternalCollectionsUtilities.o" \
  -o "$TASK_OUTPUT/protocol"
"$TASK_OUTPUT/protocol"
