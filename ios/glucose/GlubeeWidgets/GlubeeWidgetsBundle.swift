//
//  GlubeeWidgetsBundle.swift
//  GlubeeWidgets
//
//  Created by DavePark on 10/27/26.
//

import SwiftUI
import WidgetKit

@main
struct GlubeeWidgetsBundle: WidgetBundle {
    var body: some Widget {
        QuickActionsWidget()
        CaptureWidget()
        InsulinWidget()
        StreakLockWidget()
    }
}
