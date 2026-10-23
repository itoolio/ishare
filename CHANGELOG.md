## [5.4.1](https://github.com/itoolio/ishare/compare/v5.4.0...v5.4.1) (2026-10-23)

### Bug Fixes

* keep the App Review notes under App Store Connect's limit and build the docs without docbuild ([952b90c](https://github.com/itoolio/ishare/commit/952b90c46dab3b8ee70c3d66e966e1220e9942b2))

## [5.4.0](https://github.com/itoolio/ishare/compare/v5.3.0...v5.4.0) (2026-10-23)

### Features

* add frame and smart shape preferences to capture settings ([c75a5ec](https://github.com/itoolio/ishare/commit/c75a5ecf7d8718ffc7a3f1628637b0a16b29a392))
* ask for an App Store review after ten successful uploads at a calm moment ([337de58](https://github.com/itoolio/ishare/commit/337de58fd0cf8c1a1b9fcacecf87c9cbdf52fbbe))
* **automation:** add ishare:// URL actions and the ishare command-line tool ([96e1e63](https://github.com/itoolio/ishare/commit/96e1e6323ff4f1d8e6c986d88fa9381908b7cab4))
* **automation:** add palette commands for the last upload's QR code and local network link ([3883239](https://github.com/itoolio/ishare/commit/38832395e483e582f6fd9caedf8a748495645571))
* combine selected captures horizontally, vertically or in a grid ([1751fdb](https://github.com/itoolio/ishare/commit/1751fdbde690fddc61ef76ecb072912580e47ca6))
* crosshair guides and an optional last region outline in the region selector ([6ea625f](https://github.com/itoolio/ishare/commit/6ea625f2ff978c9240c6cd24081532631cd3ed62)), closes [#159](https://github.com/itoolio/ishare/issues/159)
* export annotated captures as PDF and SVG and add editor image actions ([6e03fab](https://github.com/itoolio/ishare/commit/6e03fabc25ddccdbe4396b2e6ed20ea40042ae59))
* **history:** sync history between Macs via iCloud key-value storage ([81a79a8](https://github.com/itoolio/ishare/commit/81a79a8d9146353e19d279064c1e59f14c12bb74))
* **i18n:** translate the 5.4 strings into all supported languages ([5c5ed9a](https://github.com/itoolio/ishare/commit/5c5ed9a0985399739bf4df78a5e07051468b7e31))
* **i18n:** translate the new accessibility labels ([c15c57f](https://github.com/itoolio/ishare/commit/c15c57fdd6463d0efa6a4af0aee14060b26281d9))
* label icon-only controls, report toggle states and honor Reduce Motion and Increase Contrast ([dfbba8e](https://github.com/itoolio/ishare/commit/dfbba8e4969a7f3f2e7fc1fb69c18b8038c3ff16))
* lift the subject of a capture into a transparent image ([faa038c](https://github.com/itoolio/ishare/commit/faa038c16509ed6dd75e10adead8913d510bd851))
* per-uploader upload statistics with CSV export in the uploader settings ([dcfce8b](https://github.com/itoolio/ishare/commit/dcfce8bbf957278b8b903097e3b0731776a98eec))
* **raycast:** add a Raycast extension that drives ishare through its command-line tool ([d2dbbb0](https://github.com/itoolio/ishare/commit/d2dbbb09892ad7ca85f8c7c355b107402c3d8105))
* **recording:** draw on the screen while recording ([e78d0bd](https://github.com/itoolio/ishare/commit/e78d0bdad45237508b571c5ccaf25027cdc596c1))
* **recording:** render auto zoom and pointer effects after recording ([2a6286c](https://github.com/itoolio/ishare/commit/2a6286c13c9ba2b59d9f67ec7cea660ed2809ae4))
* **recording:** stop recordings at time, size and disk space limits ([6982459](https://github.com/itoolio/ishare/commit/6982459629dac9d2416ca8502cf7b6a3a8eadb86))
* **recording:** wire effects, drawing and limits into the recorder and settings ([77a68f7](https://github.com/itoolio/ishare/commit/77a68f7b26bb8e7ab02d80fbd911e14312c5c265))
* rotate, flip and straighten with annotations and add image adjustments ([302e013](https://github.com/itoolio/ishare/commit/302e0138856a78961db78c51f795b3ccd6842255))
* **settings:** add sharing, command-line tool and history sync settings ([b3d20a5](https://github.com/itoolio/ishare/commit/b3d20a5d8969a9b6b4eb7723313e9848505e2848))
* **settings:** wire the new uploader types into the model and editor ([6c23005](https://github.com/itoolio/ishare/commit/6c23005a5c529621c7cd96acc39a7bc8f0d857ce))
* **share:** add QR codes for links and temporary local network sharing ([48cf700](https://github.com/itoolio/ishare/commit/48cf700ab6f2d2fc8bb2896f758c8775710b68fa))
* snap editor boxes to detected interface elements ([d4afc2e](https://github.com/itoolio/ishare/commit/d4afc2e0f6627c343750aa70d678f6f13beaee2a))
* **uploaders:** add a GitHub uploader that turns text into Gists ([515a9da](https://github.com/itoolio/ishare/commit/515a9da52fddc75aa8a00f3782f5b5ae53657b95))
* **uploaders:** add Dropbox, Google Drive and OneDrive uploaders ([42a29ae](https://github.com/itoolio/ishare/commit/42a29aefd047e7a63b0059abf67fbb5081769774))
* **uploaders:** add WebDAV and SFTP uploader types ([c300e9f](https://github.com/itoolio/ishare/commit/c300e9f09228db8269caae17f48ae67ed1ff986a))
* **upload:** optimize images and remove photo metadata before upload ([ec2e839](https://github.com/itoolio/ishare/commit/ec2e839d75d491242a1c4018eed49eafffcf8c63))
* **upload:** send webhooks after successful uploads ([156a4af](https://github.com/itoolio/ishare/commit/156a4afda55c8e03060335b6de89bc786aa6920a))
* wrap captures in procedurally drawn device and browser frames ([c23c898](https://github.com/itoolio/ishare/commit/c23c898af71520ef97e629b2b8018b9ccd922656))

### Bug Fixes

* avoid the Xcode 26 compiler crash in the trim window's auto zoom toggle ([b0da610](https://github.com/itoolio/ishare/commit/b0da610e51309c10c8264b754e3fe17af83b9972))
* count local network shares in upload statistics ([f5ab6ce](https://github.com/itoolio/ishare/commit/f5ab6ce781ea9008e773c5640e26a4e783950ab1))

### Performance Improvements

* show the region selector before the screen freeze-frames are ready ([3e6f4ad](https://github.com/itoolio/ishare/commit/3e6f4ad3c3ab5a3a035f87a434d668e3df33438f)), closes [#160](https://github.com/itoolio/ishare/issues/160)

## [5.3.0](https://github.com/itoolio/ishare/compare/v5.2.1...v5.3.0) (2026-10-23)

### Features

* **app-store:** localize the App Store listing and screenshots for every supported language ([c1b8006](https://github.com/itoolio/ishare/commit/c1b8006fdc366e5e0b183f630908f796cff0567a))
* build for Apple silicon only ([3b9f337](https://github.com/itoolio/ishare/commit/3b9f3376a087fdeeae5aa98b6a378e681e0276e1))
* **capture:** capture and translate, capture and ask, and alt text for uploads ([5f32a30](https://github.com/itoolio/ishare/commit/5f32a30aeb12a2d12da63b97b2e3efafe469e184))
* **capture:** keep the self-timer key so Esc cancels it from any app ([bd270af](https://github.com/itoolio/ishare/commit/bd270afe6e7dc1300fe8416aa59f0ff67e16b264))
* **capture:** send interval capture GIFs through the after-capture steps ([011518d](https://github.com/itoolio/ishare/commit/011518d64e803486d6f0c5b49690e40aea639705))
* **history:** copy alt text and Markdown from the toast and history ([42594cc](https://github.com/itoolio/ishare/commit/42594cca2adece6d443c17529c7b0c6f00c53d12))
* **i18n:** translate the 5.3 features into all supported languages ([18b2402](https://github.com/itoolio/ishare/commit/18b24027614213e72972cbd841f494d9d43f2923))
* **recording:** private notes panel, per-app audio, instant replay and on-screen webcam for window recordings ([47f7fdb](https://github.com/itoolio/ishare/commit/47f7fdb00b61bff0d97cfd876f405d96e4bfcef1))
* **ui:** drag-out captures, settings redesign, interactive onboarding, quick annotate, menu favourites, glass polish and what's new ([5803960](https://github.com/itoolio/ishare/commit/58039604cc1ac0ce146961c854e0d926ddaa8792))
* **uploads:** password-protected and expiring links, folder, iCloud Drive and Photos destinations ([abedd53](https://github.com/itoolio/ishare/commit/abedd53cb0255198f9667dc9e52139b9335a2ebb))

### Bug Fixes

* **capture:** pass a closure instead of a method reference to the translation picker binding ([433dc6e](https://github.com/itoolio/ishare/commit/433dc6ec48fa37bdc3b22f3c9d448fbd6ce5504c))
* **capture:** stream on-device answers through an AsyncThrowingStream ([98c7d5e](https://github.com/itoolio/ishare/commit/98c7d5efe4489df0374078eb092f4b04328388ae))
* **ui:** give the glass modifiers explicit initializers ([bc31282](https://github.com/itoolio/ishare/commit/bc312825c70361062c85d6d900657cef9d07e88b))
* **upload:** allow plain HTTP to localhost subdomains ([d28c758](https://github.com/itoolio/ishare/commit/d28c7586ebe5ee6c36c18da9cfb64729d22a60c9))
* **upload:** keep Folder and Photos uploaders out of the synced uploader list ([54c7b26](https://github.com/itoolio/ishare/commit/54c7b26c965ffc88b32fbd46a8fc4b54691c759d))

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
