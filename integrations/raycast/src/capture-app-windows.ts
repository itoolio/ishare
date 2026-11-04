import { LaunchProps, showToast, Toast } from "@raycast/api";
import { copyLinks, MissingToolError, openIshare, preferences, runTool, showFailure } from "./ishare";

export default async function Command(props: LaunchProps<{ arguments: Arguments.CaptureAppWindows }>) {
  const app = props.arguments.app?.trim();
  if (!preferences().uploadCaptures) {
    await openIshare("capture/app", app ? { name: app } : {});
    return;
  }
  try {
    const envelope = await runTool(["capture", "app", ...(app ? [app] : []), "--upload"], 600);
    if (!envelope.success) {
      await showToast({ style: Toast.Style.Failure, title: "Capture failed", message: envelope.error });
      return;
    }
    await copyLinks(envelope.payload.capture?.links ?? [], "Capture");
  } catch (error) {
    if (error instanceof MissingToolError) {
      await openIshare("capture/app", app ? { name: app } : {});
      return;
    }
    await showFailure("Capture failed", error);
  }
}
