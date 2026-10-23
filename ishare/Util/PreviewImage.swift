//
//  PreviewImage.swift
//  ishare
//
//  Created by Adrian Castro on 30.08.23.
//

import Combine
import Foundation
import SwiftUI

enum ImagePhase {
    case empty
    case success(NSImage)
    case failure
}

@MainActor
class ImageLoader: ObservableObject {
    @Published var phase: ImagePhase = .empty

    func load(url: URL) async {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 100
        let session = URLSession(configuration: config)

        do {
            let (data, _) = try await session.data(from: url)
            if let uiImage = NSImage(data: data) {
                self.phase = .success(uiImage)
            } else {
                self.phase = .failure
            }
        } catch {
            self.phase = .failure
        }
    }
}

struct PreviewImage<Content: View>: View {
    @StateObject private var loader = ImageLoader()
    let url: URL?
    let content: (ImagePhase) -> Content

    init(url: URL?, @ViewBuilder content: @escaping (ImagePhase) -> Content) {
        self.url = url
        self.content = content
    }

    var body: some View {
        content(loader.phase)
            .task {
                if let url = url {
                    await loader.load(url: url)
                }
            }
    }
}
