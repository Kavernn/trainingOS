# TrainingOS — Native SwiftUI App

## Setup

1. Open Xcode
2. File → New → Project → iOS App (SwiftUI)
3. Product Name: TrainingOS
4. Bundle ID: com.kavernntrainingos.app
5. Delete the default ContentView.swift
6. Drag all files from this directory into the Xcode project
7. Make sure "Copy items if needed" is checked
8. Build & Run on your device

## Structure

TrainingOSApp.swift      — Entry point
ContentView.swift        — TabView navigation
Models/APIModels.swift   — Codable data models
Services/APIService.swift — Network layer (calls Vercel API)
Views/
  Dashboard/   — Home screen
  Seance/      — Workout logging (WIP)
  Historique/  — Session history
  Timer/       — Interval timer (fully native)
  Profile/     — User profile
Utilities/Extensions.swift — Color(hex:), DateFormatter
