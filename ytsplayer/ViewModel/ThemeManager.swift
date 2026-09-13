// ThemeManager.swift
// ytsplayer

import SwiftUI
import Combine

enum AppThemeMode: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    
    var id: String { self.rawValue }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AppAccentColor: String, CaseIterable, Identifiable {
    case purple = "Deep Purple"
    case blue = "Ocean Blue"
    case pink = "Neon Pink"
    case green = "Emerald Green"
    case orange = "Sunset Orange"
    
    var id: String { self.rawValue }
    
    var color: Color {
        switch self {
        case .purple: return .purple
        case .blue: return .blue
        case .pink: return .pink
        case .green: return .green
        case .orange: return .orange
        }
    }
}

enum GlassIntensity: String, CaseIterable, Identifiable {
    case ultraThin = "Ultra Thin"
    case thin = "Thin"
    case regular = "Regular"
    case thick = "Thick"
    
    var id: String { self.rawValue }
    
    var material: Material {
        switch self {
        case .ultraThin: return .ultraThinMaterial
        case .thin: return .thinMaterial
        case .regular: return .regularMaterial
        case .thick: return .thickMaterial
        }
    }
}

class ThemeManager: ObservableObject {
    @AppStorage("appThemeMode") private var storedThemeMode: AppThemeMode = .dark
    @AppStorage("appAccentColor") private var storedAccentColor: AppAccentColor = .purple
    @AppStorage("glassIntensity") private var storedGlassIntensity: GlassIntensity = .thin
    
    @Published var themeMode: AppThemeMode {
        didSet { storedThemeMode = themeMode }
    }
    
    @Published var accentColor: AppAccentColor {
        didSet { storedAccentColor = accentColor }
    }
    
    @Published var glassIntensity: GlassIntensity {
        didSet { storedGlassIntensity = glassIntensity }
    }
    
    init() {
        // Initialize published properties from AppStorage
        let defaultTheme: AppThemeMode = UserDefaults.standard.string(forKey: "appThemeMode").flatMap { AppThemeMode(rawValue: $0) } ?? .dark
        let defaultAccent: AppAccentColor = UserDefaults.standard.string(forKey: "appAccentColor").flatMap { AppAccentColor(rawValue: $0) } ?? .purple
        let defaultGlass: GlassIntensity = UserDefaults.standard.string(forKey: "glassIntensity").flatMap { GlassIntensity(rawValue: $0) } ?? .thin
        
        self.themeMode = defaultTheme
        self.accentColor = defaultAccent
        self.glassIntensity = defaultGlass
    }
}
