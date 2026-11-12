# Large Photo Library Handling Implementation Plan

## Overview

This document provides a comprehensive implementation plan for addressing the large photo library hanging issue. The solution involves implementing scoped scanning with differentiated photo status awareness, enabling users to start scanning from manageable portions of their libraries without experiencing hangs.

## Implementation Architecture

### 1. Core Components

#### A. ScanScope Enum
```swift
enum ScanScope: String, CaseIterable, Codable {
    case recent100 = "Recent 100"
    case next1000 = "Next 1,000"
    case start2000 = "Start with 2,000"
    case album = "Select album"
    case all = "Full library" // This should be hidden from user-facing UI
    
    var description: String {
        switch self {
        case .recent100: return "Quick preview scan of recent photos"
        case .next1000: return "Medium scan of next 1,000 photos"
        case .start2000: return "Standard scan of first 2,000 photos"
        case .album: return "Scan a specific album"
        case .all: return "Full library scan (not recommended for large libraries)"
        }
    }
    
    var estimatedTime: String {
        switch self {
        case .recent100: return "~1 minute"
        case .next1000: return "~5 minutes"
        case .start2000: return "~10 minutes" 
        case .album: return "~Varies by album size"
        case .all: return "~Hours (not recommended)"
        }
    }
}
```

#### B. Photo Status Enum
```swift
enum PhotoStatus: String, CaseIterable, Codable {
    case local = "Local"
    case cloudOnly = "In iCloud"
    case unknown = "Unknown"
    
    var icon: String {
        switch self {
        case .local: return "📱"
        case .cloudOnly: return "☁️"
        case .unknown: return "❓"
        }
    }
    
    var color: Color {
        switch self {
        case .local: return .green
        case .cloudOnly: return .blue
        case .unknown: return .gray
        }
    }
}
```

### 2. Key Modifications to Existing Code

#### A. ScanEngine.swift Modifications

1. **Add scope parameter to run() method**:
```swift
func run(scope: ScanScope = .all) async -> Outcome {
    // ... existing initialization code ...
    
    // Add scope-based limits for different phases
    let scopeCount = calculateScopeCount(for: scope)
    
    // Modify all limit calculations to be scope-aware
    let maxFullHashes = min(ScanEngine.maximumFullHashesPerScan, scopeCount)
    let visionPairCap = limits.visionPairCap(scopeCount: scopeCount)
    
    // ... rest of existing code with scope-based limits ...
}
```

2. **Add scope-based inventory processing**:
```swift
private func fullInventory(scope: ScanScope) async {
    // Calculate the offset based on scope
    let maxItems = calculateMaxItems(for: scope)
    var offset = 0
    
    // Only process up to the scope limit
    while true {
        if Task.isCancelled || shouldSkip(.inventory) { return }
        
        let page = library.inventoryPage(offset: offset, limit: Self.pageSize)
        if page.photos.isEmpty { break }
        
        // Only process items within scope limits
        let itemsToProcess = min(maxItems - offset, Self.pageSize)
        let processedPage = Array(page.photos.prefix(itemsToProcess))
        
        try? await store.upsert(processedPage)
        offset += processedPage.count
        
        // Update progress based on scope
        reporter?.scanProgress(Double(offset) / Double(maxItems))
        
        if offset >= maxItems { break }
        await Task.yield()
    }
}
```

#### B. CleaningViewModel.swift Modifications

1. **Add scan scope property**:
```swift
@Published private(set) var currentScanScope: ScanScope = .recent100

func setScanScope(_ scope: ScanScope) {
    currentScanScope = scope
}

func runScan(with scope: ScanScope? = nil) async {
    let effectiveScope = scope ?? currentScanScope
    // ... existing scan code with scope parameter ...
}
```

2. **Add library statistics**:
```swift
var libraryStatistics: LibraryStatistics {
    return LibraryStatistics(
        totalItems: statistics.photosEnumerated,
        localItems: statistics.cloudOnlyOrUnavailable,
        cloudOnlyItems: statistics.cloudOnlyOrUnavailable
    )
}

struct LibraryStatistics {
    let totalItems: Int
    let localItems: Int
    let cloudOnlyItems: Int
    
    var localPercentage: Double {
        totalItems > 0 ? Double(localItems) / Double(totalItems) * 100 : 0
    }
    
    var cloudOnlyPercentage: Double {
        totalItems > 0 ? Double(cloudOnlyItems) / Double(totalItems) * 100 : 0
    }
}
```

#### C. ScanStatusCard.swift Modifications

1. **Update to show scope information**:
```swift
private var detail: String? {
    let s = model.statistics
    guard s.photosEnumerated > 0 else { return nil }
    
    // Add scope-specific details
    let checked = "\(s.photosEnumerated.formatted()) photos checked"
    
    // Show cloud status if applicable
    if s.cloudOnlyOrUnavailable > 0 {
        return "\(checked) · \(s.cloudOnlyOrUnavailable.formatted()) in iCloud weren't"
    }
    
    // Show scope information when available
    if let scope = model.currentScanScope {
        return "\(checked) · Scanning with \(scope.rawValue)"
    }
    
    return checked
}
```

### 3. New UI Components

#### A. Scan Selection Screen (ScanScopeView)

```swift
struct ScanScopeView: View {
    @EnvironmentObject private var model: CleaningViewModel
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Select scan scope")) {
                    ForEach(ScanScope.allCases.filter { $0 != .all }, id: \.self) { scope in
                        Button(action: {
                            model.setScanScope(scope)
                            isPresented = false
                            model.runScan()
                        }) {
                            HStack {
                                Text(scope.rawValue)
                                Spacer()
                                Text(scope.estimatedTime)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Section(header: Text("Library Statistics")) {
                    if let stats = model.libraryStatistics {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total items: \(stats.totalItems.formatted())")
                            Text("Local: \(stats.localItems.formatted()) (\(String(format: "%.1f", stats.localPercentage))%)")
                            Text("In iCloud: \(stats.cloudOnlyItems.formatted()) (\(String(format: "%.1f", stats.cloudOnlyPercentage))%)")
                        }
                    }
                }
            }
            .navigationTitle("Scan Library")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
```

