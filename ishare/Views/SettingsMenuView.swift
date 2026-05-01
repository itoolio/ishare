//
//  SettingsMenuView.swift
//  ishare
//
//  Created by Adrian Castro on 12.07.23.
//  UI reworked by iGerman on 22.04.24.
//

import BezelNotification
import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsMenuView: View {
	@Default(.aussieMode) var aussieMode

	let appVersionString: String =
		Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String

	var body: some View {
		NavigationView {
			VStack {
				List {
					NavigationLink(destination: GeneralSettingsView()) {
						Label {
							Text("General".localized())
						} icon: {
							Image(systemName: "gearshape")
						}
						.rotationEffect(aussieMode ? .degrees(180) : .zero)
					}
					NavigationLink(destination: UploaderSettingsView()) {
						Label {
							Text("Uploaders".localized())
						} icon: {
							Image(systemName: "icloud.and.arrow.up")
						}
						.rotationEffect(aussieMode ? .degrees(180) : .zero)
					}
					NavigationLink(destination: KeybindSettingsView()) {
						Label {
							Text("Keybinds".localized())
						} icon: {
							Image(systemName: "command.circle")
						}
						.rotationEffect(aussieMode ? .degrees(180) : .zero)
					}
					NavigationLink(destination: CaptureSettingsView()) {
						Label {
							Text("Image files".localized())
						} icon: {
							Image(systemName: "photo")
						}
						.rotationEffect(aussieMode ? .degrees(180) : .zero)
					}
					NavigationLink(destination: RecordingSettingsView()) {
						Label {
							Text("Video files".localized())
						} icon: {
							Image(systemName: "menubar.dock.rectangle.badge.record")
						}
						.rotationEffect(aussieMode ? .degrees(180) : .zero)
					}
					NavigationLink(destination: AdvancedSettingsView()) {
						Label {
							Text("Advanced".localized())
						} icon: {
							Image(systemName: "hammer.circle")
						}
						.rotationEffect(aussieMode ? .degrees(180) : .zero)
					}
				}
				.listStyle(SidebarListStyle())

				Spacer()
				Divider().padding(.horizontal)
				VStack {
					Text("v" + appVersionString)
					Link(destination: URL(string: "https://github.com/castdrian/ishare")!) {
						Text("GitHub".localized())
					}
				}
				.rotationEffect(aussieMode ? .degrees(180) : .zero)
				.padding()
				.frame(maxWidth: .infinity, alignment: .center)
			}
			.frame(minWidth: 200, idealWidth: 200, maxWidth: 300, maxHeight: .infinity)

			GeneralSettingsView()
		}
		.frame(minWidth: 600, maxWidth: 600, minHeight: 450, maxHeight: 450)
		.navigationTitle("Settings".localized())
	}
}

struct GeneralSettingsView: View {
    @EnvironmentObject var localizableManager: LocalizableManager

    @Default(.menuBarIcon) var menubarIcon
    @Default(.toastTimeout) var toastTimeout
    @Default(.aussieMode) var aussieMode
    @Default(.uploadHistory) var uploadHistory
    @Default(.copyImageToClipboard) var copyImageToClipboard

    let appImage = NSImage(named: "AppIcon") ?? AppIcon

    struct MenuButtonStyle: ButtonStyle {
        var backgroundColor: Color

        func makeBody(configuration: Self.Configuration) -> some View {
            configuration.label
                .font(.headline)
                .padding(10)
                .background(backgroundColor)
                .cornerRadius(5)
        }
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 40) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Language".localized())
                        Picker(
                            "",
                            selection: Binding(
                                get: { localizableManager.currentLanguage },
                                set: { localizableManager.changeLanguage(to: $0) }
                            )
                        ) {
                            ForEach(LanguageTypes.allCases, id: \.self) { language in
                                Text(language.name)
                                    .tag(language)
                            }
                        }
                        .frame(width: 120)
                        .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        LaunchAtLogin.Toggle {
                            Text("Launch at login".localized())
                        }
                        Toggle("Land down under".localized(), isOn: $aussieMode)
                        Toggle("Copy image to clipboard instead of URL".localized(), isOn: $copyImageToClipboard)
                    }

                VStack(alignment: .leading) {
                    Text("Menu Bar Icon".localized())
                    HStack {
                        ForEach(MenuBarIcon.allCases, id: \.self) { choice in
                            Button(action: {
                                menubarIcon = choice
                            }) {
                                switch choice {
                                case .DEFAULT:
                                    Image(.menubar)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 20, height: 5)
                                case .APPICON:
                                    Image(nsImage: AppIcon)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 20, height: 5)
                                case .SYSTEM:
                                    Image(systemName: "photo.on.rectangle.angled")
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 20, height: 5)
                                }
                            }
                            .buttonStyle(
                                MenuButtonStyle(
                                    backgroundColor:
                                    menubarIcon == choice ? .accentColor : .clear)
                            )
                        }
                    }
                }
            }
            .padding(.top, 30)

                Spacer()

                VStack(alignment: .leading) {
                    Text("Toast Timeout: \(Int(toastTimeout)) seconds".localized())
                    Slider(value: $toastTimeout, in: 1...10, step: 1)
                        .frame(maxWidth: .infinity)
                }
                .padding(.bottom, 30)
            }
            .padding(30)
            .rotationEffect(aussieMode ? .degrees(180) : .zero)

            if localizableManager.showRestartAlert {
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
                    .zIndex(1)

                VStack(spacing: 15) {
                    Text("Language Change".localized())
                        .font(.headline)
                    Text(
                        "The app needs to close to apply the language change. Please reopen the app after it closes."
                            .localized())
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    HStack(spacing: 20) {
                        Button("Restart Now".localized(), role: .destructive) {
                            localizableManager.confirmLanguageChange()
                        }
                        Button("Cancel".localized(), role: .cancel) {
                            localizableManager.showRestartAlert = false
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(12)
                .shadow(radius: 10)
                .padding(40)
                .zIndex(2)
                .rotationEffect(aussieMode ? .degrees(180) : .zero)
            }
        }
    }
}


