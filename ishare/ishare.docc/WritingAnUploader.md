# Writing an uploader

Add a new kind of destination to ishare by conforming to the uploader protocol.

## Overview

Every destination in ishare, from Imgur to a Photos album, is a type that conforms to ``Uploader``. The protocol is deliberately small: one method sends a file and describes the result, the other removes an upload again.

```swift
@MainActor
protocol Uploader: Sendable {
    func upload(fileURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> UploadOutcome
    func delete(_ item: HistoryItem) async throws
}
```

The rest of the pipeline is shared. ``UploadCoordinator`` resolves which destinations a capture goes to, asks for link options, calls your uploader, shortens the link, records the result in the history and the upload statistics, delivers the URL to the clipboard and queues retryable failures. Your type only has to talk to its destination.

The existing conformances are good references:

| Type | Destination |
| --- | --- |
| ``ImgurUploader`` | The built-in Imgur destination |
| ``HTTPUploader`` | `.iscu` HTTP uploaders, see <doc:HTTPUploaders> |
| ``S3Uploader`` | S3-compatible storage, see <doc:S3Uploaders> |
| ``FolderUploader`` | Folders and iCloud Drive, see <doc:LocalDestinations> |
| ``PhotosUploader`` | Photos albums |

### Uploading

``Uploader/upload(fileURL:progress:)`` receives a file URL that stays valid until the method returns. The file may be a screenshot, a recording, a GIF or a text snippet, so check the type when your destination is picky, and throw ``UploadFailure/unsupportedFile(destination:fileExtension:)`` for files it can't host, as ``ImgurUploader`` does for anything other than images and videos.

Report progress as a fraction from 0 to 1 through the `progress` closure. It may be called from any thread. When you send the request through ``UploadService/perform(_:progress:)`` with ``UploadService/session``, progress, response recording for **Test Upload** and the conversion of status codes into ``UploadFailure/http(status:body:)`` are handled for you, and tests can stub the network.

Return an ``UploadOutcome`` that describes the result:

| Property | Meaning |
| --- | --- |
| ``UploadOutcome/url`` | The link people share, or a `file://` URL for local destinations. |
| ``UploadOutcome/deletionURL`` | A URL that deletes the upload, kept in the history. |
| ``UploadOutcome/uploaderID`` | The ID of the `CustomUploader` that made the upload, so the history can find the uploader again to delete it. |
| ``UploadOutcome/s3Key`` | The object key for S3 uploads. |
| ``UploadOutcome/localIdentifier`` | An identifier for items without a URL, such as a Photos asset. |
| ``UploadOutcome/isShareable`` | `false` when the destination has no link to copy or shorten. |

### Failing

Throw ``UploadFailure`` so the coordinator can decide what to do:

- ``UploadFailure/invalidSpecification(_:)`` when the configuration is incomplete. Validate with `UploaderValidator.issues(for:)` before you start, as every built-in uploader does.
- ``UploadFailure/transport(_:)`` for network errors, and ``UploadFailure/http(status:body:)`` for error responses. Transport errors and 408, 429 and 5xx responses are retryable, so the coordinator moves the file to the upload queue and tries again later.
- ``UploadFailure/responseParsing(_:)`` when the response doesn't contain a link.
- ``UploadFailure/cancelled`` when the person cancelled, which is not counted as a failure.

### Deleting

``Uploader/delete(_:)`` receives the ``HistoryItem`` that the upload created, with the deletion URL, S3 key or local identifier from your ``UploadOutcome``. Delete the remote copy and return; the history removes the item itself. Destinations that can't delete anything can return without doing work.

### Wiring it up

1. Add a case to `UploaderKind` in `Packages/ishareCore` and give it a symbol and a title.
2. Add a configuration type for its settings as an optional property of `CustomUploader`, decoded case-insensitively like the existing `s3`, `folder` and `photos` blocks, so the new kind can be imported and exported as an `.iscu` file.
3. Write the uploader in `ishare/Http/Uploaders` as a `struct` that conforms to ``Uploader``.
4. Return it from ``UploadTarget/uploader(linkChoice:)`` for the new kind.
5. Validate its configuration in `UploaderValidator.issues(for:)`.
6. Add a section to the uploader editor for its settings, and document the new `uploaderType` in this catalog.

### Testing

The unit tests replace ``UploadService/session`` with a session backed by a stub URL protocol, so an uploader that sends its requests through ``UploadService`` can be tested without a server. Run requests through ``UploadCoordinator`` with a spy ``UploadEnvironment`` to check the history entry, the notifications and the queueing of retryable failures, as the upload pipeline tests in `ishareTests` do.

## See Also

- ``Uploader``
- ``UploadOutcome``
- ``UploadFailure``
- <doc:ISCUFormat>
