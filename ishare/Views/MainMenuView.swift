//
//  MainMenuView.swift
//  ishare
//
//  Created by Adrian Castro on 12.07.23.
//

import BezelNotification
import Defaults
import ScreenCaptureKit
import SettingsAccess
import SwiftUI
import UniformTypeIdentifiers

#if canImport(Sparkle)
	import Sparkle
#endif

struct MainMenuView: View {
	@EnvironmentObject var localizableManager: LocalizableManager

	@Default(.copyToClipboard) var copyToClipboard
	@Default(.openInFinder) var openInFinder
	@Default(.saveToDisk) var saveToDisk
	@Default(.uploadMedia) var uploadMedia
	@Default(.uploadType) var uploadType
	@Default(.activeCustomUploader) var activeCustomUploader
	@Default(.savedCustomUploaders) var savedCustomUploaders
	@Default(.uploadDestination) var uploadDestination
	@Default(.builtInShare) var builtInShare
	@Default(.uploadHistory) var uploadHistory

	var body: some View {
		VStack {
			Menu {
				Button {
					Task {
						await captureScreen(type: .REGION)
					}
				} label: {
					Image(systemName: "uiwindow.split.2x1")
					Text("Capture Region".localized())
				}.globalKeyboardShortcut(.captureRegion)

				Button {
					Task {
						await captureScreen(type: .WINDOW)
					}
				} label: {
					Image(systemName: "macwindow.on.rectangle")
					Text("Capture Window".localized())
				}.globalKeyboardShortcut(.captureWindow)

				ForEach(NSScreen.screens.indices, id: \.self) { index in
					let screen = NSScreen.screens[index]
					let screenName: String? = screen.localizedName
					Button {
						Task {
							await captureScreen(type: .SCREEN, display: index + 1)
						}
					} label: {
						Image(systemName: "macwindow")
						Text("Capture \(screenName ?? "Screen")".localized())
					}.globalKeyboardShortcut(index == 0 ? .captureScreen : .noKeybind)
				}
			} label: {
				Image(systemName: "photo.on.rectangle.angled")
				Text("Capture".localized())
			}

			Button {
				recordScreen(gif: false)
			} label: {
				Image(systemName: "menubar.dock.rectangle.badge.record")
				Text("Record".localized())
			}.globalKeyboardShortcut(.recordScreen).disabled(
				AppDelegate.shared.screenRecorder.isRunning)

			Button {
				recordScreen(gif: true)
			} label: {
				Image(systemName: "photo.stack")
				Text("Record GIF".localized())
			}.globalKeyboardShortcut(.recordGif).disabled(
				AppDelegate.shared.screenRecorder.isRunning)
		}
		VStack {
			Menu {
				Toggle(isOn: $copyToClipboard) {
					Image(systemName: "clipboard")
					Text("Copy to Clipboard".localized())
				}.toggleStyle(.checkbox)

				Toggle(isOn: $saveToDisk) {
					Image(systemName: "internaldrive")
					Text("Save to Disk".localized())
				}
				.toggleStyle(.checkbox)
				.onChange(of: saveToDisk) {
					if !saveToDisk {
						openInFinder = false
					}
				}

				Toggle(isOn: $openInFinder) {
					Image(systemName: "folder")
					Text("Open in Finder".localized())
				}
				.toggleStyle(.checkbox)
				.disabled(!saveToDisk)

				Toggle(isOn: $uploadMedia) {
					Image(systemName: "icloud.and.arrow.up")
					Text("Upload Media".localized())
				}.toggleStyle(.checkbox)

				Divider().frame(height: 1).foregroundColor(Color.gray.opacity(0.5))

				Toggle(isOn: $builtInShare.airdrop) {
					Image(nsImage: airdropIcon ?? NSImage())
					Text("AirDrop".localized())
				}.toggleStyle(.checkbox)

				Toggle(isOn: $builtInShare.photos) {
					Image(nsImage: icon(forAppWithName: "com.apple.Photos") ?? NSImage())
					Text("Photos".localized())
				}.toggleStyle(.checkbox)

				Toggle(isOn: $builtInShare.messages) {
					Image(nsImage: icon(forAppWithName: "com.apple.MobileSMS") ?? NSImage())
					Text("Messages".localized())
				}.toggleStyle(.checkbox)

				Toggle(isOn: $builtInShare.mail) {
					Image(nsImage: icon(forAppWithName: "com.apple.Mail") ?? NSImage())
					Text("Mail".localized())
				}.toggleStyle(.checkbox)
			} label: {
				Image(systemName: "list.bullet.clipboard")
				Text("Post Media Tasks".localized())
			}

			Picker(selection: $uploadDestination) {
				ForEach(UploadType.allCases.filter { $0 != .CUSTOM }, id: \.self) { uploadType in
					Button {
					} label: {
						Image(nsImage: ImgurIcon)
						Text(uploadType.rawValue.capitalized)
					}.tag(UploadDestination.builtIn(uploadType))
				}
				if let customUploaders = savedCustomUploaders {
					if !customUploaders.isEmpty {
						Divider()
						ForEach(CustomUploader.allCases, id: \.self) { uploader in
							Button {
							} label: {
								Image(nsImage: AppIcon)
								Text(uploader.name)
							}.tag(UploadDestination.custom(uploader.id))
						}
					}
				}
			} label: {
				Image(systemName: "icloud.and.arrow.up")
				Text("Upload Destination".localized())
			}
			.onChange(of: uploadDestination) {
				if case .builtIn = uploadDestination {
					activeCustomUploader = nil
					uploadType = .IMGUR
					BezelNotification.show(
						messageText: "Selected \(uploadType.rawValue.capitalized)".localized(),
						icon: ToastIcon)
				} else if case let .custom(customUploader) = uploadDestination {
					activeCustomUploader = customUploader
					uploadType = .CUSTOM
					BezelNotification.show(
						messageText: "Selected Custom".localized(), icon: ToastIcon)
				}
			}
			.pickerStyle(MenuPickerStyle())

			if !uploadHistory.isEmpty {
				Menu {
					Button {
						Task { @MainActor in
							openHistoryWindow(uploadHistory: uploadHistory)
						}
					} label: {
						Image(systemName: "clock.arrow.circlepath")
						Text("Open History Window".localized())
					}.globalKeyboardShortcut(.openHistoryWindow)

					Divider()

					ForEach(uploadHistory.prefix(10), id: \.self) { item in
						Button {
							NSPasteboard.general.declareTypes([.string], owner: nil)
							NSPasteboard.general.setString(item.fileUrl ?? "", forType: .string)
							BezelNotification.show(
								messageText: "Copied URL".localized(), icon: ToastIcon)
						} label: {
							HStack {
								if let urlStr = item.fileUrl, let url = URL(string: urlStr),
									url.pathExtension.lowercased() == "mp4"
										|| url.pathExtension.lowercased() == "mov"
								{
									Image(systemName: "video")
										.resizable()
										.scaledToFit()
										.frame(width: 30, height: 30)
								} else {
									PreviewImage(url: URL(string: item.fileUrl ?? "")) { phase in
										switch phase {
										case let .success(nsImage):
											Image(nsImage: nsImage).resizable()
												.scaledToFit()
												.frame(width: 30, height: 30)
										case .failure:
											Image(systemName: "exclamationmark.triangle.fill")
												.foregroundColor(.red)
										case .empty:
											ProgressView()
												.frame(width: 30, height: 30)
										}
									}
									.frame(width: 30, height: 30)
								}
							}
						}
					}
				} label: {
					Image(systemName: "clock.arrow.circlepath")
					Text("History".localized())
				}
			}

			Divider()

			SettingsLink {
				Image(systemName: "gearshape")
				Text("Settings".localized())
			} preAction: {
				NSApp.activate(ignoringOtherApps: true)
			} postAction: {
			}
			.keyboardShortcut("s")

			Button {
				NSApplication.shared.activate(ignoringOtherApps: true)

				let options: [NSApplication.AboutPanelOptionKey: Any] = [
					NSApplication.AboutPanelOptionKey(rawValue: "Copyright".localized()):
						"© \(Calendar.current.component(.year, from: Date())) ADRIAN CASTRO"
				]

				NSApplication.shared.orderFrontStandardAboutPanel(options: options)
			} label: {
				Image(systemName: "info.circle")
				Text("About ishare".localized())
			}
			.keyboardShortcut("a")

			#if GITHUB_RELEASE
				Button {
					NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/castdrian")!)
				} label: {
					Image(systemName: "heart.circle")
					Text("Donate".localized())
				}.keyboardShortcut("d")

				Button {
					AppDelegate.shared.checkForUpdates()
				} label: {
					Image(systemName: "arrow.triangle.2.circlepath")
					Text("Check for Updates".localized())
				}.keyboardShortcut("u")

			#endif

			Button {
				NSApplication.shared.terminate(nil)
			} label: {
				Image(systemName: "power.circle")
				Text("Quit".localized())
			}.keyboardShortcut("q")
		}
	}
}
