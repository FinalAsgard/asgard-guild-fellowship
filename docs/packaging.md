# Packaging and releases

One tagged source revision produces one package that supports both WoW: Forever and Retail. The package holds both production manifests, and each client loads only its own:

| Client | Manifest | Packager game type |
| --- | --- | --- |
| WoW: Forever | `AsgardsGuildFellowship_Camelot.toc` | `forever` |
| WoW Retail | `AsgardsGuildFellowship_Mainline.toc` | `retail` |

The [BigWigs packager](https://github.com/BigWigsMods/packager) reads these suffixes to tag each client's game versions, so CurseForge offers the file to both clients. Only use suffixes the packager recognizes. An unrecognized one silently drops that client. The add-on name, manifest list, and pinned packager commit live in `tools/project.env`.

`.pkgmeta` excludes tests, tools, docs, `ai/`, lint/test config, and CI files.

## Versions

The version comes from the release tag. Both production manifests declare `## Version: @project-version@`, which the packager replaces with the tag (for example `v0.2.0`). That's the version shown in the in-game AddOns list and on CurseForge. **Never hard-code a version in a manifest.** `tools/check-release-tag.sh` and the test suite both reject that. Non-release builds, such as pull request packages, get a commit-based version instead.

Tags look like `v1.2.3`. Pre-releases add a suffix such as `v1.2.3-beta1` or `v1.2.3-alpha2`.

## Build and inspect locally

```sh
PACKAGER_BASH=/opt/homebrew/bin/bash tools/build-package.sh   # macOS needs bash 4.3+
unzip -l .release/AsgardsGuildFellowship-*.zip
```

The script never uploads. It fails unless the build is tagged for both clients, then runs `tools/check-package.sh`, which fails when:

- a production manifest is missing, or a file it loads isn't in the zip
- the manifests disagree on the version, still contain `@project-version@`, or (during a release) don't match the tag
- development files (tests, tools, docs, `ai/`, CI, lint config) were packaged
- any other `.toc` was packaged

CI runs the same build on every pull request (**Release package** job) and keeps the zip as a downloadable artifact for 30 days.

## Cutting a release

1. Confirm each client's interface number in game (`/dump (select(4, GetBuildInfo()))`). If it changed, run `tools/set-interface.sh <forever|retail> <interface>`.
2. On GitHub, go to **Releases → Draft a new release**:
   - **Choose a tag**: type the new tag, e.g. `v0.2.0`, and create it on `main`. Nothing needs editing beforehand, because the tag *is* the version.
   - **Title / notes**: whatever players should read. The notes become the changelog.
   - **Set as a pre-release**: check it for `alpha`/`beta` tags, and leave it unchecked otherwise. The workflow enforces this.
   - Click **Publish release**. Saving a draft or pushing a bare tag does nothing.
3. Watch the **Release** run under **Actions**. It checks the tag, runs lint and tests, builds and validates the package, uploads to CurseForge (once enabled), and attaches the zip to the release.

If a run fails before uploading, fix the cause, delete the release and its tag, and publish again.

## Enabling CurseForge uploads

CurseForge upload is **off until the project ID is set**. Until then, releases still build and attach the zip to the GitHub release, and the run shows a notice that CurseForge was skipped.

One-time setup:

1. Create the add-on project on CurseForge (World of Warcraft → AddOns) and copy its **Project ID** from the About panel.
2. In GitHub, go to **Settings → Secrets and variables → Actions**:
   - **Secrets**: add `CF_API_KEY` with a token from <https://legacy.curseforge.com/account/api-tokens>. Add this first.
   - **Variables**: add `CURSEFORGE_PROJECT_ID` with the numeric project ID. Setting this turns uploads on.
3. Leave CurseForge's own automatic packaging off and don't add its webhook. This workflow already uploads each release, so enabling both would upload every version twice.

If the variable is set but the secret is missing, or the ID isn't numeric, the upload step fails with a message naming the problem.
