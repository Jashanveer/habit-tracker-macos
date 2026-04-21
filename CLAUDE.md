# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```sh
# Build
xcodebuild -project habit-tracker-macos.xcodeproj -scheme habit-tracker-macos build

# Run all tests
xcodebuild -project habit-tracker-macos.xcodeproj -scheme habit-tracker-macos test

# Open in Xcode
open habit-tracker-macos.xcodeproj
```

When running inside Xcode, prefer `BuildProject` and `RunAllTests`/`RunSomeTests` MCP tools. Use `XcodeRefreshCodeIssuesInFile` for fast compile-error checking without a full build.

## Architecture

**macOS-only SwiftUI + SwiftData app** — a single-window habit tracker.

- **Data model** (`Habit.swift`): Single `@Model` class `Habit` with `title`, `createdAt`, and `completedDayKeys: [String]`. Day keys use `"yyyy-MM-dd"` format. No relationships or migrations yet.
- **App entry** (`habit_tracker_macosApp.swift`): Sets up `ModelContainer` with persistent storage and a single `WindowGroup`.
- **UI** (`ContentView.swift`): ~1300-line monolithic file containing all views, styles, and logic:
  - `ContentView` — root view with `@Query` for habits, gradient background, center panel, slide-out stats sidebar, and calendar sheet
  - `HabitMetrics` — pure struct with static methods for streak calculation, perfect days, and medal/achievement logic
  - `DateKey` — enum with static helpers for date-to-key conversion, streak math, and calendar grid generation
  - `Medal`, `DayInfo` — supporting data types
  - Multiple private view structs: `CenterPanel`, `HabitCard`, `StatsSidebar`, `CalendarSheet`, `YearPerfectCalendar`, etc.
  - Custom `liquidGlassBackground` view modifier wrapping macOS 26 `glassEffect` with fallback to `ultraThinMaterial`
  - Custom button styles: `PrimaryCapsuleButtonStyle`, `EdgeHandleButtonStyle`, `SecondaryButtonStyle`

All completion tracking uses string day keys (not booleans), enabling historical streak and calendar views.

## Key Patterns

- **Liquid Glass**: Uses macOS 26 `glassEffect` API with `@available(macOS 26.0, *)` checks and pre-26 fallbacks. The `liquidGlassBackground` and `liquidGlassControl` View extensions are the shared glass styling primitives.
- **Streaks**: `HabitMetrics.currentStreak` and `bestStreak` operate on sorted `[String]` day keys, walking backwards by calendar day.
- **Testing**: Uses Swift Testing framework (`@Test`, `#expect`). Tests are currently scaffolded but empty.

## Design Philosophy

Act as a professional iOS/macOS developer at Apple. This app must feel and behave like a native Mac app:
- Use spring animations (`.spring(response:dampingFraction:)`) for all interactive transitions — never linear or basic ease curves
- Panels expand from their origin point like macOS Dock icons (scale from near-zero at anchor)
- Hover states on interactive elements (cards, buttons) with subtle scale and color shifts
- Use `FoundationModels` framework for on-device AI text generation (macOS 26+) with graceful fallback
- Respect system color scheme, use `nsColor` bridging for platform-native colors
- Symbol effects (`.contentTransition(.symbolEffect)`) for toggling SF Symbols

## Code Style

- 4-space indentation
- PascalCase types, camelCase properties/methods
- `private` for all view structs except `ContentView`
- SwiftUI + SwiftData + FoundationModels (no Combine, no UIKit)
- Minimal imports: `SwiftUI`, `SwiftData`, `Foundation`, `FoundationModels`

<!-- code-review-graph MCP tools -->
## MCP Tools: code-review-graph

**IMPORTANT: This project has a knowledge graph. ALWAYS use the
code-review-graph MCP tools BEFORE using Grep/Glob/Read to explore
the codebase.** The graph is faster, cheaper (fewer tokens), and gives
you structural context (callers, dependents, test coverage) that file
scanning cannot.

### When to use graph tools FIRST

- **Exploring code**: `semantic_search_nodes` or `query_graph` instead of Grep
- **Understanding impact**: `get_impact_radius` instead of manually tracing imports
- **Code review**: `detect_changes` + `get_review_context` instead of reading entire files
- **Finding relationships**: `query_graph` with callers_of/callees_of/imports_of/tests_for
- **Architecture questions**: `get_architecture_overview` + `list_communities`

Fall back to Grep/Glob/Read **only** when the graph doesn't cover what you need.

### Key Tools

| Tool | Use when |
|------|----------|
| `detect_changes` | Reviewing code changes — gives risk-scored analysis |
| `get_review_context` | Need source snippets for review — token-efficient |
| `get_impact_radius` | Understanding blast radius of a change |
| `get_affected_flows` | Finding which execution paths are impacted |
| `query_graph` | Tracing callers, callees, imports, tests, dependencies |
| `semantic_search_nodes` | Finding functions/classes by name or keyword |
| `get_architecture_overview` | Understanding high-level codebase structure |
| `refactor_tool` | Planning renames, finding dead code |

### Workflow

1. The graph auto-updates on file changes (via hooks).
2. Use `detect_changes` for code review.
3. Use `get_affected_flows` to understand impact.
4. Use `query_graph` pattern="tests_for" to check coverage.
