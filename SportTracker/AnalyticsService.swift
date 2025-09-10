//
//  AnalyticsService.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 9/10/25.
//
import Foundation
import FirebaseAnalytics

enum STEvent: String {
  // Sesiones/pantallas
  case screenView = "screen_view" // estándar de Firebase
  // Core app
  case trainingSaved = "training_saved"
  case trainingDeleted = "training_deleted"
  case exerciseCreated = "exercise_created"
  case exerciseEdited = "exercise_edited"
  // Health / Watch
  case healthImport = "health_import"
  case healthExport = "health_export"
  case watchTrainingSaved = "watch_training_saved"
  // Insights / Heatmap
  case heatmapOpened = "heatmap_opened"
  case gymInsightsOpened = "gym_insights_opened"
  case prAchieved = "pr_achieved"
  // Gamificación
  case pointsEarned = "points_earned"
}

enum STParam {
  static let trainingType   = "training_type"    // "running" | "gym"
  static let exerciseId     = "exercise_id"      // uuid o slug
  static let muscleGroup    = "muscle_group"     // "chest", "back", etc.
  static let weightKg       = "weight_kg"        // Double
  static let reps           = "reps"             // Int
  static let distanceKm     = "distance_km"      // Double
  static let durationSec    = "duration_sec"     // Int
  static let points         = "points"           // Int
  static let source         = "source"           // "manual" | "health" | "watch"
  static let prType         = "pr_type"          // "1RM" | "5K" | etc.
}

enum STUserProperty {
  static let usesWatch      = "uses_watch"       // "true"/"false"
  static let units          = "units"            // "metric" | "imperial"
  static let iCloudEnabled  = "icloud_enabled"   // "true"/"false"
  static let appTheme       = "app_theme"        // "light" | "dark" | "system"
}

enum AnalyticsService {
  // MARK: - Log genérico
  static func log(_ event: STEvent, _ params: [String: Any]? = nil) {
    Analytics.logEvent(event.rawValue, parameters: params)
  }

  // MARK: - Screen view (SwiftUI)
  static func logScreen(name: String, class screenClass: String = "SwiftUIScreen") {
    Analytics.logEvent(AnalyticsEventScreenView, parameters: [
      AnalyticsParameterScreenName: name,
      AnalyticsParameterScreenClass: screenClass
    ])
  }

  // MARK: - User properties
  static func setUserProperty(_ value: String?, for key: String) {
    Analytics.setUserProperty(value, forName: key)
  }

  // MARK: - Consent / Privacy
  static func setAnalyticsEnabled(_ enabled: Bool) {
    Analytics.setAnalyticsCollectionEnabled(enabled)
  }

  static func setConsent(analytics: Bool) {
    Analytics.setConsent([
      .analyticsStorage: analytics ? .granted : .denied,
      .adStorage: .denied // por defecto, sin ads/IDFA
    ])
  }
}

