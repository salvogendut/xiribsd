# XiriBSD source and release design

Use the existing NetBSD fork for kernel changes, the Xiri repository for
compatibility runtime and desktop integration, and this repository for
release policy and orchestration. Build an installable SGI system from
recorded sources, then derive both delivery formats from one versioned
payload. A release must be reconstructible without any existing Xiri guest
disk or developer's `.work` directory.

## Existing components and gaps

The local source snapshot inspected on 2026-11-14 was:

| Component | Inspected revision or source | Implication |
| --- | --- | --- |
| Xiri integration and lab | `a3b283df395dd76b81154198d1d651d5d63ef96b` | Runtime, import inventories, image packaging and desktop tests already exist. |
| NetBSD fork | `633a79f257a92ff89437f7e17b0b42b49cee3e99` on `xiri` | The source identifies itself as NetBSD `11.99.9`, a development tree. It is not simply the NetBSD 11 release source. |
| Locally recorded upstream reference | `df656f186a9c7c00fe9a9aa8b3f7325871fd008b` | This is the fetched reference recorded by the existing audit, not a promise about the latest upstream commit at a future build. |
| Current selected desktop image | `xiri-netbsd-desktop-20261113-desks` | A useful regression reference, not the input to a new distribution build. |
| Newport Xorg driver | `xsrc` input `b2f7e3892002986f53e61cb0540e281fcbfab335` plus two patches | This is a driver source pin; it does not qualify a complete X11 release at that revision. |

