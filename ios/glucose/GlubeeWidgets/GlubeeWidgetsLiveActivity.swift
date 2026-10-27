//
//  GlubeeWidgetsLiveActivity.swift
//  GlubeeWidgets
//
//  Created by DavePark on 10/27/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct GlubeeWidgetsAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct GlubeeWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GlubeeWidgetsAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension GlubeeWidgetsAttributes {
    fileprivate static var preview: GlubeeWidgetsAttributes {
        GlubeeWidgetsAttributes(name: "World")
    }
}

extension GlubeeWidgetsAttributes.ContentState {
    fileprivate static var smiley: GlubeeWidgetsAttributes.ContentState {
        GlubeeWidgetsAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: GlubeeWidgetsAttributes.ContentState {
         GlubeeWidgetsAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: GlubeeWidgetsAttributes.preview) {
   GlubeeWidgetsLiveActivity()
} contentStates: {
    GlubeeWidgetsAttributes.ContentState.smiley
    GlubeeWidgetsAttributes.ContentState.starEyes
}
