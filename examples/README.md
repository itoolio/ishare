# ishare examples

This folder contains example uploader files for ishare.

## 📤 Compatible Uploader Services

ishare is confirmed to be compatible with the following uploader services:

- [chibisafe](https://github.com/chibisafe/chibisafe)
- [lumen](https://github.com/ChecksumDev/lumen)
- [zipline](https://github.com/diced/zipline)
- [discord webhook](https://support.discord.com/hc/en-us/articles/228383668-Intro-to-Webhooks)

## 🔒 Links and local destinations

- `zipline-protected.iscu` sends a password and an expiry date with each upload through `linkOptions` headers.
- `folder.iscu` copies captures into a folder with a dated subfolder and a public URL.
- `photos.iscu` adds captures to an "ishare" album in Photos.

## ☁️ Servers and cloud storage

- `webdav.iscu` uploads to a Nextcloud (or any WebDAV) folder and creates dated folders with `MKCOL`.
- `sftp.iscu` copies captures to a web server over SSH with a private key and a pinned host key fingerprint.
- `dropbox.iscu`, `google-drive.iscu` and `onedrive.iscu` upload to a cloud folder and copy a shareable link. Sign in from the uploader settings after importing.
- `github.iscu` commits images to a repository, copies Markdown, and turns text snippets into secret Gists.
