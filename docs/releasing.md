# Releasing Unbound

Releases are prepared automatically when the owner pushes a version tag. The
workflow tests that exact commit, packages the addon, and creates a **draft** GitHub
release. The owner reviews and publishes it. Ordinary branch pushes do not prepare
releases, and nothing publishes automatically.

The version in [Unbound.toc](../Unbound/Unbound.toc) is the source of truth. A version
`0.3.0` requires the tag `v0.3.0` and produces `Unbound-0.3.0.zip`. Versions use three
numbers: `MAJOR.MINOR.PATCH`. Use GitHub's pre-release checkbox for preview releases;
there is no need to add a suffix to the tag.

## One-time setup

1. In VS Code, review the changes in **Source Control**, stage them, and commit them
   yourself. A suitable message is `Add automated draft releases`.
2. Push the commit to `main` using **Git: Push** in the Command Palette
   (`Ctrl+Shift+P`). If you work on a separate branch, merge it into `main` first,
   then return to an up-to-date local `main`.
3. On GitHub, open the repository's **Actions** tab and confirm that **Tests** passes.

The [release workflow](../.github/workflows/release.yml) is the configuration;
there is no separate release-automation switch to enable. It uses GitHub's temporary
`GITHUB_TOKEN`, with `contents: write` only on the release job. Do not create a
personal access token, add a secret, or enable write access for all workflows.
Standard GitHub-hosted runners are free for this public repository; GitHub Pro
is not required.

The workflow must already be in the commit you tag. There is no **Run workflow**
button: pushing the tag is the trigger.

## Prepare a release, step by step

### 1. Prepare the code

1. Work on `main` and finish the relevant [in-game checks](client-checks.md).
   Automation does not verify real chat delivery, hardware events, or taint.
2. Check `## Version` in [Unbound.toc](../Unbound/Unbound.toc). For the first
   `0.3.0` preview, it can stay as it is. For subsequent releases, choose a new
   version and commit that change along with the code being released.
3. Commit and push your changes yourself. Make sure Source Control has no
   uncommitted release changes and GitHub's **Tests** run is green.

A tag points to a commit, not to unsaved or uncommitted files. Do not tag until the
intended release code and workflow are both committed.

### 2. Create and push the tag in VS Code

1. Open the Command Palette (`Ctrl+Shift+P`).
2. Run **Git: Create Tag...**. If asked, select the Unbound repository.
3. Enter `v0.3.0`, or `v` followed by the version you just prepared.
4. If asked for a tag message, enter something like `Unbound 0.3.0`.
5. Open the Command Palette again and run **Git: Push Tags**. If asked for the
   remote, select `origin`.

**Push Tags pushes all local tags that are not already on the remote**, not just
the newest one. Avoid accumulating experimental `v...` tags: each matching tag can
start a release run. Push one release tag at a time.

Creating a local tag alone does not start automation. Pushing the branch alone
does not necessarily push tags either; **Push Tags** is the explicit release step.

### 3. Watch GitHub prepare the draft

1. Open [Actions](https://github.com/skiotha/unbound/actions).
2. Select **Prepare release** and open the run for your tag.
3. Wait for both the test job and the release job to pass.
4. Open [Releases](https://github.com/skiotha/unbound/releases) while signed in as
   the owner. Find the draft titled, for example, **Unbound 0.3.0**.

The workflow:

- Reuses the [Lua 5.1 test workflow](../.github/workflows/test.yml); a test failure
  blocks release preparation even if an earlier branch run passed.
- Checks that the tag matches the TOC version and that the manifest's files and
  addon icon exist.
- Packages only the [addon folder](../Unbound/) and a copy of the
  [MIT license](../LICENSE) placed inside it.
- Checks the ZIP file list against the staged files.
- Attaches the ZIP and generates initial release notes, leaving the release a draft.
- Requires the tag to exist; it never creates or moves tags, replaces an existing
  release, or publishes one.

You may also see a separate **Tests** run for the tag, because normal CI tests every
push. The tests inside **Prepare release** are the ones that gate its release job.

### 4. Review and publish

1. Open the draft's edit screen.
2. Review the title and replace or improve the generated release notes. For the
   first release, a short feature summary and known limitations are more useful
   than the repository's whole development history.
3. Confirm that the attached asset is named `Unbound-<version>.zip`.
4. Download and extract it into a temporary folder. The ZIP holds exactly one
   top-level folder, `Unbound`, with the TOC directly inside it, plus the Lua files,
   media, and license. There should be no repository-name wrapper, tests, or docs.
   Windows' **Extract All** adds an `Unbound-<version>` folder around it; that
   folder comes from the extraction, not from the ZIP.
5. For a `0.x` preview, select **This is a pre-release**. The roadmap's stable
   first-release milestone remains `1.0`; adding this automation does not complete it.
6. Click **Publish release** when satisfied.

Drafts are not public downloads. Publishing makes the release and its attached ZIP
available to users. Share the repository's **Releases** link and tell users to
download the `Unbound-<version>.zip` asset, **not** GitHub's automatic **Source code**
archives. Those source archives are separate and contain the repository source.

Keep published tags and assets unchanged. A correction should get a new version
and a new tag.

## If something fails

- **No release run appears:** check that the tag was pushed to `origin`, starts
  with lowercase `v`, and points to a commit containing the release workflow.
  Check **Settings > Actions > General** if Actions has been disabled.
- **Version mismatch or missing file:** the log names the problem. Fix it in a new
  commit and use a new matching version/tag. Re-running the old tag still uses the
  old commit, not the corrected `main`.
- **Tests fail:** fix the code before preparing another release. Do not bypass the
  test job to publish a ZIP.
- **Temporary runner/network failure:** open the failed Actions run and use
  **Re-run failed jobs** after checking whether a draft was already created.
- **A draft exists but the ZIP upload failed:** inspect it first. If it is only an
  incomplete, unpublished draft, delete that draft on GitHub, leave its tag in
  place, and re-run the failed job to recreate it. Do not delete a published release.
- **Release already exists:** the workflow will not overwrite it. Review the
  existing draft, or use a new version for a correction to a published release.
- **Permission denied:** inspect the failed step. The release job already requests
  the required token permission; repository or organization policies may restrict
  it. Do not work around this by adding a broad personal access token.

No addon code or SavedVariables are changed by this release process.
