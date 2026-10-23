# ishare for Raycast

Capture, upload and browse your uploads with [ishare](https://ishare.itoolio.dev) from Raycast.

| Command | What it does |
| --- | --- |
| Capture Region, Capture Window, Capture Screen | Takes a screenshot, uploads it and copies the link |
| Upload Files | Uploads the files selected in Finder and copies their links |
| Recent Uploads | Lists your recent uploads with thumbnails; copy or open links, alt text and Markdown |
| Switch Uploader | Picks the uploader ishare uses from now on |

The extension talks to ishare through its command-line tool and its JSON output (`ishare … --json`). When the tool isn't installed, captures and uploads fall back to the `ishare://` URL actions, which run the same actions without returning the link.

## Requirements

- A version of ishare that bundles the command-line tool, installed in `/Applications`
- The command-line tool: in ishare, open **Settings > Advanced > Command-Line Tool**. The GitHub build links it to `/usr/local/bin/ishare` for you; the App Store build shows the `ln -s` command to paste into Terminal. If you keep it somewhere else, set its path in the extension preferences.

The App Store build of ishare is sandboxed and can only upload files it is allowed to read, such as files in your Pictures folder or ones you picked in ishare before. The GitHub build can upload any file.

## Install locally

The extension isn't published to the Raycast Store. To use it, build it from this folder:

```sh
cd integrations/raycast
npm ci
npm run dev
```

`npm run dev` imports the extension into Raycast and keeps it updated while it runs; the commands stay in Raycast after you stop it. Run `npm run build` and `npm run lint` to check your changes. `npm run lint:store` runs Raycast's full store validation, which needs a Raycast account named as the author.
