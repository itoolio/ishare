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
* add option to copy image data to clipboard instead of URL ([#146](https://github.com/itoolio/ishare/issues/146)) ([c911c24](https://github.com/itoolio/ishare/commit/c911c244e38d39a7950f07f2bdfe6eb7eae613b7))
* add option to copy image data to clipboard instead of URL ([#147](https://github.com/itoolio/ishare/issues/147)) ([fbe5f58](https://github.com/itoolio/ishare/commit/fbe5f58653504a9095dfabdc6dcec3598fbf05e7))
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
