import SwiftUI

struct TestTrack: Identifiable {
    let id = UUID()
    let title: String
    let artist: String?
}

struct TestTable: View {
    let tracks = [TestTrack(title: "A", artist: "B")]
    @State private var sortOrder = [KeyPathComparator(\TestTrack.title)]
    
    var body: some View {
        Table(tracks, sortOrder: $sortOrder) {
            TableColumn("Title", value: \.title)
            TableColumn("Artist", value: \.artist)
        }
    }
}
