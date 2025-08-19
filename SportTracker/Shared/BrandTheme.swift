//
//  BrandTheme.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/19/25.
//
import SwiftUI

// Usa el color del Asset "BrandGreen"
extension Color {
    static let brand = Color("BrandGreen")
}

private struct BrandNavBar: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackground(.visible, for: .navigationBar)       // controla visibilidad
            .toolbarBackground(Color.brand, for: .navigationBar)    // <-- especifica Color
            .toolbarColorScheme(.dark, for: .navigationBar)         // texto/iconos en claro
    }
}

extension View {
    func brandNavBar() -> some View { modifier(BrandNavBar()) }
}


extension View {
    /// Deja un hueco bajo la barra de navegación (por defecto 8pt)
    func brandHeaderSpacer(_ height: CGFloat = 8) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: height)
        }
    }
}
