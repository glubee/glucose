//
//  GlubeeWidgetsBundle.swift
//  GlubeeWidgets
//
//  Created by DavePark on 10/27/26.
//

import WidgetKit
import SwiftUI

@main
struct GlubeeWidgetsBundle: WidgetBundle {
    var body: some Widget {
        GlubeeWidgets()
        GlubeeWidgetsControl()
        GlubeeWidgetsLiveActivity()
    }
}
