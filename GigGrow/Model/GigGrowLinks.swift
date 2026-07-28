//
//  GigGrowLinks.swift
//  GigGrow
//
//  Public destinations shared by the app and its App Store listing.
//
//  Apple requires a publicly reachable privacy policy and a support page in
//  the listing metadata, and a reviewer checks that what the app says matches
//  what the page says. Keeping both in one file is how they stay the same
//  text: the in-app privacy screen and the hosted policy describe the same
//  app, and a change to one is meant to be a change to both.
//
//  Force-unwrapped on purpose. These are string literals that either parse at
//  every launch or at none, so a crash on the first run of a broken edit is
//  better than a Settings row that silently does nothing.
//

import Foundation

enum GigGrowLinks {
    static let appStore = URL(string: "https://apps.apple.com/app/id6794992895")!
    static let writeReview = URL(string: "https://apps.apple.com/app/id6794992895?action=write-review")!
    static let privacyPolicy = URL(string: "https://mystoganztv.github.io/giggrow/privacy.html")!
    static let support = URL(string: "https://mystoganztv.github.io/giggrow/")!
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let refunds = URL(string: "https://support.apple.com/en-us/118223")!
}
