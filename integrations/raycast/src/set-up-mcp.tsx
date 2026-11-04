import { Action, ActionPanel, Detail } from "@raycast/api";
import { findTool } from "./ishare";

export default function Command() {
  const tool = findTool();
  const configuration = JSON.stringify(
    { mcpServers: { ishare: { command: tool ?? "/usr/local/bin/ishare", args: ["mcp"] } } },
    null,
    2,
  );
  const status = tool
    ? `The ishare command-line tool is at \`${tool}\`.`
    : "Install the command-line tool from ishare’s Advanced settings first.";
  const markdown = [
    "# Use ishare from AI assistants",
    status,
    "Add this to your assistant’s MCP settings, for example Claude Desktop’s configuration file:",
    "```json",
    configuration,
    "```",
    "The assistant can then take captures, capture app windows, upload files, start recordings and read your recent uploads.",
  ].join("\n\n");
  return (
    <Detail
      markdown={markdown}
      actions={
        <ActionPanel>
          <Action.CopyToClipboard title="Copy MCP Configuration" content={configuration} />
        </ActionPanel>
      }
    />
  );
}
