import SwiftUI
struct TestView: View {
    var body: some View {
        Text("Hello")
            .toolbar {
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }
    }
}
