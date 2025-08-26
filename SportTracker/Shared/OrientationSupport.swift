//
//  OrientationSupport.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/25/25.
//
import SwiftUI

final class OrientationLockDelegate: NSObject, UIApplicationDelegate {
    static var mask: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.mask
    }

    static func allowPortraitAndLandscape() {
        Self.mask = [.portrait, .landscapeLeft, .landscapeRight]
        // No forzamos la rotación; solo dejamos que ocurra si el usuario gira
        UIViewController.attemptRotationToDeviceOrientation()
    }

    static func lockPortrait() {
        Self.mask = .portrait
        UIViewController.attemptRotationToDeviceOrientation()
    }
}

