//
// UserDefaults+Keys.swift
// SpatialTag
//
// Created by Spatial Tag Team
// Copyright © 2023 Spatial Tag. All rights reserved.
//

import Foundation // iOS 15.0+

/// Enum containing all UserDefaults keys used throughout the application
/// Centralizes key definitions to prevent duplication and typos
public enum UserDefaultsKeys {
    static let hasCompletedOnboarding = "com.spatialtag.userdefaults.hasCompletedOnboarding"
    static let lastKnownLocation = "com.spatialtag.userdefaults.lastKnownLocation"
    static let userStatusLevel = "com.spatialtag.userdefaults.userStatusLevel"
    static let tagVisibilityRadius = "com.spatialtag.userdefaults.tagVisibilityRadius"
    static let isLocationTrackingEnabled = "com.spatialtag.userdefaults.isLocationTrackingEnabled"
    static let pushNotificationsEnabled = "com.spatialtag.userdefaults.pushNotificationsEnabled"
    static let arViewConfiguration = "com.spatialtag.userdefaults.arViewConfiguration"
    static let lastSyncTimestamp = "com.spatialtag.userdefaults.lastSyncTimestamp"
    static let preferredDiscoveryRadius = "com.spatialtag.userdefaults.preferredDiscoveryRadius"
    static let userInteractionPreferences = "com.spatialtag.userdefaults.userInteractionPreferences"
    static let spatialEngineSettings = "com.spatialtag.userdefaults.spatialEngineSettings"
}

// MARK: - UserDefaults Extension
public extension UserDefaults {
    
    /// Indicates whether the user has completed the onboarding process
    var hasCompletedOnboarding: Bool {
        get { bool(forKey: UserDefaultsKeys.hasCompletedOnboarding) }
        set { set(newValue, forKey: UserDefaultsKeys.hasCompletedOnboarding) }
    }
    
    /// The user's last known location as a serialized Data object
    var lastKnownLocation: Data? {
        get { data(forKey: UserDefaultsKeys.lastKnownLocation) }
        set { set(newValue, forKey: UserDefaultsKeys.lastKnownLocation) }
    }
    
    /// The user's current status level in the application
    var userStatusLevel: String {
        get { string(forKey: UserDefaultsKeys.userStatusLevel) ?? "regular" }
        set { set(newValue, forKey: UserDefaultsKeys.userStatusLevel) }
    }
    
    /// The user's preferred visibility radius for tags in meters
    var tagVisibilityRadius: Double {
        get { double(forKey: UserDefaultsKeys.tagVisibilityRadius) }
        set { set(newValue, forKey: UserDefaultsKeys.tagVisibilityRadius) }
    }
    
    /// Indicates whether location tracking is enabled
    var isLocationTrackingEnabled: Bool {
        get { bool(forKey: UserDefaultsKeys.isLocationTrackingEnabled) }
        set { set(newValue, forKey: UserDefaultsKeys.isLocationTrackingEnabled) }
    }
    
    /// Indicates whether push notifications are enabled
    var pushNotificationsEnabled: Bool {
        get { bool(forKey: UserDefaultsKeys.pushNotificationsEnabled) }
        set { set(newValue, forKey: UserDefaultsKeys.pushNotificationsEnabled) }
    }
    
    /// AR view configuration settings as a serialized Data object
    var arViewConfiguration: Data? {
        get { data(forKey: UserDefaultsKeys.arViewConfiguration) }
        set { set(newValue, forKey: UserDefaultsKeys.arViewConfiguration) }
    }
    
    /// Timestamp of the last successful data sync
    var lastSyncTimestamp: Date? {
        get { object(forKey: UserDefaultsKeys.lastSyncTimestamp) as? Date }
        set { set(newValue, forKey: UserDefaultsKeys.lastSyncTimestamp) }
    }
    
    /// The user's preferred discovery radius for finding other users in meters
    var preferredDiscoveryRadius: Double {
        get { double(forKey: UserDefaultsKeys.preferredDiscoveryRadius) }
        set { set(newValue, forKey: UserDefaultsKeys.preferredDiscoveryRadius) }
    }
    
    /// User interaction preferences as a serialized Data object
    var userInteractionPreferences: Data? {
        get { data(forKey: UserDefaultsKeys.userInteractionPreferences) }
        set { set(newValue, forKey: UserDefaultsKeys.userInteractionPreferences) }
    }
    
    /// Spatial engine configuration settings as a serialized Data object
    var spatialEngineSettings: Data? {
        get { data(forKey: UserDefaultsKeys.spatialEngineSettings) }
        set { set(newValue, forKey: UserDefaultsKeys.spatialEngineSettings) }
    }
    
    /// Resets all app-specific user defaults to their default values
    func resetAppDefaults() {
        removeObject(forKey: UserDefaultsKeys.hasCompletedOnboarding)
        removeObject(forKey: UserDefaultsKeys.lastKnownLocation)
        removeObject(forKey: UserDefaultsKeys.userStatusLevel)
        removeObject(forKey: UserDefaultsKeys.tagVisibilityRadius)
        removeObject(forKey: UserDefaultsKeys.isLocationTrackingEnabled)
        removeObject(forKey: UserDefaultsKeys.pushNotificationsEnabled)
        removeObject(forKey: UserDefaultsKeys.arViewConfiguration)
        removeObject(forKey: UserDefaultsKeys.lastSyncTimestamp)
        removeObject(forKey: UserDefaultsKeys.preferredDiscoveryRadius)
        removeObject(forKey: UserDefaultsKeys.userInteractionPreferences)
        removeObject(forKey: UserDefaultsKeys.spatialEngineSettings)
    }
}