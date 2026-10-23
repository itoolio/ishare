---
layout: ../../layouts/Doc.astro
title: Automation
description: Control ishare from Terminal, scripts, Raycast and other apps with the ishare command-line tool and ishare:// URL actions.
---

# Automation

ishare can be driven from Terminal, shell scripts, launchers such as Raycast and any app that opens URLs. The command-line tool waits for the result and prints the link; URL actions fit apps that speak [x-callback-url](https://x-callback-url.com).

## Command-line tool

The `ishare` tool is bundled inside the app at `ishare.app/Contents/Helpers/ishare`. To put it on your `PATH`, open **Settings → Advanced → Command-Line Tool**:

- The GitHub build links it to `/usr/local/bin/ishare`, asking for an administrator password only if needed.
- The App Store build shows the command to paste into Terminal:

```sh
sudo mkdir -p /usr/local/bin && sudo ln -sf /Applications/ishare.app/Contents/Helpers/ishare /usr/local/bin/ishare
```

The tool starts ishare in the background when it isn't running.

```text
ishare upload <file…> [--uploader NAME]   Upload files and print their links
ishare capture region|window|screen|scrolling [--upload]
                                          Take a screenshot and print its file, or its link with --upload
ishare record start|stop|toggle           Start or stop a screen recording
ishare uploaders list                     List the configured uploaders (* marks the active one)
ishare history [--limit N]                Print recent uploads, newest first (20 by default)

--json                                    Print machine-readable JSON
--timeout SECONDS                         How long to wait for ishare (120, or 600 for capture and record)
```

`--uploader` takes the name of an uploader as shown in ishare, `Imgur`, or `Local Network` to share the file on your network instead (see below). Exit codes: `0` success, `1` failure, `2` usage error, `3` timeout.

```sh
ishare upload ~/Desktop/diagram.png | pbcopy
ishare capture region --upload --json
ishare history --limit 5 --json
```

With `--json`, the tool prints one object:

```json
{
  "success": true,
  "payload": {
    "uploads": [{ "file": "/Users/me/Desktop/diagram.png", "link": "https://i.imgur.com/abc123.png" }]
  }
}
```

The payload contains `uploads` (`file`, `link`, `error`), `capture` (`file`, `link`), `uploaders` (`id`, `name`, `kind`, `selected`), `history` (`link`, `shortLink`, `title`, `date`, `uploader`, `altText`, `deletionLink`, `localPath`) or `recording`, depending on the command. On failure, `success` is `false` and `error` explains why.

The App Store build is sandboxed, so it can only upload files it is allowed to read, for example in your Pictures folder. The GitHub build can upload any file.

The tool and the app exchange small JSON request and response files in ishare's app group container (`~/Library/Group Containers/L988J7YMK5.group.dev.adrian.ishare/CommandLine`), and the tool wakes the app with an `ishare://cli?id=…` URL. Each response carries its request's ID, and stale files are removed after 15 minutes.

## URL actions

| URL | Action |
| --- | --- |
| `ishare://capture/region` | Capture a region; also `window`, `screen` and `scrolling` |
| `ishare://record/start` | Start a recording; also `stop` and `toggle`. Add `gif=1` or `region=1` |
| `ishare://upload?path=/Users/me/Pictures/a.png` | Upload a file; repeat `path` for up to 50 files |
| `ishare://uploader/select?name=My%20Server` | Make an uploader the active one |
| `ishare://open/history` | Open the history window |
| `ishare://open/settings?pane=uploaders` | Open settings, optionally on `general`, `capture`, `recording`, `uploaders`, `keybinds` or `advanced` |
| `ishare://open/editor` | Choose an image to annotate |

Captures and recordings run your after-capture settings, so they upload and copy the link the way they do from the menu. Paths must be absolute files that ishare can read; anything else is rejected and logged. The older `ishare://capture?type=region`, `ishare://record?gif=1` and `ishare://upload?file=<file URL>` forms keep working.

### Callbacks

Every action accepts optional `x-success`, `x-error` and `x-cancel` parameters, also under the `ishare://x-callback-url/…` prefix:

```text
ishare://capture/region?x-success=myapp://done&x-error=myapp://failed
```

After an upload or a capture that uploads, `x-success` is opened with `link=<the link>` appended; `x-error` gets `errorCode` and `errorMessage`. Callbacks must use an app's own URL scheme: `http`, `https`, `file` and `javascript` callbacks are rejected so a web page can't receive your links.

## Local network sharing

**Share on Local Network**, in the result toast's Copy menu and in the history, serves a file from your Mac at a temporary link such as `http://192.168.1.20:52814/<random token>/shot.png`, with a QR code for your phone. Only devices on the same network can open it. Choose how long links last (5 minutes, 1 hour or until ishare quits) and how many downloads they allow in **Settings → Advanced → Sharing**. You can also pick **Local Network** as the destination for a capture by holding the destination modifier, or with `ishare upload --uploader "Local Network"`.

## Raycast

A Raycast extension with Capture Region, Window and Screen, Upload Files, Recent Uploads and Switch Uploader commands is in [integrations/raycast](https://github.com/itoolio/ishare/tree/main/integrations/raycast). It uses the command-line tool and falls back to URL actions when the tool isn't installed. Install it locally with `npm ci && npm run dev` in that folder.