These are audit coordinates, not a proposed release lock. The
[upstream audit](https://github.com/salvogendut/xiri/blob/a3b283df395dd76b81154198d1d651d5d63ef96b/docs/NETBSD-UPSTREAM.md),
[selected-image record](https://github.com/salvogendut/xiri/blob/a3b283df395dd76b81154198d1d651d5d63ef96b/docs/XIRI-IMAGE.md) and
[Newport source manifest](https://github.com/salvogendut/xiri/blob/a3b283df395dd76b81154198d1d651d5d63ef96b/lab/newport-xaa/source.json) contain the
component relationships. In particular, the selected image deliberately
uses an older qualified core kernel and a newer module. Some subsequent
kernel work on the fork has not passed image acceptance. A fresh build of
the branch tip must therefore be qualified as a new combination.

The existing [CHD packager](https://github.com/salvogendut/xiri/blob/a3b283df395dd76b81154198d1d651d5d63ef96b/scripts/build-xiri-image.py) verifies a
halted 8 GiB raw disk, compresses it, verifies the CHD and compares an
extraction against the raw input. It does not fetch and build the whole OS
or create that initial disk. The
[kernel builder](https://github.com/salvogendut/xiri/blob/a3b283df395dd76b81154198d1d651d5d63ef96b/scripts/build-netbsd-kernel.sh) builds tools and a
kernel with X11 disabled; its `kernel.iso` is a file-transfer disc, not a
bootable distribution installer. Preserve these useful lab tools while
adding a complete release pipeline.

## A SGI MIPS target and ABI policy

### First supported profile

Use an `indy` profile with `MACHINE=sgimips` and these explicit ABIs:

| Layer | Build target | Reason |
| --- | --- | --- |
| Installed kernel | `MACHINE_ARCH=mips64eb`, N64/LP64 | Matches the modular compatibility design. |
| Kernel modules | `mips64eb`, built against the same kernel source and configuration | The current MIPS object loader requires N64. The module must match the running kernel. |
| Native base system, X11 and Xiri helpers | `MACHINE_ARCH=mipseb`, o32 | Preserves the working desktop's native userland architecture. |
| Installation environment | Initially o32 `INSTALL32_IP2x` and sysinst | Reuses the established SGI installation path; it must install the selected N64 target kernel and modules. |
| Imported IRIX programs | Supported o32 and n32 subset | These foreign ABIs are handled by `compat_irix_o32`; the module name does not mean o32-only support. |

The [64-bit baseline](https://github.com/salvogendut/xiri/blob/a3b283df395dd76b81154198d1d651d5d63ef96b/lab/netbsd64/README.md) explicitly runs NetBSD
11.0 o32 userland beneath the LP64 kernel. It does not establish a complete
N64 userspace. Keep that working ABI split initially, but rebuild native
userland, kernel and modules from **one selected NetBSD source revision**.
Updating the original release userland to that revision is itself an
acceptance milestone.

Keep independent object, tools, destination and release directories for
each ABI. Never merge their `DESTDIR`s wholesale: compose a final root from
o32 userland and explicitly selected N64 kernels/modules. Do not install
o32 kernel modules alongside the N64 kernel. Test kernel-inspecting o32
utilities such as `ps`, `modstat` and libkvm users as part of this mixed
profile.

A full N64 userland may simplify later builds, but should be introduced as
a separately tested profile. A purely o32 system would need the personality
built into the kernel or additional module-loader development. Neither
change is necessary for the first release.

### Hardware scope

NetBSD calls this machine port `sgimips`; `mips64eb` is the CPU/ABI build
choice, not a claim to support every SGI machine. NetBSD lists Indy,
Indigo/Indigo2 variants and O2 among its supported models, with separate
limitations for other systems. Xiri's tested desktop is narrower.
[NetBSD sgimips hardware list](https://wiki.netbsd.org/ports/sgimips/).

| Profile | Initial release status | Work before claiming support |
| --- | --- | --- |
| Indy R4400 with Newport in the pinned IRIS emulator | Primary qualification target | Fresh-build CD installation and CHD boot, then the existing native/desktop regression suites. |
| Physical Indy | Intended first hardware target | PROM and disk boot, cache/DMA behavior, networking, console, graphics/input and sustained I/O on named CPU/board revisions. |
| Other Indy CPUs and supported Indigo2 variants | Later profiles | CPU/PROM differences, display hardware and memory configurations. |
| O2/IP32 | Later profile | IP3x boot path, kernel, storage, graphics and desktop acceptance. |
| R3000 machines, Octane, other SGI systems | Outside the initial release | Independent port/ABI work where needed; emulator support alone does not establish NetBSD or Xiri support. |

Start the installed kernel configuration from
[`XIRI_IRIX_MODULE`](https://github.com/salvogendut/xiri/blob/a3b283df395dd76b81154198d1d651d5d63ef96b/lab/irix-module/XIRI_IRIX_MODULE). Retain
`MODULAR`, `COMPAT_NETBSD32`, ELF support and the required native fixes.
Preserve the qualified embedded symbol table where needed by the boot path.
Review the lab's fixed `root on sd0a` and disabled Hollywood audio device
when making release profiles: those are Indy-specific choices, not generic
SGI policy. Keep a serial recovery path before enabling graphical login.

Retain the full NetBSD source tree. Removing other architectures would
increase merge conflicts and can break shared build dependencies. Restrict
the build matrix and delivered images instead.

## B Source ownership and upstream updates

### Repository boundaries

| Repository or input | Owns |
| --- | --- |
| `xiribsd` | Top-level build script, source locks, hardware profiles, release overlays, importer specifications, image composition and acceptance policy. |
| `salvogendut/NetBSD-xiri`, branch `xiri` | Required kernel interfaces, personality, native fixes and the small installer/release integration changes. |
| `salvogendut/xiri` | Maintained native runtime, import logic/inventories and reusable regression tools. Pin a commit. |
| NetBSD `xsrc` plus an explicit patch series | X11 sources and the Newport rendering/text fixes. Introduce an xsrc fork if the patch series becomes substantial. |
| Selected third-party sources | Native FAM and any other installed packages, each with source hashes and patches. |
| IRIS and optionally Prismatic | Host-side qualification tools and emulator configurations; not guest OS components. |

Keep the existing `xiri` integration branch, as specified by the
[fork workflow](https://github.com/salvogendut/xiri/blob/a3b283df395dd76b81154198d1d651d5d63ef96b/docs/FORKS.md). Put release policy in this directory
instead of scattering it through lab image scripts. Keep branding in
installer text, `/etc/motd`, a dedicated `/etc/xiribsd-release`, artwork and
release metadata. Preserve `uname`/NetBSD ABI identifiers and module version
paths so tools and package compatibility continue to work.

### Git submodules for source repositories

Use submodules as the source-fetching and revision-pinning mechanism:

| Proposed path | Repository | Use |
| --- | --- | --- |
| `sources/netbsd` | `https://github.com/salvogendut/NetBSD-xiri.git` | Required OS source; select qualified commits from `xiri`. |
| `sources/xiri` | `https://github.com/salvogendut/xiri.git` | Required runtime, import specifications and tests. |
| `sources/xsrc` | `https://github.com/NetBSD/xsrc.git` | Required X11 source, with our patches applied in a separate build checkout. |
| `sources/iris` | `https://github.com/salvogendut/iris.git` | Initialize when emulator qualification is requested. |

The parent repository records each submodule's exact commit in its Git
tree. `.gitmodules` supplies paths and fetch URLs. Together they let a
XiriBSD release commit identify a tested combination without copying the
other repositories into its history.
[Git submodule model](https://git-scm.com/docs/gitsubmodules).

Use public HTTPS fetch URLs so builds do not require a contributor's SSH
credentials. The builder initializes the required submodules itself. Keep
their checkouts at the recorded commits, and apply patches or integrate
upstream in separate checkouts under `work/`. This keeps the pinned inputs
available for comparison. Reject dirty or unexpectedly advanced source
checkouts rather than resetting them automatically.

Normal builds use `git submodule update --init --recursive --checkout`
with explicit required paths. They do not use `--remote`, which selects
remote branch tips instead of the parent's recorded commits. Setting a
submodule's branch to `xiri` does not merge NetBSD `upstream/trunk` into our
fork; that remains the explicit upstream integration stage.
[Git submodule update options](https://git-scm.com/docs/git-submodule).

After a candidate passes, publish its source commits to the appropriate
fork, then commit the new submodule pointers and related lock changes in
XiriBSD together. Retain source archives/bundles for release recovery.
Use checksummed downloads for source tarballs and the planned local
importer for IRIX materials; neither needs a submodule.

### Which upstream line to follow

For the first development release, continue the existing fork's
NetBSD-current lineage and freeze tested commits. Moving everything onto
`netbsd-11` immediately would add a kernel-interface port to the release
engineering work. NetBSD 11.1 is available as a stable alternative, but the
fact that the old guest userland is NetBSD 11.0 does not make the current
fork a stable-branch fork.
[NetBSD 11 release information](https://www.netbsd.org/releases/formal-11/).

For a longer-lived stable product, evaluate a `netbsd-11` maintenance line
after the pipeline works: port the required delta deliberately, repeat the
full tests and then take that branch's fixes. Never silently change the
upstream branch based on whichever release is newest. The source lock
must name the chosen branch as well as the resolved commit.

### Build with updates and build for reproduction

Provide two modes through the same script:

1. **Locked build, the default.** Fetch missing objects/archives and check
   out the exact recorded revisions. Network access does not imply advancing
   the sources. `--offline` uses the same lock from verified caches.
2. **Upstream candidate build.** `--update-upstream` fetches the configured
   NetBSD upstream branch, resolves its commit once, and merges it with the
   selected fork revision in a builder-owned checkout. Resolve `xsrc` and
   its patch set independently. Build and test the resulting candidate,
   then write proposed submodule revisions, a new lock and an integration
   report.

A clean Git merge is not acceptance. If integration conflicts, stop with
the conflicting files and retained checkout; do not drop our fixes, use a
blanket conflict preference, or continue with the previous source tree.
If it builds but fails acceptance, retain diagnostic artifacts and leave
the release lock unchanged. Publish a tested candidate's integration commit
to the fork before using it in a release lock, so a clean machine can fetch
it. Normal builds do not alter sibling checkouts, push merges, or replace
the lab's selected image.

This satisfies the ability to bring upstream changes in **during a build**
without making every rebuild a different product. Prefer merges for the
shared `xiri` branch; keep small patch series for limited xsrc changes.
Review accepted upstream fixes and remove their downstream equivalents.
The [existing upstreaming plan](https://github.com/salvogendut/xiri/blob/a3b283df395dd76b81154198d1d651d5d63ef96b/docs/NETBSD-UPSTREAM.md) already
separates the three core personality interfaces, native fixes, XFS work
and display work.

NetBSD's GitHub repository is a conversion of CVS and explicitly warns
that commit links can change. Retain release Git bundles or complete
source archives with checksums in addition to commits. An upstream history
rewrite must trigger an explicit reconciliation; it is not a reason to
force an unrelated-history merge. Use official CVS/NXR references for
long-lived upstream source citations.
[NetBSD source mirror](https://github.com/NetBSD/src).

### What the source lock records

Treat the committed submodule pointers as authoritative for Git revisions.
The lock records upstream integration policy/base, xsrc patch hashes,
native package sources, kernel configurations and build variables. Generate
the resolved build manifest from those inputs, recording the parent commit,
repository URLs, submodule commits and final patched source tree identities.
Do not maintain a second independently editable set of Git revision pins;
if the lock includes generated copies, require them to match the pointers.
Also record the build
environment digest, compiler/tool versions, image geometry, filesystem
parameters and release timestamp. Qualification records additionally pin
the emulator, machine configuration and locally supplied firmware hash.

For an imported IRIX payload, retain the importer version, installation
identity and per-file manifest. A lock should identify the materials, not
depend on the developer's absolute source path. Keep public and local
payload manifests distinct.

## C Installation CD and preinstalled CHD

### One installation payload

Build these logical components once:

- Native o32 base, configuration, rescue utilities and selected X11 sets.
- The N64 Indy kernel, its boot representation and matching modules.
- Xiri's native runtime, FAM, rc.d integration and configuration defaults.
- Optional imported IRIX runtime/desktop payload, with a separate manifest.

Represent all installed files with hashes, ownership, modes, symlink targets,
device metadata and component ownership. Use that manifest for both the CD
installer and the root tree used to construct the CHD. The two installations
should differ only in declared choices such as accounts, disk geometry and
first-boot state.

Use NetBSD sets for the base system and an explicit Xiri component archive
or package for our runtime. The installer must know how to install it;
placing an extra tar file on the CD is insufficient. A small maintained set
or installer extension is appropriate initially. General pkgsrc binary
repositories can follow later; a full pkgsrc bulk build is not required to
ship the first system.

### Bootable installation CD

Reuse `src/build.sh ... release iso-image`. NetBSD provides separate
release and image operations; X11 is enabled with `-x -X <xsrc>`.
[Build guide](https://www.netbsd.org/docs/guide/en/chap-build.html),
[installation-media guide](https://www.netbsd.org/docs/guide/en/chap-inst-media.html).

The local source has two relevant image paths:

- [`distrib/sgimips/cdroms/installcd/Makefile`](https://github.com/salvogendut/NetBSD-xiri/blob/633a79f257a92ff89437f7e17b0b42b49cee3e99/distrib/sgimips/cdroms/installcd/Makefile)
  builds an installation CD with an SGI volume header. Its installer kernel
  names are currently hard-coded to `INSTALL32_IP2x` and `INSTALL32_IP3x`.
- [`etc/etc.sgimips/Makefile.inc`](https://github.com/salvogendut/NetBSD-xiri/blob/633a79f257a92ff89437f7e17b0b42b49cee3e99/etc/etc.sgimips/Makefile.inc)
  selects 32/64-bit kernel names by `MACHINE_ARCH` and wraps the release CD
  with SGI volume-header loaders. The top-level `iso-image` target invokes
  both the distribution and etc image stages.

The `.iso` output is an SGI bootable disc with ISO9660 data at a partition
offset. A plain `mkisofs` of a root directory, an x86 El Torito recipe, or
renaming a filesystem image cannot replace this layout. Host tools may need
the partition offset to inspect its ISO9660 contents. NetBSD's SGI notes
describe the PROM boot path through `ip2xboot`/`ip3xboot`.
[SGI installation notes](https://cdn.netbsd.org/pub/NetBSD/NetBSD-11.0/sgimips/INSTALL.html).

For the first Indy release, keep the o32 installer and explicitly teach
sysinst to install the N64 Xiri kernel, `/netbsd.boot`, the N64 module set
and the Xiri runtime. The current
[`md.c`](https://github.com/salvogendut/NetBSD-xiri/blob/633a79f257a92ff89437f7e17b0b42b49cee3e99/usr.sbin/sysinst/arch/sgimips/md.c) and
[`md.h`](https://github.com/salvogendut/NetBSD-xiri/blob/633a79f257a92ff89437f7e17b0b42b49cee3e99/usr.sbin/sysinst/arch/sgimips/md.h) identify 32-bit
installation kernels and select `kern-GENERIC32_*` sets. Merely adding
`kernel=XIRI` to a build or copying our kernel beside those sets will not
make sysinst choose it.

Keep upstream boot and ramdisk logic where possible. Add a profile-aware
selection and finalization step, include our component archives, and
regenerate set checksums. Test a blank-disk installation and reboot with
the CD detached. Treat a graphical live CD as a later product: the first
CD is an installer and recovery environment.

Enforce a declared physical CD capacity on the **final wrapped image**.
Start with a conservative 650 MiB ceiling (681,574,400 bytes), then qualify
the chosen media and drive. Exclude debug/compiler/source and optional
application sets from the boot CD when necessary and publish them as
separate downloads. If a local imported payload exceeds the budget, fail
with a size report or require an explicitly selected supplementary disc;
do not silently publish a DVD-sized file as a CD-ROM image.

### Preinstalled hard disk

Create a new raw disk using host-built NetBSD tools. `nbmakefs` can produce
a filesystem without mounting it or requiring root and can use an mtree
specification for target metadata. Use big-endian FFSv1 initially, with
explicit size, timestamp and free-space policy.
[makefs manual](https://man.netbsd.org/makefs.8).

An initial **proposed** 8 GiB geometry, retaining the lab's CHD capacity, is:

| Region | Start sector | Sector count | Purpose |
| --- | ---: | ---: | --- |
| SGI partition 8 | 0 | 4,096 | Volume header, labels and loader; 2 MiB reserved. |
| SGI partition 0 / NetBSD `a` | 4,096 | 14,675,968 | Root FFS, including `/usr` and `/var`. |
| SGI partition 1 / NetBSD `b` | 14,680,064 | 2,097,152 | 1 GiB swap. |
| SGI partition 10 / NetBSD whole-disk `c` | 0 | 16,777,216 | Whole-disk descriptor, intentionally covering the other regions. |

All sectors here are 512 bytes. The CHD geometry `16384,16,64` gives the
same 8 GiB capacity. Physical-disk installation should choose sizes for the
actual device rather than require this emulator layout.

Use `nbsgivol` for the SGI header and loader, `nbdisklabel` where a native
label is written, and `nbmakefs` for root. Generate both partition views
from one layout description. The
[sgimips disklabel code](https://github.com/salvogendut/NetBSD-xiri/blob/633a79f257a92ff89437f7e17b0b42b49cee3e99/sys/arch/sgimips/sgimips/disksubr.c)
checks a native label in the second sector before falling back to the SGI
header; native label writes also update the SGI header. A host raw-file
`disklabel` write does not invoke those kernel hooks. Therefore explicitly
write and check the SGI header as well, reserve label space, and verify
that later loader writes preserve it. Do not assume that copying an FFS
image into an empty file creates a bootable SGI disk.

Install `/usr/mdec/ip2xboot` as volume-header entry `boot`. Retain native
ELF64 `/netbsd` for kernel tools and the ELF32 representation as
`/netbsd.boot`. The qualified lab boot path selects `boot` and
`netbsd.boot`; use it as the starting point and test the freshly built
loader/kernel pair. The header and partition interfaces are documented by
[sgivol](https://man.netbsd.org/sgimips/sgivol.8) and
[SGI boot](https://man.netbsd.org/sgimips/boot.8).

CHD is the delivery encoding of this installed disk, not a conversion of
the CD. Retain the existing `createhd`, `verify`, `extracthd` and full raw
hash comparison workflow. Keep a standalone parentless compressed CHD and
use writable emulator overlays. CHD codecs, hunk size and sector metadata
must match the tested emulator. MAME's `createcd` produces optical media
and does not produce an installed hard disk.
[chdman documentation](https://docs.mamedev.org/tools/chdman.html).

A CHD does not contain the emulator's PROM configuration. Supply a text
machine profile and boot instructions for the tested disk/SCSI ID, plus
the expected firmware identity. Preserve users' existing NVRAM and disk
overlays. Boot both formats from fresh emulator state, without the lab's
TFTP fallback, before claiming that they boot independently.

### IRIX import requirement

**User decision, 2026-11-14:** implement custom scripting that fetches the
relevant materials from an existing IRIX installation. The initial source
interface should accept a locally accessible installation root, including
one exported or mounted from an installed disk. A source-image adapter can
follow, using the existing read-only extraction work.

The importer should:

1. Identify the source release, initially the known IRIX 6.5.22m profile.
2. Select files through maintained component inventories: loader/libraries,
   desktop executables, fonts, app-defaults, catalogs, icons, schemes and
   required helper programs. Resolve symlink and library dependencies.
3. Copy into a staging tree under `/emul/irix`, retaining recorded symlink
   behavior and applying explicit ownership/mode policy. Native aliases
   needed by FAM and desktop integration must be included deliberately.
4. Record source identity and source/destination hashes, missing files and
   unsupported version differences. Fail on missing required components.
5. Generate account lookup files from native NetBSD accounts. Exclude
   source passwords, user homes, saved sessions, host identity and logs.
6. Leave the source installation unchanged and keep imported bytes outside
   the public source repository and public build cache.

Reuse the [import ledger](https://github.com/salvogendut/xiri/blob/a3b283df395dd76b81154198d1d651d5d63ef96b/docs/IRIX-IMPORT.md) and supplemental
resource manifests rather than rediscovering the desktop dependencies.
The top-level builder should accept `--irix-root PATH` and invoke this
logic automatically. Native image construction must not execute MIPS
programs on the build host: generated resources that need an IRIX helper
must be deferred to a guest import/finalization phase.

Make the public image useful with native X11 and the compatibility/runtime
components, plus an importer. Allow a local image with imported desktop
materials from the supplied installation. Public packaging should contain
only the selected distributable components; do not automatically publish
the lab's imported IRIX files, fonts, applications or PROM images. Importer
availability and a populated original IRIX desktop are distinct release
states. This design does not assume that importing files grants permission
to redistribute them.

## Reproducibility and maintenance

Run the normal build without root, using NetBSD's `-U` metadata and a pinned
Linux build environment. Keep host `/etc/mk.conf` and host X11 libraries out
of the target build. A documented container is a useful way to preserve
host prerequisites; it should not depend on the user's named Toolbox.

Set `MKREPRO=yes` and an explicit `MKREPRO_TIMESTAMP`, normalize release
archive ordering/timestamps, and record filesystem and CHD parameters.
Use verified source caches and stable build paths. First establish that a
clean checkout can build the complete release twice. Claim byte-identical
images only after comparing those builds: filesystem identities, generated
databases, signatures and emulator activity can introduce differences.

Build the published disk offline, then run boot tests on disposable
overlays. Create passwords, machine keys and other unique state at install
or first boot. The current lab's empty root password and public test
accounts belong in test fixtures, not release defaults.

Keep the previous release and a recovery kernel available. For updates,
deliver a compatible kernel/module pair and corresponding sets together;
merge configuration changes rather than overwrite user configuration.
Freeze source locks for releases while continuing upstream integration in
candidate builds. Source notices, corresponding source archives and
component provenance belong beside each published release.
