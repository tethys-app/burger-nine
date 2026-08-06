//
//  BurgerNineApp.swift
//  BurgerNine
//
//  Created by abel on 10/06/2026.
//

import SwiftUI
import Stripe

@main
struct BurgerNineApp: App {
    init() { MenuDiag.sessionStart() }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
                .onOpenURL { url in
                    _ = StripeAPI.handleURLCallback(with: url)
                }
        }
    }
}
