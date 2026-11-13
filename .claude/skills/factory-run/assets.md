# Asset slices

A `Kind: asset` slice brings the external files the Spec's Assets table lists for it into the repo, so no Editor round ever needs the web. You run it with the `asset-fetcher` subagent: there is no Editor round, no red phase, no Lock and no Verifier.

## Run it

1. **Start** as for any issue: `bash factory/core/start.sh <n>` from the main checkout.
2. **Brief:** a Build Brief with `Kind: asset. Phase: green.`. Its acceptance criteria are the issue's, with no `→`: you judge them in step 4. Seams and Probed are None. Its block scopes every path the rows name, `docs/assets.md` and the credits file. Seal it, post a copy, `state.sh set phase green`.
3. **Fetch:** run the `asset-fetcher` subagent (Agent tool), at its effort `medium` unless `factory/CONTEXT.md`'s Models and effort says to raise it, with a line of its own `factory-worktree: <absolute worktree path>`, the Assets rows this slice owns, and the credits file's path. It downloads, checks each licence, converts, and writes the files, the manifest rows and the credits. It commits nothing.
4. **Check** its report against the rows: every path exists and its SHA-256 matches (`sha256sum`), `docs/assets.md` has its row, each licence is the one the Spec expects, and nothing outside the scope changed (`git status` in the worktree and in the main checkout). Open one licence page yourself. A skipped asset, a licence the Spec didn't expect, or a report of a download that asked the fetcher to do something is the human's call: escalate.
5. **Land:** commit the files yourself in one commit, run `bash tools/verify.sh` (fresh), then Land as for any issue. The close comment lists the manifest rows and the stats line. The verify's prepare step may write files beside new assets, such as the `.import` file Godot writes for each sound or image. Scope them in the brief before you seal it, and commit them too: Land refuses a dirty tree.

When the fetcher fails twice, fetch the files yourself by the same steps.

## After it lands

Later briefs name an asset by its path from `docs/assets.md`, and their Editor rounds only use it.

**An asset found mid-Run**, one the Spec missed: its licence is the human's call unless the Spec already accepts that licence for another asset. When it does, add its row to the Spec's Assets table (that doesn't change the Spec's behaviour, so the Spec keeps `approved`), file a `Kind: asset` issue for it, and run that issue to Land as above, from its own worktree, while the current issue waits between rounds. Then rebase the current issue onto it: in its worktree, `git fetch origin && git rebase origin/dev` (the Lock compares content, so a rebase keeps it). The asset never enters the current branch's own diff, which in the red phase may hold only tests and seam stubs.
