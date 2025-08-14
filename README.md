<p align="center">
  <h1>
    ishare
  </h1>
  <p>The definitive screen capture utility for macOS, designed with simplicity and efficiency in mind.</p>
</p>

<p align="center">
  <a href="https://github.com/sponsors/castdrian">
    <img src="https://img.shields.io/badge/sponsor-30363D?style=for-the-badge&logo=GitHub-Sponsors&logoColor=#white" alt="Sponsor">
  </a>
  <a href="https://ko-fi.com/castdrian">
    <img src="https://img.shields.io/badge/Ko--fi-F16061?style=for-the-badge&logo=ko-fi&logoColor=white" alt="Ko-FI">
  </a>
  <a href="https://discord.gg/sX4KYzu5pX">
    <img src="https://img.shields.io/badge/Discord-5865F2?style=for-the-badge&logo=discord&logoColor=white" alt="Discord">
  </a>
  <a href="https://github.com/castdrian/ishare">
    <img src="https://img.shields.io/badge/GitHub-100000?style=for-the-badge&logo=github&logoColor=white" alt="GitHub">
  </a>
</p>

<p align="center">
  <a href="https://github.com/castdrian/ishare/actions?query=workflow:'Build+and+Release+App'">
    <img src="https://github.com/castdrian/ishare/workflows/Build%20and%20Release%20App/badge.svg" alt="Build and Release App">
  </a>
  <a href="https://github.com/castdrian/ishare/releases/">
    <img src="https://img.shields.io/github/release/castdrian/ishare?include_prereleases=&sort=semver&color=blue" alt="GitHub release">
  </a>
  <a href="#license">
    <img src="https://img.shields.io/badge/License-GPL--3.0-blue" alt="License">
  </a>
  <a href="https://github.com/castdrian/ishare/issues">
    <img src="https://img.shields.io/github/issues/castdrian/ishare" alt="issues">
  </a>
  <a href="https://github.com/castdrian/ishare">
    <img src="https://img.shields.io/github/stars/castdrian/ishare?style=social" alt="stars">
  </a>
</p>

---
```bash
brew install --cask ishare
```
<p align="center">
   <a href="https://apps.apple.com/app/ishare-screen-capture/id6499066314" download>
    <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/3/3c/Download_on_the_App_Store_Badge.svg/640px-Download_on_the_App_Store_Badge.svg.png" alt="Download ishare" width="200">
  </a>
</p>
<p align="center">
  <a href="https://github.com/castdrian/ishare/releases/latest/download/ishare.dmg" download>
    <img src="https://i.imgur.com/EthZVfR.png" alt="Download Latest Release" width="200">
  </a>
</p>
<p align="center">
  <a href="https://poeditor.com/join/project/BexTchortS" i18n>
    Translate Project
  </a>
</p>

## 🚀 Features

<details markdown="block">
  <summary><strong>Versatile Screen Capture</strong></summary>
  
- **Custom Region**: Instantly and easily define and capture specific portions of your screen.
- **Window Capture**: Capture individual application windows without any clutter.
- **Entire Display Capture**: Snapshot your whole screen with a single action.

</details>

<details markdown="block">
  <summary><strong>Flexible Screen Recording</strong></summary>
  
- **Video Recording**: Record videos of entire screens or specific windows.
- **GIF Recording**: Capture your moments in GIF format, perfect for quick shares.
- **Customizable Codecs and Compression**: Fine-tune the parameters of the output video files.

</details>

<details markdown="block">
  <summary><strong>Easy Uploading</strong></summary>
  
- **Custom Upload Destinations**: Define your own server or service to upload your media.
- **Built-in Imgur Uploader**: Quickly upload your results to Imgur automatically.

</details>

<details markdown="block">
  <summary><strong>High Customizability</strong></summary>
  
