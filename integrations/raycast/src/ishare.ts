import { Clipboard, getPreferenceValues, open, showHUD, showToast, Toast } from "@raycast/api";
import { execFile } from "node:child_process";
import { accessSync, constants } from "node:fs";

export type CaptureMode = "region" | "window" | "screen";

export interface UploadResult {
  file: string;
  link?: string;
  error?: string;
}

export interface UploaderInfo {
  id: string;
  name: string;
  kind: string;
  selected: boolean;
}

export interface HistoryEntry {
  link?: string;
  shortLink?: string;
  title: string;
  date?: string;
  uploader?: string;
  altText?: string;
  deletionLink?: string;
  localPath?: string;
}

export interface Payload {
  message?: string;
  uploads?: UploadResult[];
  capture?: { file?: string; link?: string };
  uploaders?: UploaderInfo[];
  history?: HistoryEntry[];
  recording?: boolean;
}

export interface Envelope {
  success: boolean;
  error?: string;
  payload: Payload;
}

interface Preferences {
  cliPath?: string;
  uploadCaptures?: boolean;
}

export class MissingToolError extends Error {
  constructor() {
    super("The ishare command-line tool wasn't found");
  }
}

const candidatePaths = [
  "/usr/local/bin/ishare",
  "/opt/homebrew/bin/ishare",
  "/Applications/ishare.app/Contents/Helpers/ishare",
  `${process.env.HOME ?? ""}/Applications/ishare.app/Contents/Helpers/ishare`,
];

function isExecutable(path: string): boolean {
  try {
    accessSync(path, constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

export function preferences(): Preferences {
  return getPreferenceValues<Preferences>();
}

export function findTool(): string | undefined {
  const configured = preferences().cliPath?.trim();
  const paths = configured ? [configured, ...candidatePaths] : candidatePaths;
  return paths.find(isExecutable);
}

export function runTool(args: string[], timeoutSeconds = 120): Promise<Envelope> {
  const tool = findTool();
  if (!tool) {
    return Promise.reject(new MissingToolError());
  }
  return new Promise((resolve, reject) => {
    execFile(
      tool,
      [...args, "--json", "--timeout", String(timeoutSeconds)],
      { timeout: (timeoutSeconds + 5) * 1000, maxBuffer: 8 * 1024 * 1024 },
      (error, stdout, stderr) => {
        const output = stdout.trim();
        if (output.startsWith("{")) {
          try {
            resolve(JSON.parse(output) as Envelope);
            return;
          } catch (parseError) {
            reject(parseError);
            return;
          }
        }
        reject(error ?? new Error(stderr.trim() || "ishare returned no output"));
      },
    );
  });
}

export function ishareURL(path: string, query: Record<string, string | string[]> = {}): string {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(query)) {
    for (const item of Array.isArray(value) ? value : [value]) {
      params.append(key, item);
    }
  }
  const search = params.toString();
  return `ishare://${path}${search ? `?${search.replace(/\+/g, "%20")}` : ""}`;
}

export async function openIshare(path: string, query: Record<string, string | string[]> = {}): Promise<void> {
  await open(ishareURL(path, query));
}

export function links(envelope: Envelope): string[] {
  const uploads = envelope.payload.uploads ?? [];
  const fromUploads = uploads.map((upload) => upload.link).filter((link): link is string => Boolean(link));
  const capture = envelope.payload.capture?.link;
  return capture ? [capture, ...fromUploads] : fromUploads;
}

export async function copyLinks(found: string[], noun: string): Promise<void> {
  if (found.length === 0) {
    await showHUD(`${noun} finished without a link`);
    return;
  }
  await Clipboard.copy(found.join("\n"));
  await showHUD(found.length === 1 ? "Link copied" : `${found.length} links copied`);
}

export async function capture(mode: CaptureMode): Promise<void> {
  if (!preferences().uploadCaptures) {
    await openIshare(`capture/${mode}`);
    return;
  }
  try {
    const envelope = await runTool(["capture", mode, "--upload"], 600);
    if (!envelope.success) {
      if (envelope.error !== "Cancelled") {
        await showToast({ style: Toast.Style.Failure, title: "Capture failed", message: envelope.error });
      }
      return;
    }
    await copyLinks(links(envelope), "Capture");
  } catch (error) {
    if (error instanceof MissingToolError) {
      await openIshare(`capture/${mode}`);
      return;
    }
    await showFailure("Capture failed", error);
  }
}

export async function showFailure(title: string, error: unknown): Promise<void> {
  await showToast({
    style: Toast.Style.Failure,
    title,
    message: error instanceof Error ? error.message : String(error),
  });
}
