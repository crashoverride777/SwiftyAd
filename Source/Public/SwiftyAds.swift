//    The MIT License (MIT)
//
//    Copyright (c) 2015-2020 Dominik Ringler
//
//    Permission is hereby granted, free of charge, to any person obtaining a copy
//    of this software and associated documentation files (the "Software"), to deal
//    in the Software without restriction, including without limitation the rights
//    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//    copies of the Software, and to permit persons to whom the Software is
//    furnished to do so, subject to the following conditions:
//
//    The above copyright notice and this permission notice shall be included in all
//    copies or substantial portions of the Software.
//
//    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//    SOFTWARE.

import GoogleMobileAds

/**
 SwiftyAds
 
 A concret class implementation of SwiftAdsType to display ads from AdMob.
 */
public final class SwiftyAds: NSObject {
    
    // MARK: - Static Properties
    
    /// The shared instance of SwiftyAds
    public static let shared = SwiftyAds()
    
    // MARK: - Properties
    
    private let mobileAds: GADMobileAds
    private let intervalTracker: SwiftyAdsIntervalTrackerType
    
    private var bannerAd: SwiftyAdsBannerType!
    private var interstitialAd: SwiftyAdsInterstitialType!
    private var rewardedAd: SwiftyAdsRewardedType!
    private var consentManager: SwiftyAdsConsentManagerType!
    private var isDisabled = false
        
    // MARK: - Computed Properties
    
    private var requestBuilder: SwiftyAdsRequestBuilderType {
        SwiftyAdsRequestBuilder(
            isGDPRRequired: consentManager.isInEEA,
            isNonPersonalizedOnly: consentManager.status == .nonPersonalized,
            isTaggedForUnderAgeOfConsent: consentManager.isTaggedForUnderAgeOfConsent
        )
    }
    
    // MARK: - Init
    
    // Shared instance
    private override init() {
        mobileAds = .sharedInstance()
        intervalTracker = SwiftyAdsIntervalTracker()
        super.init()
        
    }
    
    // Testing
    init(mobileAds: GADMobileAds,
         bannerAd: SwiftyAdsBannerType,
         interstitialAd: SwiftyAdsInterstitialType,
         rewardedAd: SwiftyAdsRewardedType,
         consentManager: SwiftyAdsConsentManagerType,
         intervalTracker: SwiftyAdsIntervalTrackerType) {
        self.mobileAds = mobileAds
        self.bannerAd = bannerAd
        self.interstitialAd = interstitialAd
        self.rewardedAd = rewardedAd
        self.consentManager = consentManager
        self.intervalTracker = intervalTracker
    }
}

// MARK: - SwiftyAdType

extension SwiftyAds: SwiftyAdsType {
    
    /// Check if user has consent e.g to hide rewarded video button
    public var hasConsent: Bool {
        consentManager.hasConsent
    }
     
    /// Check if we must ask for consent e.g to hide change consent button in apps settings menu (required GDPR requirement)
    public var isRequiredToAskForConsent: Bool {
        consentManager.isRequiredToAskForConsent
    }
     
    /// Check if interstitial video is ready (e.g to show alternative ad like an in house ad)
    /// Will try to reload an ad if it returns false.
    public var isInterstitialReady: Bool {
        interstitialAd.isReady
    }
     
    /// Check if reward video is ready (e.g to hide/disable the rewarded video button)
    /// Will try to reload an ad if it returns false.
    public var isRewardedVideoReady: Bool {
        rewardedAd.isReady
    }
    
    /// Setup swift ad
    ///
    /// - parameter viewController: The view controller that will present the consent alert if needed.
    /// - parameter mode: Set the mode of ads, production or debug.
    /// - parameter consentStyle: The style of the consent alert.
    /// - parameter consentStatusDidChange: A handler that will fire everytime the consent status has changed.
    /// - parameter handler: A handler that will return the current consent status after the consent alert has been dismissed.
    public func setup(with viewController: UIViewController,
                      mode: SwiftyAdsMode,
                      consentStyle: SwiftyAdsConsentStyle,
                      consentStatusDidChange: @escaping (SwiftyAdsConsentStatus) -> Void,
                      handler: @escaping (SwiftyAdsConsentStatus) -> Void) {
        // Update configuration for selected mode
        let configuration: SwiftyAdsConfiguration
        switch mode {
        case .production:
            configuration = .production
        case .debug(let testDeviceIdentifiers):
            configuration = .debug
            mobileAds.requestConfiguration.testDeviceIdentifiers = testDeviceIdentifiers//kGADSimulatorID
        }
        
        // Create ads
        bannerAd = SwiftyAdsBanner(
            notificationCenter: .default,
            adUnitId: configuration.bannerAdUnitId,
            request: ({ [unowned self] in
                self.requestBuilder.build()
            })
        )
        
        interstitialAd = SwiftyAdsInterstitial(
            adUnitId: configuration.interstitialAdUnitId,
            request: ({ [unowned self] in
                self.requestBuilder.build()
            })
        )
        
        rewardedAd = SwiftyAdsRewarded(
            adUnitId: configuration.rewardedVideoAdUnitId,
            request: ({ [unowned self] in
                self.requestBuilder.build()
            })
        )
     
        // Create consent manager and make request
        consentManager = SwiftyAdsConsentManager(
            configuration: configuration,
            consentStyle: consentStyle,
            statusDidChange: consentStatusDidChange
        )
        consentManager.ask(from: viewController, skipAlertIfAlreadyAuthorized: true) { [weak self] status in
            guard let self = self else { return }
            if status.hasConsent {
                if !self.isDisabled {
                    self.interstitialAd.load()
                }
                self.rewardedAd.load()
            }
            
            handler(status)
        }
    }

