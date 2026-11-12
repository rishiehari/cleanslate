> 2026-11-12: Historical proposal from the previous parallel work. Current implementation and evidence are in `docs/implementation_summary.md`, `docs/VALIDATION_LOG.md`, and `docs/PHONE_TESTING.md`; unsupported album/local-cloud-count/next-batch claims below are not implemented product behavior.

# 10 Alternatives for Handling Large Photo Libraries

## 1. Scope-based Scanning with User Selection

**Description**: Allow users to choose from predefined scan scopes (100, 1,000, 2,000 photos) or select specific albums.
- **Pros**: Immediate relief for large library users, clear user control, no hang risk
- **Cons**: Requires UI changes, may not be intuitive for all users

## 2. Smart Scoping Based on Library Characteristics

**Description**: Automatically determine optimal scan scope based on library size, age, and usage patterns.
- **Pros**: No user decision required, potentially optimal for each user
- **Cons**: Complex implementation, might not always choose correctly, less control for user

## 3. Incremental Scanning with Resume Capability

**Description**: Break scanning into chunks that can be paused and resumed at any point.
- **Pros**: Allows users to scan in sessions, no loss of progress
- **Cons**: More complex state management, requires persistent storage

## 4. Background Processing with Notification

**Description**: Allow scanning to run in background while providing notifications when complete.
- **Pros**: No blocking of UI, allows user to continue working
- **Cons**: May not provide immediate feedback, more complex UI design

## 5. Cloud-Only vs Local Processing Separation

**Description**: Process local photos first, then handle iCloud photos separately with clear warnings.
- **Pros**: Clear user understanding of what's being scanned, reduces hang risk
- **Cons**: More complex logic for determining photo status

## 6. Adaptive Resource Management

**Description**: Dynamically adjust processing resources based on device capabilities and current load.
- **Pros**: Optimizes performance per device, maintains responsiveness
- **Cons**: Complex to implement correctly, may not prevent all hangs

## 7. Pre-filtered Library Scanning

**Description**: Scan only specific types of photos (videos, screenshots, etc.) or filter by date/album first.
- **Pros**: Reduces scan volume significantly, faster results
- **Cons**: May miss some duplicate photos, less comprehensive scanning

## 8. Multi-phase Scanning with Progress Indicators

**Description**: Break the scanning process into clearly defined phases with progress tracking.
- **Pros**: Better user experience, clear feedback at each stage
- **Cons**: Requires significant UI changes, more complex state management

## 9. Memory-Efficient Data Structures

**Description**: Use streaming and paging approaches to avoid loading entire libraries into memory.
- **Pros**: Addresses root cause of memory issues, maintains performance
- **Cons**: Requires architectural changes to existing scanning pipeline

## 10. Hybrid Approach with User Guidance

**Description**: Combine multiple techniques - automatic scope detection with user override options.
- **Pros**: Balances automation and control, comprehensive solution
- **Cons**: Most complex to implement and test thoroughly

## Recommendation

Based on the analysis of the current codebase and F03 architecture constraints, **Alternative 1 (Scope-based Scanning)** combined with **Alternative 5 (Cloud-Only vs Local Processing Separation)** provides the best balance of immediate relief for hanging issues while maintaining all existing safety mechanisms. This approach:

1. Provides clear user control over scanning scope
2. Prevents hangs by limiting processing volume
3. Addresses the iCloud vs local photo differentiation requirement
4. Maintains compatibility with existing F03 architecture
5. Allows users to start with manageable scans and expand as needed
6. Is relatively straightforward to implement and test

The implementation will leverage the existing scan limits system, maintain all safety checks, and provide clear UI feedback about what's being scanned and how much remains.