- **Custom Keybinds**: Set keyboard shortcuts that match your workflow.
- **File Format Preferences**: Choose the formats for your screenshots (e.g. PNG, JPG) and recordings.
- **Custom File Naming**: Define your own prefix for filenames, so you always know which app took the shot.
- **Custom Save Path**: Decide where exactly on your system you want to save your captures and recordings.
- **Application Exclusions**: Exclude specific apps from being recorded.

</details>

<details markdown="block">
  <summary><strong>Automatic Updates</strong></summary>
  
  Always stay on the cutting edge with built-in automatic updates.
</details>

![ishare_menu](https://github.com/iGerman00/ishare/assets/36676880/3a546afb-90ee-4b85-8b38-6029ccd67565)

## 🛠 Custom Uploader Setup

By default, ishare supports and opens `.iscu` files for configuration. They are text files containing JSON data according to the `iscu` spec:

**Note:** Version 2.0.0 introduces breaking changes. Follow the migration guide for updates and consider reinstallation if you encounter issues post-update.

<details markdown="block">
  <summary>
    📝 Specification (2.0.0 and newer)
  </summary>

  The custom uploader specification since version 2.0.0+ has the following structure:

```json
{
    "name": "Custom Uploader Name",
    "requestURL": "https://uploader.com/upload",
    "headers": { // optional
        "Authorization": "Bearer YOUR_AUTH_TOKEN"
    },
    "formData": { // optional
        "additionalData": "value"
    },
    "fileFormName": "file", // optional
    "requestBodyType": "multipartFormData", // optional, can be "multipartFormData" or "binary"
    "responseURL": "https://uploader.com/{{jsonproperty}}",
    "deletionURL": "https://uploader.com/{{jsonproperty}}", // optional
    "deleteRequestType": "DELETE" // optional, can be "DELETE" or "GET"
}
```

<sup>All properties are case insensitive.</sup>

This new specification allows for more dynamic URL construction and handles deletion URLs.  
For `responseURL` and `deletionURL`, JSON properties that are derived from the response payload can be defined as `{{jsonProperty}}`. There is support for nesting (`upload.url`) and arrays (`files[0].url`).  
</details>

## ⚙️ Migration from Previous Specification

<details markdown="block">
<summary>Click to expand</summary>

### Key changes

- `responseURL` replaces `responseProp`.
- New optional field `deletionURL`.
- Updated URL templating syntax.

### Migration steps

1. Replace `responseProp` with `responseURL`, ensuring the URL includes placeholders for dynamic values.
2. If your service provides a deletion link, add the `deletionURL` field.
3. Update URL placeholders to match the new syntax:  

For example,

```json
"responseProp": "fileId"
```

Turns into:

```json
"responseURL": "{{fileId}}"
```

### Example migration

Before:

```json
{
    "name": "uploader",
    "requestURL": "https://uploader.com/upload",
    "responseProp": "fileUrl"
}
```

After:

```json
{
    "name": "uploader",
    "requestURL": "https://uploader.com/upload",
    "responseURL": "{{fileUrl}}" // also supported: "https://uploader.com/{{fileId}}"
}
```

</details>

## 📤 Compatible Uploader Services

ishare is confirmed to be compatible with the following upload services:

- [chibisafe](https://github.com/chibisafe/chibisafe)
- [copyparty](https://github.com/9001/copyparty)
- [lumen](https://github.com/ChecksumDev/lumen)
- [zipline](https://github.com/diced/zipline)
- [discord webhook](https://support.discord.com/hc/en-us/articles/228383668-Intro-to-Webhooks)

## 🤝 Contributors

[![Contributors](https://contrib.rocks/image?repo=castdrian/ishare)](https://github.com/castdrian/ishare/graphs/contributors)

## 🙌 Credits

- Special thanks to [Inna Strazhnik](https://www.behance.net/strazhnik) for the app icon

## 📜 License

Released under [GPL-3.0](/LICENSE) by [@castdrian](https://github.com/castdrian)
