const normalizedSubject = (subject) =>
  String(subject || "")
    .replace(/\s*\(\[?#\d+\]?(\([^)]*\))?\)\s*$/, "")
    .replace(/\s+/g, " ")
    .trim()
    .toLowerCase();

const commitKey = (commit) => `${(commit.scope || "").toLowerCase()}|${normalizedSubject(commit.subject)}`;

const uniqueBy = (items, key) => {
  const seen = new Set();
  return items.filter((item) => {
    const value = key(item);
    if (seen.has(value)) return false;
    seen.add(value);
    return true;
  });
};

const removeDuplicateEntries = (context) => ({
  ...context,
  commitGroups: (context.commitGroups || []).map((group) => ({
    ...group,
    commits: uniqueBy(group.commits || [], commitKey),
  })),
  noteGroups: (context.noteGroups || []).map((group) => ({
    ...group,
    notes: uniqueBy(group.notes || [], (note) => normalizedSubject(note.text)),
  })),
});

module.exports = {
  branches: ["main"],
  tagFormat: "v${version}",
  plugins: [
    ["@semantic-release/commit-analyzer", { preset: "conventionalcommits" }],
    [
      "@semantic-release/release-notes-generator",
      { preset: "conventionalcommits", writerOpts: { finalizeContext: removeDuplicateEntries } },
    ],
    ["@semantic-release/changelog", { changelogFile: "CHANGELOG.md" }],
    [
      "@semantic-release/exec",
      {
        verifyReleaseCmd: "echo ${nextRelease.version} > .next-version",
        prepareCmd: "go run ./tools/cmd/ishare-tools set-version ${nextRelease.version}",
      },
    ],
    [
      "@semantic-release/git",
      {
        assets: ["Config.xcconfig", "CHANGELOG.md"],
        message: "chore(release): ${nextRelease.version} [skip ci]\n\n${nextRelease.notes}",
      },
    ],
    ["@semantic-release/github", { assets: [{ path: "dist/*" }] }],
  ],
};
