# ``ishare``

Describe upload destinations with `.iscu` files and extend ishare with new kinds of uploaders.

## Overview

ishare uploads screenshots, recordings and files to Imgur, to any HTTP service, to S3-compatible storage or to a local destination such as a folder or a Photos album. Every destination other than Imgur is a custom uploader, a small JSON document with the `.iscu` extension that you can import, export and share.

This documentation covers two audiences:

- People who write `.iscu` files for a service. Start with <doc:ISCUFormat> and use <doc:Examples> as templates.
- Contributors who add a new kind of destination to the app. Read <doc:WritingAnUploader>, which walks through the ``Uploader`` protocol and the upload pipeline around it.

## Topics

### The ISCU format

- <doc:ISCUFormat>
- <doc:HTTPUploaders>
- <doc:ResponseTemplates>
- <doc:LinkOptions>
- <doc:S3Uploaders>
- <doc:LocalDestinations>
- <doc:Examples>

### Extending ishare

- <doc:WritingAnUploader>
- ``Uploader``
- ``UploadOutcome``
- ``UploadTarget``
- ``UploadFailure``
- ``CustomUploader``
- ``UploaderKind``
