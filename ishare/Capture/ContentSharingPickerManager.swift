//
//  ContentSharingPickerManager.swift
//  ishare
//
//  Created by Adrian Castro on 20.01.24.
//

import Defaults
import Foundation
import ScreenCaptureKit

actor CallbackStore {
    private var contentSelected: (@Sendable (SCContentFilter, SCStream?) -> Void)?
    private var contentSelectionFailed: (@Sendable (any Error) -> Void)?
    private var contentSelectionCancelled: (@Sendable (SCStream?) -> Void)?

    func setContentSelectedCallback(_ callback: @Sendable @escaping (SCContentFilter, SCStream?) -> Void) {
        contentSelected = callback
    }

    func setContentSelectionFailedCallback(_ callback: @Sendable @escaping (any Error) -> Void) {
        contentSelectionFailed = callback
    }

    func setContentSelectionCancelledCallback(_ callback: @Sendable @escaping (SCStream?) -> Void) {
        contentSelectionCancelled = callback
    }

    func getContentSelectedCallback() -> (@Sendable (SCContentFilter, SCStream?) -> Void)? {
        contentSelected
    }

    func getContentSelectionFailedCallback() -> (@Sendable (any Error) -> Void)? {
        contentSelectionFailed
    }

    func getContentSelectionCancelledCallback() -> (@Sendable (SCStream?) -> Void)? {
        contentSelectionCancelled
    }
}

@MainActor
class ContentSharingPickerManager: NSObject, SCContentSharingPickerObserver {
    static let shared = ContentSharingPickerManager()
    private let picker = SCContentSharingPicker.shared
    private let callbackStore = CallbackStore()

    func setContentSelectedCallback(_ callback: @Sendable @escaping (SCContentFilter, SCStream?) -> Void) async {
        await callbackStore.setContentSelectedCallback(callback)
    }

    func setContentSelectionFailedCallback(_ callback: @Sendable @escaping (any Error) -> Void) async {
        await callbackStore.setContentSelectionFailedCallback(callback)
    }

    func setContentSelectionCancelledCallback(_ callback: @Sendable @escaping (SCStream?) -> Void) async {
        await callbackStore.setContentSelectionCancelledCallback(callback)
    }

    @Default(.ignoredBundleIdentifiers) var ignoredBundleIdentifiers

    func setupPicker(stream: SCStream) {
        picker.add(self)
        picker.isActive = true

        var pickerConfig = SCContentSharingPickerConfiguration()
        pickerConfig.excludedBundleIDs = ignoredBundleIdentifiers
        pickerConfig.allowsChangingSelectedContent = true

        picker.setConfiguration(pickerConfig, for: stream)
    }

    func showPicker() {
        picker.present()
    }

    func deactivatePicker() {
        picker.isActive = false
        picker.remove(self)
    }

    nonisolated func contentSharingPicker(_: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        struct SendableParams: @unchecked Sendable {
            let filter: SCContentFilter
            let stream: SCStream?
        }
        let params = SendableParams(filter: filter, stream: stream)

        Task { @MainActor in
            if let callback = await ContentSharingPickerManager.shared.callbackStore.getContentSelectedCallback() {
                callback(params.filter, params.stream)
            }
        }
    }

    nonisolated func contentSharingPicker(_: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in
            self.deactivatePicker()
        }
        
        struct SendableParams: @unchecked Sendable {
            let stream: SCStream?
        }
        let params = SendableParams(stream: stream)

        Task { @MainActor in
            if let callback = await ContentSharingPickerManager.shared.callbackStore.getContentSelectionCancelledCallback() {
                callback(params.stream)
            }
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        struct SendableParams: @unchecked Sendable {
            let error: any Error
        }
        let params = SendableParams(error: error)

        Task { @MainActor in
            if let callback = await ContentSharingPickerManager.shared.callbackStore.getContentSelectionFailedCallback() {
                callback(params.error)
            }
        }
    }
}

