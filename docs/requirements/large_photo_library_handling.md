# Large Photo Library Handling Requirements

## Problem Statement

The current implementation of CleanSlate hangs when users with large photo libraries (exceeding 44,000 images and assets) attempt to scan their library. This occurs because:

1. The initial scan process attempts to enumerate the entire library at once
2. The scan process becomes unresponsive during resource-intensive phases (especially "Checking the original files" and "Comparing similar shots")
3. Memory pressure issues occur due to whole-library arrays and uncached Vision requests
4. No mechanism exists to provide immediate feedback or allow users to proceed with smaller, manageable scans

## User Requirements

### 1. Initial Onboarding Experience

When users first open the app:
- Users should not be forced to scan their entire library immediately
- Provide clear options for starting a scan with manageable volumes
- Display progress in real-time with meaningful feedback
- Allow users to pause/resume scans at any point

### 2. Scan Scope Options

Users should be able to choose from different scan scopes:
- **Do 100 photos** - Quick preview scan 
- **Scan the next 1,000 photos** - Medium scan
- **Start with 2,000 photos** - Standard scan
- **Select a particular album** - Targeted scan

### 3. iCloud vs Local Photos Differentiation

Users need to understand which photos are:
- Already downloaded locally on the device
- Still in iCloud (requiring download)
- Can be scanned without internet connectivity

### 4. Performance and Stability

The application should:
- Never freeze or hang during scanning
- Provide clear progress indicators at all stages
- Handle large libraries gracefully with bounded resources
- Allow users to start scanning from any point in the library
- Provide options to pause and resume scans

## Technical Requirements

### 1. Scan Scoping Implementation

#### A. Scope-based Scanning
- Implement a `ScanScope` enum that defines different scanning limits:
  - `.recent100` (100 most recent items)
  - `.next1000` (1,000 next items)
  - `.start2000` (2,000 starting items) 
  - `.album(id: String)` (specific album)
  - `.all` (full library - deprecated for user-facing UI)

#### B. Progress Tracking
- Add progress tracking that reflects actual scan scope
- Show clear indicators of how much of the selected scope has been processed
- Provide estimated time remaining based on current processing rate

### 2. Photo Status Differentiation

#### A. Local vs iCloud Photos
- Implement photo status enumeration:
  - `.local` (downloaded and available locally)
  - `.cloudOnly` (only available in iCloud, requires download)
  - `.unknown` (status not yet determined)

#### B. Visual Indicators
- Show different visual indicators for local vs iCloud photos in scan results
- Display information about cloud-only photos that may be missed in the scan

### 3. User Experience Improvements

#### A. Scan Selection Interface
- Create a new scan selection screen at app launch
- Provide clear options with descriptions and estimated time/cost implications
- Show library statistics (total items, iCloud items, local items)

#### B. Progress Feedback
- Implement real-time progress updates during scanning
- Display current phase and percentage complete
- Show memory usage and thermal status

### 4. Performance Optimization

#### A. Resource Management
- Implement strict resource limits per scan
- Add memory pressure handling that gracefully reduces processing
- Ensure only one asset is in flight at any time (maintaining existing constraint)

#### B. Caching Strategy
- Implement LRU caches for feature prints and quality signals
- Cache results to avoid reprocessing the same photos
- Clear caches when memory pressure is detected

## Implementation Plan

### Phase 1: Scope-based Scanning (F04)

#### A. Core Changes
1. Add `ScanScope` enum to define different scan limits
2. Modify `ScanEngine.run()` to accept a scope parameter
3. Update `ScanLimits` to support scope-based limiting
4. Implement paging for all phases based on the selected scope

#### B. UI Changes
1. Create new scan selection interface at app launch
2. Add library statistics display (total, local, iCloud items)
3. Implement scope selection buttons with clear descriptions
4. Update scan status card to show scope-based progress

### Phase 2: Photo Status Differentiation

#### A. Core Changes
1. Add photo status tracking in `PhotoSnapshot` 
2. Modify `PhotoLibraryClient` to provide status information
3. Update `ScanEngine` to differentiate between local and iCloud photos
4. Implement visual indicators for different photo statuses

