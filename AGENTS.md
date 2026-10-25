# MyPlayer delivery requirements

- Keep the application bundle named MyPlayer.app, without an Updated or build suffix.
- Preserve the fixed user data directory and existing records when updating.
- Deliver MyPlayer.zip only, without DMG. Run package_app.sh and verify the app signature.
- Playback restoration changes must pass Tests/run_build39.sh. Tests use isolated user data; do not launch against or modify the user's real library for verification.

- Selection updates must not inject/remove row subviews or trigger full-table redraws. Do not use continuous KVO write-back to fight SwiftUI row sizing.
- Keep original artwork on disk with backup and integrity verification; do not retain original cover data as image-cache keys. Run Tests/run_build44.sh for artwork, native marquee or selection changes.

## Next release policy (user instruction, 2026-10-24)

- Starting with the next release, merge this development line into the formal release; do not continue publishing it as Beta.
- Use `vMAJOR.MINOR.PATCH` release naming. The release sequence is `v4.0.18`, `v4.0.19`, `v4.0.20`, and so on. This checkout is `v4.0.20`; the next release must be `v4.0.21`.
- Replace the old parenthesized version display and Beta suffix in the next release. Preserve library/settings data when integrating the existing Beta data into the formal app.
- This instruction does not request changing the already published `v4.0.0-beta.17` GitHub tag or release now.

## v4.0.19 navigation scope

- Preserve the v4.0.18 fullscreen background implementation; Tests/run_navigation19.sh checks protected hashes.
- Inactive-tab clicks restore the last browsing state. Repeated clicks on the active Library or Collections tab return to its home.
- Keep scroll offsets independent of hidden viewport changes and suspend inactive artwork/marquees. Run Tests/run_navigation19.sh for navigation and scroll changes.