#### B. Photo Status Indicators

```swift
struct PhotoStatusView: View {
    let status: PhotoStatus
    
    var body: some View {
        HStack {
            Text(status.icon)
                .font(.system(size: 16))
            Text(status.rawValue)
                .font(.caption)
        }
        .foregroundColor(status.color)
    }
}
```

## Detailed Implementation Steps

### Phase 1: Scope-based Scanning Implementation

#### Step 1: Create ScanScope Enum
- Add the `ScanScope` enum to a new file `App/Models/ScanScope.swift`
- Include all required cases and helper properties

#### Step 2: Modify ScanEngine
- Update `run()` method signature to accept scope parameter  
- Implement scope-based limit calculations
- Modify inventory processing to respect scope limits
- Add scope-aware logic to all scanning phases

#### Step 3: Update CleaningViewModel
- Add currentScanScope property
- Modify scan methods to use scope parameters
- Add library statistics calculation
- Update progress reporting to be scope-aware

### Phase 2: Photo Status Differentiation

#### Step 1: Extend PhotoSnapshot
- Add status field to `PhotoSnapshot` struct
- Implement status determination logic in `ScanEngine`

#### Step 2: Update PhotoLibraryClient
- Add methods to determine photo status (local vs cloud)
- Modify existing library client implementations

#### Step 3: Update UI Components
- Add photo status indicators to relevant views
- Display information about iCloud photos in scan results

### Phase 3: User Interface Enhancements

#### Step 1: Create Scan Selection Screen
- Implement `ScanScopeView` with clear options
- Add library statistics display
- Ensure proper navigation flow

#### Step 2: Update Progress Indicators  
- Modify `ScanStatusCard` to show scope information
- Add more detailed progress feedback
- Implement stall detection and recovery

### Phase 4: Testing and Validation

#### Step 1: Unit Tests
- Test all new scan scope logic
- Verify scope-based limits are properly enforced
- Test photo status determination

#### Step 2: Integration Tests
- Test complete scanning flow with different scopes
- Verify state persistence across app launches
- Validate error handling scenarios

#### Step 3: Performance Testing
- Test with large libraries (>44,000 items)
- Verify no hangs or memory issues
- Confirm proper resource usage within bounds

## Code Structure and File Organization

### New Files to Create

1. `App/Models/ScanScope.swift` - Contains ScanScope enum and related logic
2. `App/Views/ScanScopeView.swift` - Scan selection interface 
3. `App/Components/PhotoStatusView.swift` - Photo status indicator component

### Modified Files

1. `App/Services/ScanEngine.swift` - Add scope parameter support
2. `App/Services/CleaningViewModel.swift` - Add scope management
3. `App/Views/ScanStatusCard.swift` - Update progress display
4. `App/Models/SwipePairModel.swift` - Ensure compatibility with new scan scopes

## Key Implementation Details

### 1. Resource Management
- Maintain existing constraint of one asset in flight at all times
- Implement proper memory pressure handling 
- Use LRU caches for feature prints and quality signals

### 2. State Persistence
- Ensure scan state is properly saved when app is backgrounded
- Implement checkpointing at scope boundaries
- Support resuming scans from any point

### 3. User Experience
- Provide clear feedback during all phases
- Show estimated time remaining
- Handle interruptions gracefully with recovery options

## Backward Compatibility

The implementation will maintain full backward compatibility:
- All existing APIs remain unchanged
- Default behavior remains the same for automated operations
- Only user-facing interfaces are modified to provide scope options
- All safety checks and validation mechanisms preserved

## Performance Considerations

### Memory Usage
- Maintain bounded memory usage within tier-appropriate limits (F03 constraints)
- Implement proper caching with LRU eviction
- Use paging for all large data structures

### Processing Time
- Ensure each scope completes within reasonable timeframes
- Provide progress feedback during processing
- Optimize algorithms to be linear or near-linear in scope size

## Testing Strategy

### Unit Tests
1. Test ScanScope enum functionality
2. Verify limit calculations are correct per scope
3. Test photo status determination logic

### Integration Tests  
1. Test complete scan flow with different scopes
2. Validate state persistence across app lifecycle
3. Verify error handling and recovery scenarios

### Performance Tests
1. Test with libraries >44,000 items
2. Verify no hangs or memory issues
3. Confirm proper resource usage patterns

## Deployment Plan

### Initial Release
- Implement core scope-based scanning functionality
- Add scan selection UI at app launch
- Provide basic photo status differentiation

### Follow-up Enhancements
- Add advanced scope options (custom ranges, date filters)
- Improve progress visualization and feedback
- Add more detailed statistics and insights

## Risk Assessment

### Technical Risks
1. **Memory Management**: Ensuring proper handling of large libraries with limited memory
2. **Performance Degradation**: Maintaining good performance across all scopes
3. **State Consistency**: Ensuring proper state persistence and recovery

### User Experience Risks
1. **Confusion**: Users may not understand the different scope options
2. **Inappropriate Defaults**: Default scope might not be suitable for all users
3. **Missing Features**: Some users might want more advanced filtering options

## Success Indicators

1. No more hangs when scanning large libraries (>44,000 items)
2. Users can complete scans successfully with manageable time commitments  
3. Clear progress feedback during all phases of scanning
4. Appropriate handling of iCloud vs local photo status
5. Maintained performance on low-end devices (iPhone SE 2nd gen)