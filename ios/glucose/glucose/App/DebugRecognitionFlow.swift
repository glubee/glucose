#if DEBUG
import SwiftUI

struct DebugRecognitionFlow: View {
    @State private var showsRecognition = true
    @State private var photoId = UUID()

    var body: some View {
        RootTabView()
            .sheet(isPresented: $showsRecognition) {
                NavigationStack {
                    RecognitionResultView(photoId: photoId, context: .meal) {
                        showsRecognition = false
                    }
                }
            }
    }
}
#endif
