import { closeMainWindow } from "@raycast/api";
import { openIshare } from "./ishare";

export default async function Command() {
  await closeMainWindow();
  await openIshare("open/replay");
}
