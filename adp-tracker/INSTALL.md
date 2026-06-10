# TimeGuard · ADP Companion — Install on Android

## What it is
A Progressive Web App (PWA) that tracks your location-based clock-in/out times,
giving you a verified record to compare against ADP when punches are missed.

## Install on Android (Chrome)
1. Open **Chrome** on your Android phone
2. Navigate to the app URL (GitHub Pages link once deployed)
3. Tap the **three-dot menu (⋮)** → **"Add to Home screen"**
4. Tap **Add** — the TimeGuard icon appears on your home screen
5. Open it — it runs like a native app, full-screen, no browser chrome

## Features
- **Dashboard** — Clock In / Clock Out buttons, today's in/out times, hours worked today + this week, mini map
- **Map** — Full map showing your current position, work location marker (🏢), and geofence boundary circle
- **History** — Full editable record of every punch. Add missing entries, edit times, delete mistakes. Filter by week / month. Export to CSV or text report for ADP comparison.
- **Settings** — Set your work location (GPS or address search), configure geofence radius (50–600m), enable/disable auto clock-in/out when you enter/leave the geofence

## ADP Comparison Workflow
1. At end of pay period, go to **History → Export CSV**
2. Open the CSV in Excel / Google Sheets
3. Compare against your ADP time card side-by-side
4. Any row in ADP that's missing or wrong = your GPS record is the proof

## Notes
- Location data stays **entirely on your phone** (localStorage) — nothing is uploaded
- The app works offline once loaded (Service Worker caches the shell)
- For auto clock-in/out to work, keep Chrome running in the background and grant "Allow all the time" location permission
- Manual Clock In/Out always works regardless of location
