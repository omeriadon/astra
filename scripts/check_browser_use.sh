#!/bin/zsh
set -euo pipefail

# Run after an Xcode MCP build; supply its Build/Products/Debug directory.
SDK_PRODUCTS=${1:?Supply the Xcode Build/Products/Debug directory}
TASK_ROOT=${0:A:h:h}
TASK_OUTPUT=$(mktemp -d /tmp/astra-browser-use-checks.XXXXXX)
trap 'rm -rf "$TASK_OUTPUT"' EXIT
cd "$TASK_ROOT"

swiftc -swift-version 6 -parse-as-library \
  astra/App/BrowserLog.swift \
  astra/Agent/BrowserAgentHTTP.swift scripts/check_agent_http.swift \
  -o "$TASK_OUTPUT/framing"
"$TASK_OUTPUT/framing"

swiftc -swift-version 6 -parse-as-library \
  astra/Agent/BrowserAgentPageScripts.swift checks/browser-use-dom.swift \
  -o "$TASK_OUTPUT/dom"
"$TASK_OUTPUT/dom"

for TASK_CHECK in http listener; do
  swiftc -swift-version 6 -D ASTRA_BROWSER_USE_FIXTURE -parse-as-library \
    -I "$SDK_PRODUCTS" \
    -I "$SDK_PRODUCTS/../../Intermediates.noindex/GeneratedModuleMaps" \
    astra/App/BrowserLog.swift \
    astra/Agent/BrowserAgentHTTP.swift \
    astra/Agent/BrowserAgentResultEncoder.swift \
    astra/Agent/BrowserAgentPageScripts.swift \
    astra/Agent/BrowserAgentProtocol.swift \
    astra/Agent/BrowserAgentToolCatalog.swift \
    astra/Agent/BrowserAgentStateSignal.swift \
    astra/Agent/BrowserAgentServer.swift \
    checks/browser-use-model-fixtures.swift "checks/browser-use-$TASK_CHECK.swift" \
    "$SDK_PRODUCTS/MCP.o" "$SDK_PRODUCTS/SystemPackage.o" \
    "$SDK_PRODUCTS/CSystem.o" "$SDK_PRODUCTS/Logging.o" \
    "$SDK_PRODUCTS/EventSource.o" "$SDK_PRODUCTS/DequeModule.o" \
    "$SDK_PRODUCTS/InternalCollectionsUtilities.o" \
    -o "$TASK_OUTPUT/$TASK_CHECK"
  "$TASK_OUTPUT/$TASK_CHECK"
done

if /usr/bin/sandbox-exec -p '(version 1)(allow default)(deny network-bind)' \
  "$TASK_OUTPUT/listener" > "$TASK_OUTPUT/denied.txt" 2>&1; then
  print -u2 "Listener incorrectly stayed enabled after network binding was denied"
  exit 1
fi
/usr/bin/grep -Fq 'Listener remains enabled: false; status: This build cannot accept' "$TASK_OUTPUT/denied.txt"
cat "$TASK_OUTPUT/denied.txt"
