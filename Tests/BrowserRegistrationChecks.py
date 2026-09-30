# Run with the source plist or the built app's Contents/Info.plist:
# python3 Tests/BrowserRegistrationChecks.py astra/Info.plist
import plistlib
import sys
from pathlib import Path

with Path(sys.argv[1]).open("rb") as source:
    info = plistlib.load(source)

schemes = {
    scheme
    for registration in info.get("CFBundleURLTypes", [])
    if registration.get("CFBundleTypeRole") == "Viewer"
    for scheme in registration.get("CFBundleURLSchemes", [])
}
assert {"http", "https"} <= schemes, "Astra must register both web URL schemes"
print("Browser URL registration checks passed")
