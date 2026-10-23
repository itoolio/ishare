# ``ishare/Uploader``

A destination that can receive a file and remove it again.

## Overview

Conforming types run on the main actor and are created for each upload by ``UploadTarget/uploader(linkChoice:)``, so they are usually small value types that hold their configuration, such as a `CustomUploader`. See <doc:WritingAnUploader> for a walkthrough.

## Topics

### Uploading

- ``upload(fileURL:progress:)``
- ``UploadOutcome``
- ``UploadFailure``

### Deleting

- ``delete(_:)``
- ``HistoryItem``
