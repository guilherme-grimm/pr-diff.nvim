# pr-diff.nvim

Side-by-side GitHub PR review in Neovim. No inline diffs, no browser tab
flipping — and the diff numbers exactly match the PR's "Files changed"
view.

```lua
{
  'guilherme-grimm/pr-diff.nvim',
  dependencies = { 'dlyongemallo/diffview.nvim' },
  opts = {},
}
```

Then: `:ReviewPR <url-or-number>`.

## What it does

1. `gh pr checkout` — the working tree becomes the PR state
2. Resolves the PR's **true merge-base** from GitHub's compare API
3. Fetches just that commit (arbitrary-sha fetch)
4. Opens a diffview side-by-side diff (old | new) against the merge-base

Because it's a *real* checkout (not a diff stream), LSP gives you full
go-to-def / find-references on the author's code state. Press
`<leader>gf` on any diff buffer to open the working-tree version with
gopls/tsserver/etc. attached.

## Requirements

- Neovim >= 0.10
- `gh` CLI, authenticated (`gh auth login`)
- `git`

## Commands & keys (defaults, all overridable via `opts`)

| Key | Command | Action |
|---|---|---|
| `<leader>pr` | `:ReviewPR <url-or-number>` | Check out PR, open side-by-side diff vs its merge-base |
| `<leader>gf` | | Open working-tree version of the diff file under cursor (full LSP) |
| `<leader>dc` | `:DiffviewClose` | Close the review tab |

```lua
opts = {
  command = 'ReviewPR',
  keys = {
    open = '<leader>pr',       -- false to disable
    working_tree = '<leader>gf',
    close = '<leader>dc',
  },
  diffview = {}, -- forwarded to diffview.setup()
}
```

## Why merge-base, not the base branch tip

Diffing against `main`'s tip includes main's own drift since the PR was
cut — a 9-file PR showed up as 3828 files, +112k/−216k. GitHub's UI
shows the three-dot (merge-base) diff; this plugin reproduces it exactly.

It also makes shallow / blobless clones work at all: with depth-1
fetches, `git merge-base` between the PR branch and main returns nothing
(disconnected histories), so the merge-base is resolved server-side via
`gh api repos/{owner}/{repo}/compare/{base}...{head}`.

## Diffview keymap walkthrough

| Key | Action |
|---|---|
| `<tab>` / `<s-tab>` | Next / previous file's diff (main review loop) |
| `]F` / `[F` | Last / first file |
| `]c` / `[c` | Next / previous hunk in file |
| `zo` / `zc` | Open / close folds between hunks |
| `<leader>b` | Toggle the file panel |
| `<leader>e` | Focus file panel (`j`/`k` move, `<cr>` open entry) |
| `gf` | Open file in a normal buffer — from the *right* window only; from the left it opens the merge-base version (see LSP note) |
| `<C-w>gf` | Same, in a new tab |
| `<leader>dc` | Close the whole review tab |

## LSP on review

Diff buffers get treesitter highlighting but **no LSP** — they're
pseudo-buffers (`diffview://...git/<sha>/...`) whose fake path breaks
lsp root detection. Don't fight it. Since this plugin does a real
checkout, working-tree files get full LSP — and the server persists
across file comparisons (one server, one workspace). Find-references
answers are the author's code state, not stale main.

Workflow: `<tab>` through diffs → `<leader>gf` → full navigation → back
to the diff. `<leader>gf` always lands on the PR state regardless of
which side you're on; plain `gf` from the left window opens the
merge-base version, which won't match the disk.

## Gotchas (learned the hard way)

- **Two dots, not three.** Diffview's rev parser wants `main..HEAD`.
  Git accepts `...` too, so shell-level checks pass while diffview fails
  with `Failed to parse rev 'main...HEAD'`.
- **Regular diffs are side-by-side by default.** `view.merge_tool.layout`
  is only for merge-conflict views (`diff3_*`/`diff4_mixed`); setting
  `diff2_horizontal` there is invalid config.
- **First checkout of a PR is slow** on big shallow repos (grafana:
  30–60s, silent); subsequent ones are cached. Rerun `:ReviewPR` if the
  author rebases — everything is re-resolved.
- **Treesitter parser hiccups** are cosmetic: if a PR touches a filetype
  you don't have a parser for (e.g. `.cue`), the install may fail but
  the buffer still opens as plain text.

## Uses the maintained diffview fork

`dlyongemallo/diffview.nvim` — the original `sindrets/diffview.nvim` has
been unmaintained since June 2024. It's a drop-in dependency of this
plugin, so you don't need to add it yourself.

## License

MIT
