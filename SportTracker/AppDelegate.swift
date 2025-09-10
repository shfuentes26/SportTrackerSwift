//
//  AppDelegate.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 9/10/25.
//
import UIKit
import FirebaseCore

final class AppDelegate: NSObject, UIApplicationDelegate {

  // Bloqueo de orientación (cámbialo cuando lo necesites)
  static var orientationLock: UIInterfaceOrientationMask = .all

  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    FirebaseApp.configure()
    return true
  }

  func application(_ application: UIApplication,
                   supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
    AppDelegate.orientationLock
  }
}
