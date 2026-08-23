import SwiftUI

struct QueueView: View {
    @EnvironmentObject var playbackVM: PlaybackViewModel
    @State private var draggedItem: TrackViewModel?
    
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
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
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
                        ForEach(Array(playbackVM.queue.enumerated()), id: \.element.id) { index, track in
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
                                    self.draggedItem = track
                                    return NSItemProvider(object: track.id.description as NSString)
                                }
                            )
                                .opacity(isPast ? 0.4 : 1.0)
                                .onTapGesture {
                                    playbackVM.play(track: track, queue: playbackVM.queue, startIndex: index)
                                }
                                .onDrop(of: [.plainText], delegate: QueueDropDelegate(item: track, items: playbackVM.queue, playbackVM: playbackVM, draggedItem: $draggedItem))
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                }
            }
        }
        .frame(minWidth: 400, idealWidth: 450, minHeight: 500)
    }
}

struct QueueDropDelegate: DropDelegate {
    let item: TrackViewModel
    let items: [TrackViewModel]
    let playbackVM: PlaybackViewModel
    @Binding var draggedItem: TrackViewModel?

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
