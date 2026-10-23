import { getSelectedFinderItems, showHUD, showToast, Toast } from "@raycast/api";
import { statSync } from "node:fs";
import { copyLinks, links, MissingToolError, openIshare, runTool, showFailure } from "./ishare";

function selectedFiles(paths: string[]): string[] {
  return paths.filter((path) => {
    try {
      return statSync(path).isFile();
    } catch {
      return false;
    }
  });
}

export default async function Command() {
  let files: string[];
  try {
    files = selectedFiles((await getSelectedFinderItems()).map((item) => item.path));
  } catch {
    await showHUD("Select files in Finder first");
    return;
  }
  if (files.length === 0) {
    await showHUD("Select files in Finder first");
    return;
  }
  const toast = await showToast({
    style: Toast.Style.Animated,
    title: files.length === 1 ? "Uploading file" : `Uploading ${files.length} files`,
  });
  try {
    const envelope = await runTool(["upload", ...files], 300);
    const failures = (envelope.payload.uploads ?? []).filter((upload) => upload.error);
    if (!envelope.success || failures.length > 0) {
      toast.style = Toast.Style.Failure;
      toast.title = "Some uploads failed";
      toast.message = envelope.error ?? failures.map((upload) => `${upload.file}: ${upload.error}`).join("\n");
      const found = links(envelope);
      if (found.length > 0) {
        await copyLinks(found, "Upload");
      }
      return;
    }
    await toast.hide();
    await copyLinks(links(envelope), "Upload");
  } catch (error) {
    if (error instanceof MissingToolError) {
      await toast.hide();
      await openIshare("upload", { path: files });
      await showHUD("Sent to ishare");
      return;
    }
    await toast.hide();
    await showFailure("Upload failed", error);
  }
}
