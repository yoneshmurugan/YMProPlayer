# Custom Theming Engine & Light Mode Implementation Plan

## Goal Description
Implement a robust, customizable theming engine for YM Pro that fully supports a clean Light Mode, user-selectable accent colors, and adjustable glassmorphism blur intensities. We will add a dedicated "UI & Theming" section to the Settings menu and refactor the entire app's hardcoded colors to use adaptive semantic colors.

## Open Questions
- **Accent Color Selection**: Would you like predefined aesthetic accent colors (e.g., Deep Purple, Ocean Blue, Neon Pink), or a free-form color picker? (I plan to implement 5 predefined premium colors to maintain the app's aesthetic consistency).

## Proposed Changes

### 1. `ytsplayer/ViewModel/ThemeManager.swift`
- **[NEW]** Create an `ObservableObject` to manage:
  - `themeMode`: Enum (System, Light, Dark)
  - `accentColor`: Enum of predefined premium colors (defaulting to the current purple/indigo vibe).
  - `glassIntensity`: Enum for `.ultraThinMaterial`, `.thinMaterial`, etc.
- Add an extension on `View` to easily apply the `themeManager.colorScheme` override.

### 2. `ytsplayer/ytsplayerApp.swift`
- Inject the `ThemeManager` as an `@EnvironmentObject` into the root view.
- Apply the `.preferredColorScheme` override at the root window level.
- Apply the selected global `accentColor`.

### 3. `ytsplayer/Views/SettingsView.swift`
- **[MODIFY]** Add a new section `UI & Theming`.
- Add controls (Pickers/Toggles) bound to the `ThemeManager`'s properties so users can customize the app in real-time.

### 4. Global UI Refactoring (The Massive Cleanup)
Currently, the app uses hardcoded `Color.white` and `Color.black` in over 200 places. I will refactor these files to use Apple's native adaptive semantic colors (`.primary`, `.secondary`, `.background`, `.ultraThinMaterial`), so they look stunning in both Dark and Light mode.
Target files include:
- `ContentView.swift`
- `NowPlayingBar.swift`
- `TracksView.swift`
- `ArtistsView.swift` & `ArtistDetailView.swift`
- `AlbumsView.swift` & `AlbumDetailView.swift`
- `HomeView.swift`
- `QueueView.swift`
- `LibraryView.swift`

*Note: Backgrounds that use `Color.black.opacity(...)` will be upgraded to use native SwiftUI `.materials` (like `.ultraThinMaterial`) combined with the user's selected `glassIntensity`.*

## Verification Plan
### Manual Verification
1. Open the Settings menu and verify the new "UI & Theming" section exists.
2. Toggle between Light Mode and Dark Mode and ensure no text is illegible (i.e., no white text on white backgrounds).
3. Change the Accent Color and verify that play buttons, active toggles, and highlights update instantly.
4. Verify the glassmorphism backgrounds adapt correctly to Light Mode without looking muddy.
