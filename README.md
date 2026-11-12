# CleanSlate Swipe n Save Feature

This document describes the implementation of the Swipe n Save feature that allows users to review and decide which photos from similar pairs to keep.

## Implementation Overview

The Swipe n Save feature implements a swipe-based interface for reviewing photo pairs:
- Supports both exact and similar pairs
- Swipe left/right to choose which photo to keep, up/center button to keep both
- Integration with the app's tab system
- Safety gates and protection checks
- Practice/tutorial component for first-time users

## Core Components

### SwipePairModel.swift
- Handles the logic for swipe operations on photo pairs
- Supports exact and similar pair types
- Implements safety checks and warnings
- Manages decision tracking and approval flow

### SwipeSaveView.swift  
- Main UI view with swipe gesture handling
- Displays photo pairs for review
- Implements swipe interaction (left/right to choose, up to keep both)
- Integrates with the app's tab system
- Shows appropriate state messages and permissions

## Feature Requirements Met

✅ Exact pair support - handles byte-for-byte identical photos  
✅ Similar pair support - handles visually similar photos  
✅ Swipe gestures - left/right to keep one photo, up to keep both  
✅ Safety gates - protection checks and warning systems  
✅ Integration with app tabs - appears as a dedicated tab  
✅ Practice/tutorial - initial onboarding flow for new users  
✅ Unit tests - comprehensive test coverage  

## Large Library Handling

To address hanging issues with large photo libraries (>44,000 items), the following improvements have been implemented:

### Scan Scoping
- Users can now choose from different scan scopes:
  - Do 100 photos (Quick preview)
  - Scan the next 1,000 photos (Medium scan)  
  - Start with 2,000 photos (Standard scan)
  - Select a particular album (Targeted scan)
- Full library scanning is still available but not recommended for large libraries

### Photo Status Differentiation
- Clear indication of which photos are local vs in iCloud
- Users understand what will be scanned without internet connectivity
- Better feedback about potential missing duplicates due to cloud-only photos

## Usage

1. The feature is accessible through the main app's tab bar
2. Users see pairs of photos that need review 
3. Swipe left or right to keep one photo, or swipe up to keep both
4. Tap "Approve" to add the chosen photo to the deletion tray
5. First-time users see a practice tutorial

## Implementation Notes

The implementation follows all requirements from SWIPE_N_SAVE_PLAN.md:
- Supports both exact and similar pairs as specified 
- Uses swipe gestures for intuitive interaction
- Includes proper safety gates and protection checks
- Integrates cleanly into the app's existing tab system
- Provides a clear onboarding experience for new users
- Maintains compatibility with large library handling improvements