struct KeybindSettingsView: View {
	@Default(.forceUploadModifier) var forceUploadModifier
	@Default(.aussieMode) var aussieMode

	var body: some View {
		VStack(spacing: 20) {
			Form {
				Section {
					VStack(spacing: 10) {
						KeyboardShortcuts.Recorder(
							"Open Main Menu:".localized(), name: .toggleMainMenu)
						KeyboardShortcuts.Recorder(
							"Open History Window:".localized(), name: .openHistoryWindow)
						KeyboardShortcuts.Recorder(
							"Capture Region:".localized(), name: .captureRegion)
						KeyboardShortcuts.Recorder(
							"Capture Window:".localized(), name: .captureWindow)
						KeyboardShortcuts.Recorder(
							"Capture Screen:".localized(), name: .captureScreen)
						KeyboardShortcuts.Recorder(
							"Record Screen:".localized(), name: .recordScreen)
						KeyboardShortcuts.Recorder("Record GIF:".localized(), name: .recordGif)
                        KeyboardShortcuts.Recorder("Open most recent item:".localized(), name: .openMostRecentItem)
                        KeyboardShortcuts.Recorder("Upload from Pasteboard:".localized(), name: .uploadPasteBoardItem)

						Divider()
							.padding(.vertical, 5)

						HStack {
							Text("Force Upload Modifier:".localized())
							Picker("", selection: $forceUploadModifier) {
								ForEach(ForceUploadModifier.allCases) { modifier in
									Text(modifier.rawValue)
										.tag(modifier)
								}
							}
							.frame(width: 100)
						}
					}
					.padding(.vertical, 5)
				} header: {
					Text("Keybinds".localized())
						.font(.headline)
						.padding(.bottom, 5)
				}
			}
			.formStyle(.grouped)

			Button(action: {
				KeyboardShortcuts.reset([
					.toggleMainMenu, .openHistoryWindow,
					.captureRegion, .captureWindow, .captureScreen,
					.recordScreen, .recordGif,
					.captureRegionForceUpload, .captureWindowForceUpload, .captureScreenForceUpload,
					.recordScreenForceUpload, .recordGifForceUpload,
				])
				BezelNotification.show(messageText: "Reset keybinds".localized(), icon: ToastIcon)
			}) {
				Text("Reset All Keybinds".localized())
					.foregroundColor(.red)
					.frame(maxWidth: .infinity)
			}
			.padding(.horizontal)
		}
		.padding()
        .rotationEffect(aussieMode ? .degrees(180) : .zero)
	}
}

struct CaptureSettingsView: View {
	@Default(.capturePath) var capturePath
	@Default(.captureFileType) var fileType
	@Default(.captureFileName) var fileName
	@Default(.aussieMode) var aussieMode

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            VStack(alignment: .leading, spacing: 15) {
                Text("Image path:").font(.headline)
                HStack {
                    TextField(text: $capturePath) {}
                    Button(action: {
                        selectFolder { folderURL in
                            if let url = folderURL {
                                Task { @MainActor in
                                    capturePath = url.path()
                                }
                            }
                        }
                    }) {
                        Image(systemName: "folder.fill")
                    }.help("Pick a folder".localized())
                }
            }

			VStack(alignment: .leading, spacing: 15) {
				Text("File prefix:".localized()).font(.headline)
				HStack {
					TextField(String(), text: $fileName)
					Button(action: {
						fileName = Defaults.Keys.captureFileName.defaultValue
					}) {
						Image(systemName: "arrow.clockwise")
					}.help("Set to default".localized())
				}
			}

			VStack(alignment: .leading, spacing: 15) {
				Text("Format:".localized()).font(.headline)
				Picker("Format:".localized(), selection: $fileType) {
					ForEach(FileType.allCases, id: \.self) {
						Text($0.rawValue.uppercased())
					}
				}
				.labelsHidden()
			}
		}
		.padding(30)
		.rotationEffect(aussieMode ? .degrees(180) : .zero)
	}
}

