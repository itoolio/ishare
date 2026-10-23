import { Action, ActionPanel, Icon, List, popToRoot, showHUD } from "@raycast/api";
import { useEffect, useState } from "react";
import { MissingToolError, openIshare, runTool, UploaderInfo } from "./ishare";

const kindIcons: Record<string, Icon> = {
  imgur: Icon.Image,
  s3: Icon.HardDrive,
  folder: Icon.Folder,
  photos: Icon.Mountain,
  custom: Icon.Globe,
};

interface State {
  uploaders: UploaderInfo[];
  isLoading: boolean;
  error?: string;
  missingTool: boolean;
}

async function select(uploader: UploaderInfo): Promise<void> {
  await openIshare("uploader/select", { name: uploader.name });
  await showHUD(`Uploading with ${uploader.name}`);
  await popToRoot();
}

export default function Command() {
  const [state, setState] = useState<State>({ uploaders: [], isLoading: true, missingTool: false });

  useEffect(() => {
    runTool(["uploaders", "list"], 30)
      .then((envelope) =>
        setState({
          uploaders: (envelope.payload.uploaders ?? []).filter((uploader) => uploader.kind !== "localNetwork"),
          isLoading: false,
          error: envelope.success ? undefined : envelope.error,
          missingTool: false,
        }),
      )
      .catch((error: unknown) =>
        setState({
          uploaders: [],
          isLoading: false,
          error: error instanceof Error ? error.message : String(error),
          missingTool: error instanceof MissingToolError,
        }),
      );
  }, []);

  return (
    <List isLoading={state.isLoading} searchBarPlaceholder="Search uploaders">
      {state.error ? (
        <List.EmptyView
          icon={Icon.Warning}
          title={state.missingTool ? "Install the ishare command-line tool" : "Couldn't load uploaders"}
          description={
            state.missingTool
              ? "In ishare, open Settings > Advanced > Command-Line Tool, or set its path here."
              : state.error
          }
          actions={
            <ActionPanel>
              <Action
                title="Open Uploader Settings"
                icon={Icon.Gear}
                onAction={() => openIshare("open/settings", { pane: "uploaders" })}
              />
            </ActionPanel>
          }
        />
      ) : null}
      {state.uploaders.map((uploader) => (
        <List.Item
          key={uploader.id}
          icon={kindIcons[uploader.kind] ?? Icon.Upload}
          title={uploader.name}
          subtitle={uploader.kind}
          accessories={uploader.selected ? [{ icon: Icon.CheckCircle, tooltip: "Selected" }] : []}
          actions={
            <ActionPanel>
              <Action title="Use This Uploader" icon={Icon.Checkmark} onAction={() => select(uploader)} />
              <Action
                title="Open Uploader Settings"
                icon={Icon.Gear}
                onAction={() => openIshare("open/settings", { pane: "uploaders" })}
              />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
