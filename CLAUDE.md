# Build Instructions
Use the iPhone 16 Pro simulator for builds:
```bash
xcodebuild -scheme "DhikrCounter" -configuration Debug -destination "platform=iOS Simulator,name=iPhone 16 Pro" build
```

Available schemes:
- DhikrCounter (iOS app)
- DhikrCounter Watch App (watchOS app)

# Architecture Overview

## File-based Session Persistence
- **Location**: `~/Documents/DhikrSessions/`
- **Format**: Individual JSON files per session: `session_[UUID].json`
- **Auto-load**: Sessions automatically loaded on app startup
- **Structure**: `PersistedSessionData` contains complete session + sensor data

## Data Transfer Optimization (Issue #11)
- **Method**: `transferFile()` instead of `transferUserInfo()` for large sensor datasets
- **File Processing**: Immediate file reading in `didReceive file:` to prevent race conditions with WatchConnectivity cleanup
- **Session ID Mapping**: Uses `DhikrSession.createWithId()` to preserve original UUIDs from Watch

## Key Files
- `DhikrCounter/PhoneSessionManager.swift`: iPhone-side data reception and persistence
- `DhikrCounter Watch App/WatchSessionManager.swift`: Watch-side data transfer
- `DhikrCounter/DataVisualizationView.swift`: Charts with Catmull-Rom interpolation
- `DhikrCounter/CompanionContentView.swift`: Main dashboard UI

## Known Issues
- Actor isolation warnings with WCSessionDelegate (fixed with `@preconcurrency`)
- Swift 6 compatibility warnings (non-critical)

## Charts Implementation
- Uses Swift Charts framework
- Catmull-Rom interpolation for smooth curves: `.interpolationMethod(.catmullRom)`
- Multiple sensor metrics: Acceleration X/Y/Z, Rotation X/Y/Z, Magnitudes
- Default metric: `accelerationX` for better oscillation visibility

# Important Implementation Notes
- Sessions persist across app builds/restarts
- File-based storage handles large sensor datasets efficiently  
- UI shows real metrics from transferred sensor data
- Debug logging removed from frequently called methods to prevent spam
- use .venv or venv for python