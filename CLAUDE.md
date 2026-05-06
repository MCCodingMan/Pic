# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

"Magic" (Pic) is a SwiftUI photo editor iOS app. It provides image adjustments, filters, masks, stickers, drawings, curves, HSL tuning, and collage features. The UI is entirely in Chinese (zh-CN).

## Build & Run

- Open `Pic.xcodeproj` in Xcode and build/run on a device or simulator
- `xcodebuild -project Pic.xcodeproj -scheme Magic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` for CLI builds
- Target: iOS 17+, Swift 5.9+
- Metal shaders are in `Magic/Pic/Resources/Shaders.ci.metal`

## Architecture

**MVVM with @Observable (Observation framework, not Combine)**

- **App entry**: `Magic/MagicApp.swift` → `MainTabView` (custom floating tab bar with Home, Camera, Photo Picker, Album)
- **ViewModels**: Use `@Observable` (iOS 17 Observation framework). `EditorViewModel` is the core — manages edit state, undo/redo history, image processing pipeline, stickers, masks, and export. `HomeViewModel` handles project listing and photo library access.
- **Models**: All value types (`struct`). `EditState` is the central edit document containing adjustments, crop, rotation, filters, masks, stickers, and drawings. `PhotoProject` wraps an edit state with metadata.
- **Services** (singletons):
  - `ImageProcessingService` — Metal-based image processing pipeline. Converts CIImage→MTLTexture, runs compute kernels (adjustments, HSL, curves, sharpen, grain, vignette, color matrix filters, masks/blending), then converts back. Uses ping-pong texture buffers for multi-pass rendering.
  - `PersistenceService` — JSON file-based project storage in Documents directory with backup/restore
  - `PhotoLibraryService` — PhotoKit wrapper for saving images
  - `CameraService` — AVFoundation camera capture

## Critical Constraints (from AGENTS.md)

- **Never use `@Published`** — use `@Observable` or `@State` with value types instead
- **All responses must be in Chinese (zh-CN)**
- Default to iOS 17+ and Swift 5.9+ with Swift Concurrency (async/await)

## Key Patterns

- `EditorViewModel` uses `AsyncStream` with `.bufferingNewest(1)` for debounced preview updates — edits are yielded to the stream and processed sequentially
- Undo/redo is snapshot-based: entire `EditState` structs are pushed to stacks (max 50 levels)
- Image processing uses Metal compute shaders for all pixel operations; CIImage/CIContext is only used for initial texture loading and final CGImage output
- Filters come in two paths: standard (adjustments → color matrix) and Metal-optimized unified kernel (single pass for both)
- Preview uses downsampled images (max 1200px) for performance; full-res processing only on export
