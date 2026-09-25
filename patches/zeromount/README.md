# Local ZeroMount patch set

## Combined patch for `zeromount_ksu-next.yml`

The repository-root `rezoss_zeromount_ksu-next.patch` combines upstream patches
**50 -> 51 -> 60 -> 70** into one diff against the unpatched source. Apply it
once from the kernel root after the LTS compile fixes and KernelSU-Next setup;
its `KernelSU-Next/` paths include the driver changes. Do not apply the four
individual patches or local patches 72/73 on top of it.

Validated source revisions (matching failed Actions run `36178871383`):

- Super-Builders: `c2cb71614868fe742cbffee2b6f3126523432673`.
- Samsung kernel: `29d38a6a77fd7a938289204e4f106cd372dbc7ea`.
- Android common LTS: `776976664f31444fa4583d92491a1a9de7bdc4b2`
  (Linux 5.15.216), merged with the base workflow's `-X ours` strategy.
- KernelSU-Next dev: `c61d876480976e553060789759cc4b54c9e7d816`.
  The workflow pins this revision and its setup script to keep the driver API
  matched to the patch. Kernel/LTS source selection remains inherited from
  `plain_build.yml`; later source drift will fail the strict dry-run.

Ordered upstream dry-runs with `--fuzz=0` found 2 rejected hunks in 50,
0 in 51, 1 in 60, and 12 in 70 (after resolving preceding patches).
Adaptations:

- Retain Samsung's `trace/hooks/blk.h` and the LTS `trace/hooks/mm.h`
  includes while adding the original SUSFS declarations.
- Match the existing SUSFS `#endif` comment when adding ZeroMount's statfs
  include. No filesystem hook or ZeroMount/SUSFS implementation is removed.
- Re-anchor patch 70's Kbuild/Kconfig, SELinux helpers, umount guard,
  supercall includes, and init-rc read-hook guard to the current source.
- Guard the current root-profile thread declarations and tracepoint loop as
  intended by patch 70, preserving current profile lifetime and flag handling.
- Preserve the current syscall-table faccessat/stat/execve/execveat handlers;
  add the original SUSFS manual hooks alongside them. Share the existing
  `su_path`, restore the userspace-stack `sh_user_path()` helper required by
  the manual faccessat/stat hooks, and give the legacy manual execveat helper
  a distinct static name to avoid the current syscall-handler signature.
- Keep reboot-kprobe registration/unregistration disabled under SUSFS without
  reintroducing the removed `sulog_init_heap()` call.

The combined patch passes a zero-fuzz dry-run and real application on clean
baseline files; the resulting 43 files match the repaired validation tree.
An independent ordered application confirms the kernel-side result differs
from upstream only by the include-context repairs described above.
All C files touched by the combined patch and the complete KernelSU-Next
driver compiled successfully with KSU, SUSFS, and ZeroMount enabled, after
generating SELinux headers. YAML parsing and `bash -n` passed for the workflow.
This validation does not constitute a full kernel link, flash, or boot test.

## Existing individual patch set for `ZeroMount.yml`

These patches are vendored from `Enginex0/Super-Builders` commit
`c2cb71614868fe742cbffee2b6f3126523432673` and are maintained locally for
this Samsung SM8550 Android 13 / Linux 5.15 build.

Apply order:

1. `50_add_susfs_in_gki-android13-5.15.patch`
2. `51_enhanced_susfs-android13-5.15.patch`
3. `60_zeromount-android13-5.15.patch`
4. `70_ksu_safety-kernelsu-next-5.15.patch` (inside `KernelSU-Next`)

Local adaptations:

- **50**: Samsung `fs/namespace.c` already contains
  `#include <trace/hooks/blk.h>`, so that line is retained as patch context.
  This folds the former `samsung_susfs_namespace_5.15.211_fix.patch` into the
  base SUSFS patch.
- **51**: unchanged from the pinned Super-Builders source.
- **60**: unchanged from the pinned Super-Builders source.
- **70**: adapted to current KernelSU-Next by restoring the `sh_user_path()`
  userspace-stack helper used by the SUSFS/manual-hook `faccessat/stat` path,
  and by updating the `supercall.c` tail hunk for KernelSU-Next versions where
  `sulog_init_heap()` is no longer present. This folds the former
  `ksu_safety_supercall_v3.3.0_fix.patch` into patch 70.

`ZeroMount.yml` intentionally consumes only this local directory so a future
change in Super-Builders cannot silently change an otherwise identical build.
