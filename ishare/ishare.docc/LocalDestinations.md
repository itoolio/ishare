# Local destinations

Keep captures on your Mac in a folder, in iCloud Drive or in a Photos album.

## Overview

Folder and Photos uploaders don't upload anything. They copy each capture to a place on your Mac and behave like any other uploader otherwise: they can be the default uploader, an additional destination or part of an upload preset. Local uploaders are never synced to other Macs, because the folders and albums they point to are specific to this one.

### Folder

```json
{
  "name": "Website folder",
  "uploaderType": "folder",
  "folder": {
    "path": "~/Sites/screenshots",
    "subfolderTemplate": "{{date}}",
    "publicURL": "https://example.com/screenshots/{{path}}"
  }
}
```

| Property | Required | Description |
| --- | --- | --- |
| `path` | yes | The folder captures are copied into. `~` expands to your home folder. After importing, choose the folder again with **Choose…** so ishare is allowed to write to it. |
| `subfolderTemplate` | no | A subfolder for each capture, with the placeholders of S3 key templates, for example `{{date}}` or `{{year}}/{{month}}`. |
| `publicURL` | no | The link to copy when a web server or sync service publishes the folder. Supports `{{filename}}`, `{{path}}` (subfolder and file name) and `{{subfolder}}`. Without it ishare copies the `file://` URL. |

A file with the same name gets a number appended instead of being replaced. Deleting the upload from the history moves the copy to the Trash.

**iCloud Drive** in the **Create** menu is a folder uploader whose folder picker starts in iCloud Drive, so iCloud syncs the captures to your other devices.

### Photos

```json
{
  "name": "Photos",
  "uploaderType": "photos",
  "photos": { "album": "ishare" }
}
```

| Property | Required | Description |
| --- | --- | --- |
| `album` | no | The album captures are added to. Defaults to `ishare` and is created when it doesn't exist. Use `""` to add captures to the library only. |

ishare asks for Photos access when you create the uploader. Apps can't create or add to shared albums, so choose a regular album and share it from Photos. Photos uploads have no link: the history keeps a reference to the photo, and deleting the upload there removes it from Photos.

## See Also

- <doc:ISCUFormat>
- <doc:Examples>
