## [5.2.1](https://github.com/itoolio/ishare/compare/v5.2.0...v5.2.1) (2026-10-23)

### Bug Fixes

* **app-store:** declare the keychain group for App Review and keep versions out of screenshots ([bc5e28b](https://github.com/itoolio/ishare/commit/bc5e28ba3abba5de5cbc613cf01ec8c8be3905b8))

## [5.2.0](https://github.com/itoolio/ishare/compare/v5.1.1...v5.2.0) (2026-10-23)

### Features

* **capture:** text capture, self-timer, QR links, redaction, interval capture, app profiles and window-title names ([942e62a](https://github.com/itoolio/ishare/commit/942e62aae4ef117bb0563f194fc9a68e9226e8fa))
* **diagnostics:** collect MetricKit crash and hang reports ([9e82135](https://github.com/itoolio/ishare/commit/9e82135c0bdfe294cd1078131005e9f4757f8691))
* **editor:** annotation templates, layers sidebar, anchored zoom and live effect previews ([58eafb5](https://github.com/itoolio/ishare/commit/58eafb5d82edf03b9d2ed531daeedfc245f15504))
* **history:** day timeline with multi-select and bulk actions ([3deedf9](https://github.com/itoolio/ishare/commit/3deedf9df1f32273f7eb481e5d7c82df36ee2d4c))
* **i18n:** translate the 5.2 features into all supported languages ([c24ff04](https://github.com/itoolio/ishare/commit/c24ff0418e46a2d6d0ee72d4f4750c4bc34c4380))
* **menu:** add text capture, interval capture, markers and presets to the menu and command palette ([ac645cf](https://github.com/itoolio/ishare/commit/ac645cfb20c99c13270c1b002db964b24c7f8bd4))
* **menu:** command palette, menu layout and appearance, toast placement, notifications, sharing, undo and Continuity Camera import ([21c3b6a](https://github.com/itoolio/ishare/commit/21c3b6a8a51476ef12bb5a1f0c32cd032404e630))
* **recording:** markers and chapters, on-device captions, export formats and composited overlays for window recordings ([ce86b7c](https://github.com/itoolio/ishare/commit/ce86b7c3cb03e7acb3203be80a2518d9fd1b31ff))
* **settings:** move old local captures to the Trash ([9855998](https://github.com/itoolio/ishare/commit/98559980ce2c7206952a071ca5eb580e09edd49d))
* **upload:** sync S3 secrets through iCloud Keychain in a shared access group ([103ebfd](https://github.com/itoolio/ishare/commit/103ebfd943b8246893d37bc2b69e8cb1fe0239f3))
* **upload:** URL shortener step and upload presets with shortcuts and an App Intent ([2e1c962](https://github.com/itoolio/ishare/commit/2e1c96216bbbeeda50cb975dfefd537158de2650))
* **widgets:** add a Recent Uploads widget and a Capture Region control ([61bd48e](https://github.com/itoolio/ishare/commit/61bd48e87641e38ab1e303cae503f3d3d8d8ac4e))

### Bug Fixes

* **menu:** show after-capture steps in the order they run and fit longer uploader names ([a3e9885](https://github.com/itoolio/ishare/commit/a3e98857590e864624794fea34390af5b754aa2d))
* **upload:** keep Keychain sharing to the App Store build ([875daf1](https://github.com/itoolio/ishare/commit/875daf1cca6dbca12de819662284298a0e75fb3b))

## [5.1.1](https://github.com/itoolio/ishare/compare/v5.1.0...v5.1.1) (2026-10-23)

### Bug Fixes

* **app-store:** make automatic scrolling opt-in and drop the Movies entitlement ([b4664a3](https://github.com/itoolio/ishare/commit/b4664a304076b5af1852e10638a96b3f79949768))
* **history:** decode image thumbnails directly and time out QuickLook ([5bf74f2](https://github.com/itoolio/ishare/commit/5bf74f2df345daf223402f93550b424f1af5dd51))

## [5.1.0](https://github.com/itoolio/ishare/compare/v5.0.0...v5.1.0) (2026-10-22)

### Features

* **capture:** add measuring, clearer magnifier, last region, privacy blur and beautify ([683e534](https://github.com/itoolio/ishare/commit/683e534554e84147709193af337fab100b7b3877))
* **editor:** canvas crop handles, spotlight union, stamps, arrow styles and zoom ([45a7eb4](https://github.com/itoolio/ishare/commit/45a7eb40f2f2014c86e54e5dd56f9063b7ffd137))
* **editor:** discard with Command-Delete ([ef9fc0c](https://github.com/itoolio/ishare/commit/ef9fc0c39389a880f80d882932bb7465e2b03715))
* **history:** cached thumbnails, history search, server deletion, limits and sounds ([1333f84](https://github.com/itoolio/ishare/commit/1333f8493561e1bb1f5dfb985b7e09ee822457a1))
* **i18n:** translate the new features into all supported languages ([52abecc](https://github.com/itoolio/ishare/commit/52abeccbc5a48cbea06a352a36a3907e152eecbc))
* **recording:** add input overlay, webcam bubble, audio meters, trimming and GIF presets ([f69d654](https://github.com/itoolio/ishare/commit/f69d654716a472557877db261516c947ad4fa59c))
* **settings:** add privacy and background options for screenshots ([d63cbdf](https://github.com/itoolio/ishare/commit/d63cbdf0b5fdeefd3ac3928b6472bc24c8bb3654))
* **ui:** keyboard menu, hover previews, menu bar drops, services, onboarding and settings search ([224bc70](https://github.com/itoolio/ishare/commit/224bc70b18d62a122b05f2ee57c1cbab693a2a81))
* **upload:** multi-destination uploads, retry queue, watch folder and uploader tooling ([da25d26](https://github.com/itoolio/ishare/commit/da25d2691d0aae2a2c10f11a08c94031e83c511c))

### Bug Fixes

* **capture:** copy PNG pixels with the file URL ([3a75ef7](https://github.com/itoolio/ishare/commit/3a75ef738cd7eab76f5d4d818aed6b0f1561654f))
* report real upload results, skip own captures in the watch folder and index new settings ([61c571d](https://github.com/itoolio/ishare/commit/61c571d19e74da59f00e2ed2dd264eddc8120340))

## [5.0.0](https://github.com/itoolio/ishare/compare/v4.2.6...v5.0.0) (2026-10-20)

### ⚠ BREAKING CHANGES

* screenshots use ScreenCaptureKit and the custom screencapture binary setting was removed; the menu, settings and Sparkle feed URL changed

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>

# Conflicts:
#	.github/workflows/main.yml
#	ishare/Config.xcconfig
#	ishare/Http/Custom.swift
#	ishare/Http/Imgur.swift
#	ishare/Views/SettingsMenuView.swift
* screenshots use ScreenCaptureKit and the custom screencapture binary setting was removed; the menu, settings and Sparkle feed URL changed
* **capture:** the custom screencapture binary setting was removed

### release

* ishare 5.0 ([7c731a8](https://github.com/itoolio/ishare/commit/7c731a8ad06f2db1815449a7d30829c6b73b9f70))

### Features

* add option to copy image data to clipboard instead of URL ([102b57b](https://github.com/itoolio/ishare/commit/102b57bd06a1ed75db9fc4d69f1afb668b1cdf23))
* **capture:** capture with ScreenCaptureKit and on-screen selectors ([8b4c984](https://github.com/itoolio/ishare/commit/8b4c984eb691e3e259633f8bb55d125d30c1bf85)), closes [#114](https://github.com/itoolio/ishare/issues/114) [#116](https://github.com/itoolio/ishare/issues/116) [#115](https://github.com/itoolio/ishare/issues/115) [#92](https://github.com/itoolio/ishare/issues/92) [#119](https://github.com/itoolio/ishare/issues/119) [#41](https://github.com/itoolio/ishare/issues/41)
* chat uploader assistant, permission helper and live-test fixes ([#151](https://github.com/itoolio/ishare/issues/151)) ([e6c793e](https://github.com/itoolio/ishare/commit/e6c793e0f56ee48f2a4f3def00d9a2b0aaf6ac67))
* chat-based uploader assistant and drag-in permission helper ([d7394f5](https://github.com/itoolio/ishare/commit/d7394f53c8d4fa040c934e9755ab22dc1d9e91e9))
* **design:** new viewfinder app icon and violet accent ([07ce906](https://github.com/itoolio/ishare/commit/07ce90670085296645fea43d081a33d1d0899c1c))
* **editor:** add ShareX style annotation tools ([6960d19](https://github.com/itoolio/ishare/commit/6960d195c9dc977c4dc04aa1112a28cbc9cf99e0))
* **i18n:** translate every new string into all supported languages ([d8ba746](https://github.com/itoolio/ishare/commit/d8ba7467aa07ea5859ea22be0180795067099b32))
* ishare 5.0 ([#149](https://github.com/itoolio/ishare/issues/149)) ([d7afe3e](https://github.com/itoolio/ishare/commit/d7afe3e20060dde29bed8c11df0158776ceac65a))
* **ui:** redesign the menu and settings with Liquid Glass ([350ad20](https://github.com/itoolio/ishare/commit/350ad204ec8a996f8c8395cd4e0b92db4f87d0f7)), closes [#105](https://github.com/itoolio/ishare/issues/105) [#135](https://github.com/itoolio/ishare/issues/135) [#134](https://github.com/itoolio/ishare/issues/134) [#61](https://github.com/itoolio/ishare/issues/61) [#102](https://github.com/itoolio/ishare/issues/102) [#113](https://github.com/itoolio/ishare/issues/113)
* **upload:** async upload service with S3 support ([4a0b202](https://github.com/itoolio/ishare/commit/4a0b20228a67b6b2b0a78376f96579ada31c5b5f)), closes [#113](https://github.com/itoolio/ishare/issues/113)

### Bug Fixes

* add extension file to github target ([#140](https://github.com/itoolio/ishare/issues/140)) ([c8496a1](https://github.com/itoolio/ishare/commit/c8496a171c00871d95eaa07b4ec018b51b653020))
* fix a few more things ([#133](https://github.com/itoolio/ishare/issues/133)) ([996264a](https://github.com/itoolio/ishare/commit/996264a9f8aef5144b21d460350f4a8c75abbc5d))
* **i18n:** correct German typos and capitalization ([7a1eef0](https://github.com/itoolio/ishare/commit/7a1eef072821ad31dc8693ad6ebe342a4e446701)), closes [#144](https://github.com/itoolio/ishare/issues/144)
* **i18n:** skip untranslated strings in Crowdin exports and widen the editor ([459f856](https://github.com/itoolio/ishare/commit/459f856bbcfb989679d514381ba6ec5b04e822a4))
* import uploaders without a key window and log capture and upload outcomes ([c504a2f](https://github.com/itoolio/ishare/commit/c504a2f8f431dfd015bafcc9312c078ce2df1396))
* macOS 26 Tahoe stuff ([#132](https://github.com/itoolio/ishare/issues/132)) ([8e085d4](https://github.com/itoolio/ishare/commit/8e085d4c72af4a63bfa04f2c488633fc09ee46b6))
