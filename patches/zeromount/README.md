# Local ZeroMount patch set

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
