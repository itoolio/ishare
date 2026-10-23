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
