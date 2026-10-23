import { Action, ActionPanel, Icon, Image, List } from "@raycast/api";
import { existsSync } from "node:fs";
import { useEffect, useState } from "react";
import { HistoryEntry, MissingToolError, openIshare, runTool } from "./ishare";

const imageExtensions = new Set(["png", "jpg", "jpeg", "gif", "webp", "heic", "avif", "bmp", "tif", "tiff"]);

function isImage(name: string): boolean {
  const extension = name.split(".").pop()?.toLowerCase() ?? "";
  return imageExtensions.has(extension);
}

function thumbnail(entry: HistoryEntry): Image.ImageLike {
  if (entry.localPath && existsSync(entry.localPath) && isImage(entry.localPath)) {
    return { source: entry.localPath };
  }
  if (entry.link && isImage(entry.link)) {
    return { source: entry.link, fallback: Icon.Image };
  }
  return isImage(entry.title) ? Icon.Image : Icon.Document;
}

function subtitle(entry: HistoryEntry): string {
  return [entry.uploader, entry.date ? new Date(entry.date).toLocaleString() : undefined].filter(Boolean).join(" · ");
}

interface State {
  entries: HistoryEntry[];
  isLoading: boolean;
  error?: string;
  missingTool: boolean;
}

export default function Command() {
  const [state, setState] = useState<State>({ entries: [], isLoading: true, missingTool: false });

  useEffect(() => {
    runTool(["history", "--limit", "100"], 30)
      .then((envelope) =>
        setState({
          entries: envelope.payload.history ?? [],
          isLoading: false,
          error: envelope.success ? undefined : envelope.error,
          missingTool: false,
        }),
      )
      .catch((error: unknown) =>
        setState({
          entries: [],
          isLoading: false,
          error: error instanceof Error ? error.message : String(error),
          missingTool: error instanceof MissingToolError,
        }),
      );
  }, []);

  return (
    <List isLoading={state.isLoading} isShowingDetail={false} searchBarPlaceholder="Search uploads">
      {state.error ? (
        <List.EmptyView
          icon={Icon.Warning}
          title={state.missingTool ? "Install the ishare command-line tool" : "Couldn't load uploads"}
          description={
            state.missingTool
              ? "In ishare, open Settings > Advanced > Command-Line Tool, or set its path here."
              : state.error
          }
          actions={
            <ActionPanel>
              <Action
                title="Open History in Ishare"
                icon={Icon.AppWindowGrid2x2}
                onAction={() => openIshare("open/history")}
              />
              <Action
                title="Open Ishare Settings"
                icon={Icon.Gear}
                onAction={() => openIshare("open/settings", { pane: "advanced" })}
              />
            </ActionPanel>
          }
        />
      ) : null}
      {state.entries.map((entry, index) => {
        const link = entry.shortLink ?? entry.link;
        return (
          <List.Item
            key={`${entry.link ?? entry.localPath ?? entry.title}-${index}`}
            icon={thumbnail(entry)}
            title={entry.title || link || "Upload"}
            subtitle={subtitle(entry)}
            keywords={[entry.altText, entry.uploader, link].filter((value): value is string => Boolean(value))}
            accessories={entry.altText ? [{ icon: Icon.Text, tooltip: entry.altText }] : []}
            actions={
              <ActionPanel>
                {link ? <Action.CopyToClipboard title="Copy Link" content={link} /> : null}
                {entry.link ? <Action.OpenInBrowser url={entry.link} /> : null}
                {entry.shortLink && entry.link ? (
                  <Action.CopyToClipboard title="Copy Full Link" content={entry.link} />
                ) : null}
                {entry.altText ? <Action.CopyToClipboard title="Copy Alt Text" content={entry.altText} /> : null}
                {entry.link && isImage(entry.link) ? (
                  <Action.CopyToClipboard
                    title="Copy Markdown"
                    content={`![${entry.altText ?? entry.title}](${entry.link})`}
                  />
                ) : null}
                {entry.localPath ? <Action.ShowInFinder path={entry.localPath} /> : null}
                <Action
                  title="Open History in Ishare"
                  icon={Icon.AppWindowGrid2x2}
                  shortcut={{ modifiers: ["cmd"], key: "h" }}
                  onAction={() => openIshare("open/history")}
                />
              </ActionPanel>
            }
          />
        );
      })}
    </List>
  );
}