#### B. UI Changes
1. Update scan results to show photo status indicators
2. Add explanations about cloud-only photos in scan results
3. Provide guidance on downloading photos for complete scanning

### Phase 3: Enhanced User Experience

#### A. Progress Improvements
1. Implement more granular progress reporting
2. Add estimated time remaining calculations
3. Improve stall detection and recovery mechanisms
4. Add pause/resume functionality with proper state persistence

#### B. Error Handling
1. Implement graceful handling of timeouts and failures
2. Provide clear error messages when scans are interrupted
3. Ensure proper cleanup of resources on interruption

## Detailed Design Considerations

### 1. Scan Scope Implementation

The implementation should:
- Use the existing `ScanLimits` system to define scope-based limits
- Maintain backward compatibility with full library scanning (when explicitly requested)
- Provide a default scope that's appropriate for typical user libraries
- Allow users to easily switch between different scopes

### 2. Resource Management

Key constraints:
- Only one asset in flight at any time (maintaining existing F03 requirement)
- Memory usage bounded to tier-appropriate limits
- Process batches of photos with proper checkpointing
- Implement memory pressure detection and handling

### 3. User Interface Considerations

#### A. Scan Selection Screen
- Clear visual distinction between different scope options
- Estimated time/cost information for each option
- Library statistics overview (total items, iCloud items)
- Option to proceed with full library scan (if user really wants it)

#### B. Progress Indicators
- Real-time progress updates showing percentage complete
- Current phase display with meaningful labels
- Memory usage and thermal status indicators
- Stall detection with recovery options

### 4. Technical Architecture

The solution should:
- Integrate seamlessly with existing `ScanEngine` architecture
- Maintain all safety checks and validation mechanisms
- Preserve existing API contracts where possible
- Follow established patterns for error handling and resource management
- Support the existing diagnostics system for troubleshooting

## Risk Mitigation

### 1. Performance Risks
- Ensure all phases remain bounded by scope limits
- Implement proper memory pressure handling
- Maintain performance on low-end devices (iPhone SE 2nd gen, etc.)

### 2. User Experience Risks  
- Provide clear feedback at every stage of scanning
- Ensure users understand the implications of different scan scopes
- Make it easy to resume interrupted scans

### 3. Compatibility Risks
- Maintain backward compatibility with existing code
- Ensure all existing tests continue to pass
- Preserve all safety gates and validation mechanisms

## Success Metrics

1. **No more hangs**: Scans should complete successfully for libraries >44,000 items
2. **User confidence**: Users should be able to start scanning without fear of freezing
3. **Performance**: Scans should complete within reasonable timeframes based on selected scope
4. **Usability**: Clear UI with proper feedback at all stages

## Dependencies and Timeline

### Immediate Dependencies
- F03 scan stability (already approved)
- Existing `ScanEngine` and `ScanLimits` architecture
- Current diagnostics system for monitoring performance

### Implementation Timeline
1. **Week 1**: Implement scope-based scanning with basic UI
2. **Week 2**: Add photo status differentiation 
3. **Week 3**: Enhance progress feedback and error handling
4. **Week 4**: Testing, validation, documentation

## Alternative Approaches Considered

### Approach 1: Full Library Scanning (Current)
- **Pros**: Complete coverage of all photos
- **Cons**: Hangs on large libraries (>44,000 items), memory intensive

### Approach 2: Incremental Scanning with Resume
- **Pros**: Can handle very large libraries, users can interrupt and resume
- **Cons**: More complex implementation, requires state persistence

### Approach 3: Smart Scoping Based on Library Characteristics  
- **Pros**: Automatically chooses optimal scope based on library size/characteristics
- **Cons**: Requires additional analysis, might not always be correct

### Approach 4: Background Processing with Notification
- **Pros**: Allows users to continue using app while scanning
- **Cons**: May not provide immediate feedback, more complex UI design

## Recommendations

1. **Prioritize scope-based scanning** as the primary solution since it directly addresses the hang issue
2. **Maintain existing safety mechanisms** to ensure no regressions in protection or validation
3. **Provide clear user guidance** about when and why to choose different scopes
4. **Implement robust error handling** for interrupted scans and recovery scenarios
5. **Keep performance monitoring** through existing diagnostics system