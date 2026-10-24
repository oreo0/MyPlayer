# MyPlayer delivery requirements

- Keep the application bundle named MyPlayer.app, without an Updated or build suffix.
- Preserve the fixed user data directory and existing records when updating.
- Deliver MyPlayer.zip only, without DMG. Run package_app.sh and verify the app signature.
- Playback restoration changes must pass Tests/run_build39.sh. Tests use isolated user data; do not launch against or modify the user's real library for verification.

- Selection updates must not inject/remove row subviews or trigger full-table redraws. Do not use continuous KVO write-back to fight SwiftUI row sizing.
- Keep original artwork on disk with backup and integrity verification; do not retain original cover data as image-cache keys. Run Tests/run_build44.sh for artwork, native marquee or selection changes.
