# MyPlayer delivery requirements

- Keep the application bundle named MyPlayer.app, without an Updated or build suffix.
- Preserve the fixed user data directory and existing records when updating.
- Deliver MyPlayer.zip only, without DMG. Run package_app.sh and verify the app signature.
- Playback restoration changes must pass Tests/run_build39.sh. Tests use isolated user data; do not launch against or modify the user's real library for verification.

- Selection updates must not inject/remove row subviews or trigger full-table redraws. Do not use continuous KVO write-back to fight SwiftUI row sizing.
- Keep original artwork on disk with backup and integrity verification; do not retain original cover data as image-cache keys. Run Tests/run_build44.sh for artwork, native marquee or selection changes.

## Next release policy (user instruction, 2026-10-24)

- Starting with the next release, merge this development line into the formal release; do not continue publishing it as Beta.
- Use `vMAJOR.MINOR.PATCH` release naming. The release sequence is `v4.0.18`, `v4.0.19`, `v4.0.20`, and so on. This checkout is `v4.0.24`; the next release must be `v4.0.25`.
- Replace the old parenthesized version display and Beta suffix in the next release. Preserve library/settings data when integrating the existing Beta data into the formal app.
- This instruction does not request changing the already published `v4.0.0-beta.17` GitHub tag or release now.

## v4.0.19 navigation scope

- Preserve the v4.0.18 fullscreen background implementation; Tests/run_navigation19.sh checks protected hashes.
- Inactive-tab clicks restore the last browsing state. Repeated clicks on the active Library or Collections tab return to its home.
- Keep scroll offsets independent of hidden viewport changes and suspend inactive artwork/marquees. Run Tests/run_navigation19.sh for navigation and scroll changes.

## v4.0.21 source metadata and lyric sizes

- Only explicit metadata editor saves write source media. Automatic metadata matching remains library-only. Never test source edits against user media.
- Preserve the original in a verified local backup before committing a source rename. Do not put full media backups inside the local user data root.
- Keep sidebar, windowed and fullscreen lyric size preferences independent. Run Tests/run_release21.sh for source tagging, rename, import sorting, drop handling and lyric size changes.

## v4.0.22 retained video and native icon

- Keep the video AVPlayerView mounted across tab navigation. Page selection must not detach the player or replace its item.
- Use the Icon Composer AppIcon.icon resource and system icon rendering; do not restore runtime PNG icon overrides.
- Keep the declarative Appearance menu and synchronously hide the duplicate system View menu; do not rename it asynchronously.
- Run Tests/run_release22.sh for video routing, toolbar title sizing and menu policy changes.

## v4.0.23 local data and menu/editor input

- No iCloud backup, recovery, polling, or exit synchronization. Preserve existing local data and leave prior cloud backup files untouched.
- Theme accent follows artwork automatically; legacy themeColorName must not override it.
- Retain the AVPlayer, item and native video view during repeat-one playback.
- Metadata sheets own text input; transport shortcuts must not consume editing keys. Keep native menu content stable during tracking.
- Run Tests/run_release23.sh for editor input/playback, repeated EOF rendering, cover import, menu tracking and preference policy.

## v4.0.24 focus invalidation

- Keep collection FocusedValue subscriptions inside CollectionToolbarControls, not ContentView. Library selection/focus must not invalidate the whole window toolbar.
- Menu tracking must not be an ObservedObject dependency of ContentView. Only the playing-page controls consume the deduplicated hold publisher.
- Run Tests/run_release24.sh and the v4.0.23 baseline comparison when changing focus/toolbar dependencies.
