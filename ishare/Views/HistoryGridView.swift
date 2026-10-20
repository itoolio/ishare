//
//  HistoryGridView.swift
//  ishare
//
//  Created by Adrian Castro on 29.12.23.
//

import Alamofire
import BezelNotification
import Defaults
import Foundation
import SwiftUI

struct HistoryGridView: View {
    @Default(.uploadHistory) var uploadHistory
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: .infinity), spacing: 3)], spacing: 3) {
                ForEach(uploadHistory, id: \.self) { item in
                    // Use regular context menu directly
                    itemView(for: item)
                        .frame(width: 100, height: 100)
                        .contextMenu {
                            Button("Copy URL".localized()) {
                                copyURL(item)
                            }
                            Button("Open in Browser".localized()) {
                                openInBrowser(item)
                            }
                            Button("Delete".localized()) {
                                deleteItem(item)
                            }
                        }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
    
    @ViewBuilder
    private func itemView(for item: HistoryItem) -> some View {
        if let urlStr = item.fileUrl, 
           let url = URL(string: urlStr), 
           url.pathExtension.lowercased() == "mp4" || url.pathExtension.lowercased() == "mov" {
            VideoThumbnailView(url: url)
        } else {
            HistoryItemView(urlString: item.fileUrl ?? "")
        }
    }
    
    private func copyURL(_ item: HistoryItem) {
        NSPasteboard.general.declareTypes([.string], owner: nil)
        NSPasteboard.general.setString(item.fileUrl ?? "", forType: .string)
        BezelNotification.show(messageText: "Copied URL".localized(), icon: ToastIcon)
    }
    
    private func openInBrowser(_ item: HistoryItem) {
        if let url = URL(string: item.fileUrl ?? "") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func deleteItem(_ item: HistoryItem) {
        Task { @MainActor in
            do {
                try await UploadCoordinator.delete(item)
            } catch {
                NSLog("Deletion error: %@", error.localizedDescription)
            }
            uploadHistory.removeAll { $0 == item }
            BezelNotification.show(messageText: "Deleted".localized(), icon: ToastIcon)
        }
    }
}

struct VideoThumbnailView: View {
    var url: URL

    var body: some View {
        Image(systemName: "video")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 100, height: 100)
    }
}

struct HistoryItemView: View {
    var urlString: String

    var body: some View {
        if let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
                image.resizable()
            } placeholder: {
                ProgressView()
            }
            .aspectRatio(contentMode: .fit)
            .frame(width: 100, height: 100)
        } else {
            Image(systemName: "photo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
        }
    }
}
