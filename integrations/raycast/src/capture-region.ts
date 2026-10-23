import { capture } from "./ishare";

export default async function Command() {
  await capture("region");
}
