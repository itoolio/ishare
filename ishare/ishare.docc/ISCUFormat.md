# The ISCU format

The structure of an `.iscu` file and how ishare reads it.

## Overview

An `.iscu` file is a JSON object that describes one uploader. ishare opens it when you double-click the file, drop it on the import sheet in **Settings → Uploaders**, or paste it into the importer. You can also build an uploader in the editor in the same pane and export it as an `.iscu` file, or let the Apple Intelligence assistant write one from a conversation.

ishare decodes the file into a `CustomUploader` from the `ishareCore` package. The parser is lenient so that hand-written files keep working:

- Property names are case-insensitive: `requestURL`, `requesturl` and `RequestUrl` are the same property.
- Trailing commas and comments are accepted.
- Unknown properties are ignored.
- ShareX `.sxcu` files are converted on import.

### Choosing the kind of uploader

The optional `uploaderType` property selects what kind of destination the file describes. It maps to `UploaderKind`.

| `uploaderType` | Destination | Required block | Article |
| --- | --- | --- | --- |
| `custom` (default) | Any HTTP service that accepts a file and answers with its URL | none | <doc:HTTPUploaders> |
| `s3` | AWS S3 and S3-compatible storage, signed with AWS Signature Version 4 | `s3` | <doc:S3Uploaders> |
| `folder` | A folder on this Mac, including iCloud Drive | `folder` | <doc:LocalDestinations> |
| `photos` | An album in the Photos library | `photos` | <doc:LocalDestinations> |

When `uploaderType` is missing, ishare infers it from the blocks that are present: an `s3` block makes an S3 uploader, a `folder` block a folder uploader and a `photos` block a Photos uploader. Without any of them the file describes an HTTP uploader.

### Properties shared by every uploader

| Property | Required | Description |
| --- | --- | --- |
| `name` | yes | Shown in the menu, the settings and the Shortcuts actions. |
| `uploaderType` | no | `custom`, `s3`, `folder` or `photos`, as described above. |
| `id` | no | A UUID that identifies the uploader. ishare creates one when it is missing, and keeps it when you import an updated copy of the same uploader. |
| `modifiedAt` | no | An ISO 8601 date written by ishare when the uploader syncs through iCloud. Leave it out of hand-written files. |

### Validation

Before every upload ishare validates the uploader and refuses to upload when something is missing, for example an empty name, a `requestURL` that is not an http or https URL, a `responseURL` without a closing `}}`, an S3 block without a bucket or a `linkOptions` field that sends a form field with a binary body. The uploader editor shows the same messages while you type.

### Where uploaders are stored

Imported uploaders are saved in the app's preferences and, when iCloud sync is turned on, synced to your other Macs. Secrets such as an S3 secret access key or the default link password are kept in the Keychain instead. Exporting an S3 uploader asks whether to include the secret.

## See Also

- <doc:HTTPUploaders>
- <doc:Examples>
