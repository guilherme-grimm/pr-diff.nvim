-- pr-diff.nvim: side-by-side GitHub PR review in Neovim.
--
-- One command: `:ReviewPR <url-or-number>` checks out a PR, resolves its true
-- merge-base from GitHub's compare API, and opens a diffview side-by-side
-- diff that exactly matches the PR's "Files changed" view — even on shallow
-- or blobless clones where no local merge-base exists.
--
-- Because it does a real checkout, the working tree becomes the PR state,
-- so LSP (gopls, tsserver, ...) gives full go-to-def / find-references on
-- the author's code, not stale main. See README for the review workflow.

local M = {}

---@class pr-diff.Opts
---@field command string user command name
---@field keys table<string,string|false> keymaps; set a value to false to skip
---@field diffview table options forwarded to diffview.setup()
local defaults = {
  command = 'ReviewPR',
  keys = {
    open = '<leader>pr',
    working_tree = '<leader>gf',
    close = '<leader>dc',
  },
  diffview = {}, -- regular diffs are side-by-side by default
}

local opts = nil

-- Small async-run helper: run cmd, call fn(result) on the main loop.
local function run(cmd, fn)
  vim.system(cmd, { text = true }, function(res)
    vim.schedule(function()
      fn(res)
    end)
  end)
end

local function fail(msg)
  vim.notify('[pr-diff] ' .. msg, vim.log.levels.ERROR)
end

local function info(msg)
  vim.notify('[pr-diff] ' .. msg, vim.log.levels.INFO)
end

-- "https://github.com/owner/repo/pull/123" | 123 | "123" -> "123"
local function pr_number(ref)
  return ref:match('/pull/(%d+)') or ref:match('^%d+$') or ref
end

local function repo_slug()
  local remote = vim.fn.system('git remote get-url origin'):gsub('%s', '')
  return remote:match('github%.com[:/](.-)%.git$') or remote:match('github%.com[:/](.+)$')
end

-- Open the diffview tab for the current branch against the given rev.
local function open_diff(rev, pr_no)
  -- NB: diffview wants TWO dots (..), not git's ...
  vim.cmd('DiffviewOpen ' .. rev .. '..HEAD')
  info(('Reviewing PR #%s (merge-base: %s)'):format(pr_no, rev:sub(1, 10)))
end

-- Resolve the PR's true merge-base from GitHub, fetch it, then open the diff.
-- In shallow clones `git merge-base` returns nothing (disconnected
-- histories), and a two-tree diff vs the base *tip* would include main's own
-- drift since the PR was cut. The compare API solves both.
local function open_at_merge_base(pr, pr_no)
  local slug = repo_slug()
  if not slug then
    fail('not a GitHub remote')
    return
  end

  local url = ('repos/%s/compare/%s...%s:%s'):format(
    slug, pr.baseRefName, pr.headRepositoryOwner.login, pr.headRefName
  )

  run({ 'gh', 'api', url, '--jq', '.merge_base_commit.sha' }, function(cmp)
    local mb = vim.trim(cmp.stdout or '')
    if cmp.code ~= 0 or mb == '' then
      fail('could not get merge-base from GitHub:\n' .. (cmp.stderr or ''))
      return
    end

    run({ 'git', 'fetch', 'origin', mb }, function(fetch)
      if fetch.code ~= 0 then
        fail('git fetch of merge-base failed:\n' .. (fetch.stderr or ''))
        return
      end
      open_diff(mb, pr_no)
    end)
  end)
end

---Review a GitHub pull request side-by-side.
---@param ref string|number PR URL or number
function M.review(ref)
  ref = vim.trim(tostring(ref or ''))
  if ref == '' then
    vim.notify('Usage: ' .. (opts and opts.command or 'ReviewPR') .. ' <pr-url-or-number>', vim.log.levels.WARN)
    return
  end

  local pr_no = pr_number(ref)
  info('Fetching PR ' .. pr_no .. ' ...')

  -- Resolve PR metadata first (accepts full URLs).
  run({ 'gh', 'pr', 'view', pr_no, '--json', 'number,baseRefName,headRefName,headRepositoryOwner' }, function(res)
    if res.code ~= 0 then
      fail('gh pr view failed:\n' .. (res.stderr or res.stdout or ''))
      return
    end

    local ok, pr = pcall(vim.json.decode, res.stdout)
    if not ok or type(pr) ~= 'table' or not pr.headRefName then
      fail('could not parse PR info')
      return
    end

    run({ 'gh', 'pr', 'checkout', tostring(pr.number) }, function(checkout)
      if checkout.code ~= 0 then
        fail('gh pr checkout failed:\n' .. (checkout.stderr or checkout.stdout or ''))
        return
      end
      open_at_merge_base(pr, pr.number)
    end)
  end)
end

---Open the working-tree version of the diff file under the cursor.
---The working tree == the PR state (real checkout), so LSP attaches with
---the author's code state. Works from either diff side.
function M.open_working_tree()
  local name = vim.fn.bufname()
  local path = name:match('^diffview://.-/%.git/[0-9a-f]+/(.+)$')
  if not path then
    vim.notify('Not in a diff buffer', vim.log.levels.WARN)
    return
  end
  vim.cmd.edit(path)
end

---@param user_opts pr-diff.Opts?
function M.setup(user_opts)
  opts = vim.tbl_deep_extend('force', defaults, user_opts or {})

  require('diffview').setup(opts.diffview)

  vim.api.nvim_create_user_command(opts.command, function(input)
    M.review(input.args)
  end, { nargs = '?', desc = 'Checkout and review a GitHub PR side-by-side' })

  local k = opts.keys
  if k.open then
    vim.keymap.set('n', k.open, ':' .. opts.command .. ' ', { desc = '[P][R] review', silent = false })
  end
  if k.working_tree then
    vim.keymap.set('n', k.working_tree, M.open_working_tree, { desc = 'Open working-tree version of diff file (full LSP)' })
  end
  if k.close then
    vim.keymap.set('n', k.close, '<cmd>DiffviewClose<cr>', { desc = 'Close the diffview tab' })
  end
end

return M
