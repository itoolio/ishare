import { closeMainWindow, LaunchProps } from "@raycast/api";
import { openIshare } from "./ishare";

export default async function Command(props: LaunchProps<{ arguments: Arguments.CaptureWebPage }>) {
  const query: Record<string, string> = { url: props.arguments.url.trim() };
  const width = props.arguments.width?.trim();
  if (width) {
    query.width = width;
  }
  await closeMainWindow();
  await openIshare("capture/web", query);
}