    /// Ask for consent e.g when consent button is pressed
    ///
    /// - parameter viewController: The view controller that will present the consent form.
    public func askForConsent(from viewController: UIViewController) {
        consentManager.ask(from: viewController, skipAlertIfAlreadyAuthorized: false, handler: nil)
    }
    
    /// Show banner ad
    ///
    /// - parameter viewController: The view controller that will present the ad.
    /// - parameter isAtTop: If set to true the banner will be displayed at the top.
    /// - parameter animationDuration: The duration of the banner to animate on/off screen.
    /// - parameter onOpen: An optional callback when the banner was presented.
    /// - parameter onClose: An optional callback when the banner was dismissed or removed.
    /// - parameter onError: An optional callback when an error has occurred.
    public func showBanner(from viewController: UIViewController,
                           atTop isAtTop: Bool,
                           animationDuration: TimeInterval,
                           onOpen: (() -> Void)?,
                           onClose: (() -> Void)?,
                           onError: ((Error) -> Void)?) {
        guard !isDisabled, hasConsent else {
            return
        }
        
        bannerAd.show(
            from: viewController,
            at: isAtTop ? .top : .bottom,
            isLandscape: UIDevice.current.orientation.isLandscape,
            animationDuration: animationDuration,
            onOpen: onOpen,
            onClose: onClose,
            onError: onError
        )
    }
    
    /// Update banner for orientation change
    ///
    /// - parameter isLandscape: An flag to tell the banner if it should be refreshed for landscape or portrait orientation.
    public func updateBannerForOrientationChange(isLandscape: Bool) {
        bannerAd.refresh(isLandscape: isLandscape)
    }
    
    /// Show interstitial ad
    ///
    /// - parameter viewController: The view controller that will present the ad.
    /// - parameter interval: The interval of when to show the ad, e.g every 4th time the method is called. Set to nil to always show.
    /// - parameter onOpen: An optional callback when the banner was presented.
    /// - parameter onClose: An optional callback when the ad was dismissed.
    /// - parameter onError: An optional callback when an error has occurred.
    public func showInterstitial(from viewController: UIViewController,
                                 withInterval interval: Int?,
                                 onOpen: (() -> Void)?,
                                 onClose: (() -> Void)?,
                                 onError: ((Error) -> Void)?) {
        guard !isDisabled, hasConsent else {
            return
        }
    
        guard intervalTracker.canShow(forInterval: interval) else {
            return
        }
        
        interstitialAd.show(
            from: viewController,
            onOpen: onOpen,
            onClose: onClose,
            onError: onError
        )
    }
    
    /// Show rewarded video ad
    ///
    /// - parameter viewController: The view controller that will present the ad.
    /// - parameter onOpen: An optional callback when the banner was presented.
    /// - parameter onClose: An optional callback when the ad was dismissed.
    /// - parameter onError: An optional callback when an error has occurred.
    /// - parameter onNotReady: An optional callback when the ad was not ready.
    /// - parameter onReward: A callback when the reward has been granted.
    public func showRewardedVideo(from viewController: UIViewController,
                                  onOpen: (() -> Void)?,
                                  onClose: (() -> Void)?,
                                  onError: ((Error) -> Void)?,
                                  onNotReady: (() -> Void)?,
                                  onReward: @escaping (Int) -> Void) {
        guard hasConsent else {
            return
        }
        
        rewardedAd.show(
            from: viewController,
            onOpen: onOpen,
            onClose: onClose,
            onError: onError,
            onNotReady: onNotReady,
            onReward: onReward
        )
    }
    
    /// Remove banner ads
    public func removeBanner() {
        bannerAd.remove()
    }

    /// Disable ads e.g in app purchases
    public func disable() {
        isDisabled = true
        removeBanner()
        interstitialAd.stopLoading()
    }
}