struct RecordingSettingsView: View {
	@Default(.recordingPath) var recordingPath
	@Default(.recordingFileName) var fileName
	@Default(.recordMP4) var recordMP4
	@Default(.useHEVC) var useHEVC
	@Default(.useHDR) var useHDR
	@Default(.aussieMode) var aussieMode
	@Default(.recordAudio) var recordAudio
	@Default(.recordMic) var recordMic
	@Default(.recordPointer) var recordPointer
	@Default(.recordClicks) var recordClicks

	@State private var isExcludedAppSheetPresented = false

	var body: some View {
		VStack(alignment: .leading, spacing: 30) {
			VStack(alignment: .leading, spacing: 15) {
				HStack(spacing: 30) {
					VStack(alignment: .leading) {
						Toggle("Record .mp4 instead of .mov".localized(), isOn: $recordMP4)
						Toggle("Use HEVC".localized(), isOn: $useHEVC)
						Toggle("Use HDR".localized(), isOn: $useHDR)
						Toggle("Record audio".localized(), isOn: $recordAudio)
						Toggle("Record microphone".localized(), isOn: $recordMic)
							.onChange(of: recordMic) { _, newValue in
								if newValue {
									Task {
										switch AVCaptureDevice.authorizationStatus(for: .audio) {
										case .authorized:
											NSLog("Microphone permissions already granted")
										case .notDetermined:
											NSLog("Requesting microphone permissions")
											let granted = await AVCaptureDevice.requestAccess(
												for: .audio)
											if !granted {
												NSLog("Microphone permissions denied")
												await MainActor.run {
													recordMic = false
												}
											}
											NSLog("Microphone permissions granted")
										case .denied, .restricted:
											NSLog("Microphone permissions denied or restricted")
											await MainActor.run {
												recordMic = false
											}
										@unknown default:
											NSLog("Unknown microphone permission status")
											await MainActor.run {
												recordMic = false
											}
										}
									}
								}
							}
						Toggle("Record pointer".localized(), isOn: $recordPointer)
						Toggle("Record clicks".localized(), isOn: $recordClicks)
					}
				}
			}

            VStack(alignment: .leading, spacing: 15) {
                Text("Video path:").font(.headline)
                HStack {
                    TextField(text: $recordingPath) {}
                    Button(action: {
                        selectFolder { folderURL in
                            if let url = folderURL {
                                Task { @MainActor in
                                    recordingPath = url.path()
                                }
                            }
                        }
                    }) {
                        Image(systemName: "folder.fill")
                    }.help("Pick a folder".localized())
                }
            }

			VStack(alignment: .leading, spacing: 15) {
				Text("File prefix:".localized()).font(.headline)
				HStack {
					TextField(String(), text: $fileName)
					Button(action: {
						fileName = Defaults.Keys.recordingFileName.defaultValue
					}) {
						Image(systemName: "arrow.clockwise")
					}.help("Set to default".localized())
				}
			}

			Button("Excluded applications".localized()) {
				isExcludedAppSheetPresented.toggle()
			}
			.padding(.top)
		}
		.padding(30)
		.rotationEffect(aussieMode ? .degrees(180) : .zero)
	}
}

struct AdvancedSettingsView: View {
    @State private var showingAlert: Bool = false
    @Default(.imgurClientId) var imgurClientId
    @Default(.captureBinary) var captureBinary
    @Default(.aussieMode) var aussieMode

    var body: some View {
        ZStack {
            VStack {
                Spacer()
                VStack(alignment: .leading) {
                    Text("Imgur Client ID:".localized()).font(.headline)
                    HStack {
                        TextField(String(), text: $imgurClientId)
                        Button(action: {
                            imgurClientId = Defaults.Keys.imgurClientId.defaultValue
                        }) {
                            Image(systemName: "arrow.clockwise")
                        }.help("Set to default".localized())
                    }
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text("Screencapture binary:".localized()).font(.headline)
                    HStack {
                        TextField(String(), text: $captureBinary)
                        Button(action: {
                            captureBinary = Defaults.Keys.captureBinary.defaultValue
                            BezelNotification.show(
                                messageText: "Reset captureBinary".localized(), icon: ToastIcon)
                        }) {
                            Image(systemName: "arrow.clockwise")
                        }.help("Set to default".localized())
                    }
                }
                Spacer()
            }
            .padding()
            .rotationEffect(aussieMode ? .degrees(180) : .zero)

            if showingAlert {
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
                    .zIndex(1)

                VStack(spacing: 15) {
                    Text("Advanced Settings".localized())
                        .font(.headline)
                    Text("Warning! Only modify these settings if you know what you're doing!".localized())
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button("I understand".localized()) {
                        withAnimation {
                            showingAlert = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(12)
                .shadow(radius: 10)
                .padding(40)
                .zIndex(2)
                .rotationEffect(aussieMode ? .degrees(180) : .zero) // 🌀 Flip this too!
            }
        }
        .onAppear {
            showingAlert = true
        }
    }
}

#Preview {
	NavigationView {
		SettingsMenuView()
			.environmentObject(LocalizableManager.shared)
	}
}
