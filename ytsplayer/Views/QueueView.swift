import SwiftUI

struct QueueView: View {
    @EnvironmentObject var playbackVM: PlaybackViewModel
    @State private var draggedItem: QueueItem?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Up Next")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Text("\(max(0, playbackVM.queue.count - playbackVM.queueIndex - 1)) Tracks")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            // Removed solid background to let the native popover glass shine through
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            if playbackVM.queue.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Queue is empty")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(playbackVM.queue.enumerated()), id: \.element.id) { index, queueItem in
                            let track = queueItem.track
                            let isPlaying = (index == playbackVM.queueIndex)
                            let isPast = (index < playbackVM.queueIndex)
                            
                            TrackRow(
                                index: index + 1,
                                track: track,
                                isPlaying: isPlaying,
                                onPlayNext: { playbackVM.playNext(track) },
                                onEnqueue: { playbackVM.enqueue(track) },
                                showDragHandle: true,
                                enableExportDrag: false,
                                onDragStarted: {
                                    self.draggedItem = queueItem
                                    return NSItemProvider(object: queueItem.id.uuidString as NSString)
                                }
                            )
                                .opacity(isPast ? 0.4 : 1.0)
                                .onTapGesture {
                                    // Map QueueItems back to tracks for play()
                                    playbackVM.play(track: track, queue: playbackVM.queue.map { $0.track }, startIndex: index)
                                }
                                .onDrop(of: [.plainText], delegate: QueueDropDelegate(item: queueItem, items: playbackVM.queue, playbackVM: playbackVM, draggedItem: $draggedItem))
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                }
            }
        }
        .frame(minWidth: 300, idealWidth: 400, minHeight: 400)
        .liquidGlassBackground(cornerRadius: 16)
    }
}

struct QueueDropDelegate: DropDelegate {
    let item: QueueItem
    let items: [QueueItem]
    let playbackVM: PlaybackViewModel
    @Binding var draggedItem: QueueItem?

    func dropEntered(info: DropInfo) {
        guard let draggedItem,
              draggedItem.id != item.id,
              let from = items.firstIndex(where: { $0.id == draggedItem.id }),
              let to = items.firstIndex(where: { $0.id == item.id }) else { return }

        if from != to {
            withAnimation(.default) {
                playbackVM.moveInQueue(from: IndexSet(integer: from), to: to > from ? to + 1 : to)
            }
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        self.draggedItem = nil
        return true
    }
}
