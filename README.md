# whereami

A CLI tool written in Zig that taps into system-level location services to tell you where you are — natively, on macOS, Windows, and Linux.

## What it does

`whereami` calls your operating system's native location APIs directly — no HTTP requests, no API keys, no third-party services. It returns your latitude, longitude, and accuracy, and on platforms that support reverse geocoding (macOS today) it also resolves those coordinates to a human-readable address.

Output is human-readable by default, with a `--json` flag for scripting and piping into other tools.

```
$ whereami --mock=40.7128,-74.0060
Location: 40.7128, -74.0060
Accuracy: 0m

$ whereami --mock=40.7128,-74.0060 --json
{"latitude":40.7128,"longitude":-74.006,"accuracy":0,"address":null}
```

On macOS, real (non-`--mock`) runs also include an `Address:` line with the reverse-geocoded street, city, state, postal code, and country.
