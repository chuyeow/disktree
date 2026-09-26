# DiskTree

A native macOS app that shows where your disk space goes: a nested treemap of a folder
(your home folder by default), colour-coded by type of storage, with anything safe to
delete shown hatched.

- **By type**: Code, Git, Toolchains, Cache, Agent scratch, Synced, Media, Documents, Apps, System, Trash, Other.
- **Reclaimable**: *Safe* (caches, build output, `node_modules`, DerivedData, Trash) and
  *Worth a look* (worktrees, Downloads, installers, simulators, Docker, device backups), each with a reason.
- Click to select, double-click to zoom in, ⌘↑ to zoom out, right-click to Reveal in Finder or Move to Trash.
  Clicking a type in the legend or sidebar highlights it.

## Download

Every merge to `main` builds `DiskTree.dmg`; grab it from the latest
[Build DMG](../../actions/workflows/dmg.yml) run's artifacts. The app is ad-hoc signed, not
notarized: on first launch, right-click it and choose Open.

## Build

```sh
swift test               # classifier, treemap layout, scanner
./scripts/bundle.sh      # builds DiskTree.app
open DiskTree.app        # or: open DiskTree.app --args --root ~/code
```

The app icon lives in `assets/`: `drive.png` is the generated render, and
`scripts/make_icon.py` (needs Pillow) builds `AppIcon.icon` from it. `bundle.sh` compiles
that with `actool`.

Grant DiskTree **Full Disk Access** (System Settings → Privacy & Security). Without it,
macOS shows privacy prompts for protected folders such as other apps' containers, and the
scan waits until you answer them.

Sizes are allocated bytes on disk. Hard links and APFS clones are counted once per path.
Files under 1 MB are grouped into "small items" leaves to keep memory low.
