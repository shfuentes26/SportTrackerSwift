//
//  ScreenTrackingModifier.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 9/10/25.
//
import SwiftUI

struct ScreenTrackingModifier: ViewModifier {
  let name: String
  func body(content: Content) -> some View {
    content
      .onAppear { AnalyticsService.logScreen(name: name) }
  }
}

extension View {
  func trackScreen(_ name: String) -> some View {
    self.modifier(ScreenTrackingModifier(name: name))
  }
}

