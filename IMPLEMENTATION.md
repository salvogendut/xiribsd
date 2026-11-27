# XiriBSD build implementation plan

Implement one public command, `./build.sh`, in this directory. It should
orchestrate NetBSD's existing builder and image utilities, plus internal
helpers where parsing or binary layout requires them. Users should never
have to run a sequence of lab preparation scripts. The commands below
specify the future interface; they are not implemented by this documentation.

## Proposed command interface

```sh
./build.sh
./build.sh --update-upstream
./build.sh --offline
./build.sh --irix-root /path/to/installed-irix
./build.sh --profile indy --jobs 2
./build.sh --verify --firmware /path/to/indy-prom
```

The default initializes the required source submodules and builds both
the CD installer and preinstalled CHD from their committed revisions and
the accompanying source lock. `--update-upstream` integrates and builds an
upstream candidate and emits proposed revisions/lock changes; it does not
silently advance the release pointers. `--irix-root` adds the planned
installation importer and labels the result as a local populated image.
Flags may be combined.

Always run structural checks, set/manifest checks and the CHD round trip.
`--verify` additionally runs the emulator acceptance suite using the supplied
firmware and a pinned emulator built or obtained by the same script. A
build without that phase is marked **built, boot qualification pending**.
Release qualification requires these boot checks; firmware availability
must not be hidden behind reuse of a developer's guest state.

Use resumable stages with input hashes. A stage can be reused only if its
source, configuration, toolchain and dependency identities match. Keep logs
and failed staging directories, publish completed artifacts atomically,
and return nonzero on failure. Default kernel/module concurrency to two
jobs, matching the existing project's build policy.

## Proposed repository layout

```text
xiribsd/
  build.sh                    single public build entry point
  .gitmodules                 source repository paths and HTTPS fetch URLs
  sources.lock.json           non-Git inputs, patches and build policy
  sources/                    submodule revisions tracked by the parent
    netbsd/                   NetBSD-xiri
    xiri/                     Xiri runtime and integration
    xsrc/                     NetBSD X11 sources
    iris/                     emulator, initialized for verification
  config/
    builder/                 pinned container recipe and host dependencies
    profiles/indy.json        ABI, kernel, disk and emulator choices
    mk.conf                  release build settings
    sets.json                selected components and install order
    irix/6.5.22m.json         import component inventory
  overlays/                  owned configuration and branding files
  patches/xsrc/              small ordered Newport patch series
  lib/                       internal build/import/image helpers
  tests/                     image inspection and acceptance drivers
  cache/                     verified downloads and repository objects
  work/                      isolated sources, tools, objects and staging
  out/                       completed releases and reports
```

Keep `cache`, `work` and image outputs out of Git. Preserve the current
sibling repositories as development inputs only when explicitly selected;
the normal clean build fetches its own sources. No required path should
contain a particular username, `.work` snapshot name or preexisting Toolbox.

For an ordinary build, the script runs this after checking that existing
source checkouts have no local changes or unexpected revision differences:

```sh
git submodule update --init --recursive --checkout -- \
  sources/netbsd sources/xiri sources/xsrc
```

Initialize `sources/iris` the same way for `--verify`. A recursive clone is
also supported, but is not a prerequisite for the single build command.
For `--offline`, require initialized repositories and all required objects
locally before updating with `--no-fetch`; missing submodules must not
trigger a network clone. Avoid shallow-history requirements for the NetBSD
integration checkout, which needs merge ancestry. Keep source modifications
in builder-owned checkouts and object files outside the submodule trees.
The submodule pointers supply Git revisions; the resolved build manifest
combines them with the source lock's additional inputs.
[Git submodule command](https://git-scm.com/docs/git-submodule).

Use an x86-64 Linux host as the first supported build host. The script can
enter a pinned Podman/Docker environment itself, preserving the one-command
interface. Document a direct-host route with the same tool versions later.
The builder environment needs Bash, Python 3, Git, a host C/C++ compiler,
make, development headers and archive/download utilities. Supply a pinned
`chdman` in that environment or build it from recorded MAME sources.
NetBSD's tools stage supplies the target compilers and utilities such as
`nbmakefs`, `nbsgivol` and `nbdisklabel`. If the selected ISO path requires
an external mkisofs-compatible program, pin that too. Emulator validation
additionally needs the selected IRIS toolchain/dependencies and local PROM
input; it is not required to compile the guest OS.

## Build stages and their outputs

| Stage | Required behavior | Output |
| --- | --- | --- |
| 1 Preflight | Validate configuration, host environment, free space and tool availability. Check source/output paths before cleanup. | Environment report and resolved build configuration. |
| 2 Fetch | Initialize required submodules at the committed revisions and fetch checksummed package sources. In update mode, resolve upstream once and integrate in isolated checkouts. | Source manifest and proposed revisions/lock where applicable. |
| 3 Prepare | Apply recorded xsrc patches, select release kernel configs, materialize overlays and installer changes. Reject incomplete patches or unexpected dirty inputs. | Immutable input tree identities. |
| 4 Cross-build | Build o32 native release/X11 and separate N64 kernel/modules from the same src revision. | Target binaries, sets, toolchains and metadata. |
| 5 Build runtime | Cross-build FAM and Xiri helpers against the freshly built o32 sysroot and X11. | Runtime component with file metadata. |
| 6 Import when requested | Read the supplied IRIX installation and apply the component inventory. | Local payload plus import report. |
| 7 Compose | Select base/X11 sets, the N64 kernel and modules, runtime and optional imported component. Generate final manifests and checksums. | One canonical installation payload and root staging tree. |
| 8 Make CD | Run the SGI-aware image path with the selected payload and patched installer. Enforce the CD capacity. | Bootable installation `.iso`. |
| 9 Make disk | Create fresh SGI partition metadata, loader, FFS root and swap in a new raw file; encode and verify CHD. | Standalone installed `.chd`. |
| 10 Verify | Inspect image metadata and installed contents; optionally boot disposable test machines and install from CD onto a blank disk. | Machine-readable acceptance report and logs. |
| 11 Finalize | Hash artifacts, archive source/provenance and atomically place completed outputs. | Release directory; qualification status remains explicit. |

Plan for source, two toolchains/object trees, staged sets, an 8 GiB raw
image and another 8 GiB extraction at peak. A 100 GiB free-space starting
budget is a planning allowance, not a measured minimum. Measure actual
usage during the first complete build and replace this allowance with
documented requirements.

## NetBSD build integration

The following illustrates the underlying commands the wrapper will issue.
All variables are absolute paths or values resolved by the wrapper. This
is a sequence outline, not a complete script; custom set composition and
installer wiring described below are essential.

```sh
# o32 native base, X11, boot tools and installation environment
"$SRC/build.sh" -m sgimips -a mipseb -U -j 2 \
  -O "$OBJ32" -T "$TOOLS32" -D "$DEST32" -R "$REL32" \
  -x -X "$XSRC" \
  -V "MAKECONF=$MKCONF" \
  -V MKREPRO=yes -V "MKREPRO_TIMESTAMP=$EPOCH" \
  -V MKKMOD=no \
  tools release

# matching N64 kernel and separate module toolchain
"$SRC/build.sh" -m sgimips -a mips64eb -U -j 2 \
  -O "$OBJ64" -T "$TOOLS64" -D "$DEST64" -R "$REL64" \
  -V "MAKECONF=$MKCONF" \
  -V MKREPRO=yes -V "MKREPRO_TIMESTAMP=$EPOCH" \
  -V MKX11=no \
  tools "kernel=$XIRI_KERNEL_CONFIG" modules
```

Invoke these from the source root, with a controlled environment. Check
the selected revision's `BUILDING` for module install/set targets and
resulting paths. `MKKMOD=no` is specific to the o32 release: install the
modules from the N64 build instead. The release composer must account for
all modules the installed kernel needs, not just the IRIX personality.

Use the same path/build variables when generating the final `iso-image`.
NetBSD's release targets can generate multiple images; explicitly select
and rename the tested installer artifact. Do not accidentally publish an
upstream-only ISO produced before the Xiri components were incorporated.

NetBSD's [build guide](https://www.netbsd.org/docs/guide/en/chap-build.html)
documents cross-building, unprivileged builds and xsrc selection. The local
[`BUILDING`](https://github.com/salvogendut/NetBSD-xiri/blob/633a79f257a92ff89437f7e17b0b42b49cee3e99/BUILDING) and
[`build.sh`](https://github.com/salvogendut/NetBSD-xiri/blob/633a79f257a92ff89437f7e17b0b42b49cee3e99/build.sh) are authoritative for the selected
fork revision. Reuse the current host C dialect settings only where the
pinned compiler needs them; the lab builder already documents a GCC 16
host-tools issue handled with `gnu17`.

### Kernel and modules

Maintain an explicit Indy release config, derived from the current module
config. Generate both native `netbsd` and its `netbsd.elf32` boot form.
Package the latter as `/netbsd.boot` and configure the boot loader to select
it. Keep the native kernel as `/netbsd`.

Extend normal module/set integration. The current fork wires
`sys/modules/compat_irix_o32`, but the
[existing audit](https://github.com/salvogendut/xiri/blob/a3b283df395dd76b81154198d1d651d5d63ef96b/docs/NETBSD-UPSTREAM.md#what-must-be-prepared-for-the-module-submission)
found no corresponding IRIX module distribution-set entry. Add the proper
architecture-gated entries and test set completeness. Derive module paths
from the target build's `KMODULEDIR`/OS release values rather than a
hard-coded `11.99.9` directory.

For the mixed ABI release, compose an explicitly identified N64 kernel and
module component; do not relabel o32 modules as N64 or let the o32 release
stage overwrite them. Configure boot-time `modules` loading through native
rc.d and `/etc/modules.conf`. Check undefined module symbols and supported
relocations, as the existing
[module build audit](https://github.com/salvogendut/xiri/blob/a3b283df395dd76b81154198d1d651d5d63ef96b/scripts/build-irix-module.py) does, then check
actual loading at normal securelevel.

### Native runtime and X11

Port [`runtime/Makefile`](https://github.com/salvogendut/xiri/blob/a3b283df395dd76b81154198d1d651d5d63ef96b/runtime/Makefile) to cross-build with
parameterized X11 include/library paths and the o32 sysroot. Its current
absolute `/usr/X11R7` build paths assume a native guest. Compile native
helpers; stage shell scripts as data; do not execute target binaries on
the host. Extend the installer to emit METALOG-compatible ownership and
mode entries for an unprivileged build.

Adapt the [existing FAM builder](https://github.com/salvogendut/xiri/blob/a3b283df395dd76b81154198d1d651d5d63ef96b/scripts/build-native-fam.py) to
accept the new toolchain/sysroot and output directories. Preserve its
multi-user fixes and source hashes, removing dependence on lab paths.
Use the fork-built rpcbind and maintained Xiri rc.d/session configuration.

Apply both Newport patches to the pinned xsrc tree and build the driver
with the X server it will accompany. The
[qualified driver](https://github.com/salvogendut/xiri/blob/a3b283df395dd76b81154198d1d651d5d63ef96b/lab/newport-xaa/README.md) uses Xorg 1.10.6 and
video-driver ABI 10.0. A newer server may change the integration requirements;
reusing the old `newport_drv.so` is not a release strategy. Verify that the
selected src/xsrc build still chooses a working Newport server path.
Reassess the current `-dumbSched` workaround against that built server.

### Installer and payload ownership

Patch the SGI sysinst kernel-set mapping for the Xiri Indy profile. Keep
disk selection, partitioning and base extraction in sysinst; add the
distribution component selection and finalization needed for the mixed
kernel/userland installation. Ensure an o32 installer does not execute an
N64 helper from the installed target during finalization.

Define a single installation order and ownership manifest. The composer
must exclude conflicting stock kernel/module choices and install the
selected replacements exactly once. Include runtime configuration,
bootloader choice, `/etc/fstab`, device metadata and account/first-boot
setup in the shared plan. A successful CD installation and the CHD root
must match that plan, excluding documented machine-specific state.

## Disk assembly and CHD encoding

Prototype the proposed layout in [the design](DESIGN.md#preinstalled-hard-disk)
against a disk created by sysinst. Reuse the source-built host tools and
compare the SGI header, partition offsets, checksums and the NetBSD view.
Prefer this host assembly path over booting a historical disk and modifying
it. If host metadata generation exposes a tooling gap, an automated fresh
installation in an emulator is a useful reference/fallback, but must be
declared as a firmware-dependent stage and start from a blank disk.

Use the staged METALOG/mtree data for root ownership, permissions, device
nodes and hard links. NetBSD's `makefs` can construct the target filesystem
without host root privileges.
[makefs manual](https://man.netbsd.org/makefs.8).

Check root capacity and free inodes/blocks, then place the filesystem at
the declared offset without truncating the full disk. Initialize the SGI
header, write explicit root/swap/whole-disk entries, and install `ip2xboot`.
Native disklabel and volume-header values must agree. Test header geometry
as well as total capacity; `nbsgivol` has its own synthetic cross-tool
geometry, which is not automatically the CHD geometry.

For a native label written to the raw file, use the source-built disklabel
tool's `-M sgimips`, `-B be` and file-image mode, with the generated label
prototype. That writes the target label representation; it does not replace
the separate SGI-header construction. Validate sector placement and both
checksums against the chosen source revision before enabling this path.

Once a complete 8 GiB raw disk exists, retain the lab's known CHD parameters:

```sh
chdman createhd -i "$RAW" -o "$CHD" \
  -chs 16384,16,64 -ss 512 -hs 16384 -c zlib -np 2
chdman verify -i "$CHD"
chdman extracthd -i "$CHD" -o "$ROUNDTRIP"
cmp "$RAW" "$ROUNDTRIP"
```

Require a stopped/unmounted raw input and new output paths. Record raw and
CHD hashes, size, format version, geometry and codec. Do not supply an
output parent: the delivered CHD must be independently usable. Keep test
writes in disposable overlays and compare the base hash afterward.
[chdman manual](https://docs.mamedev.org/tools/chdman.html).

For the current Indy disk-at-SCSI-ID-1 profile, the lab's boot settings are:

```text
setenv systempartition scsi(0)disk(1)rdisk(0)partition(8)
setenv osloadpartition scsi(0)disk(1)rdisk(0)partition(0)
setenv osloader boot
setenv osloadfilename netbsd.boot
setenv osloadoptions auto
boot
```

These are profile-specific instructions. Generate them alongside the CHD,
and qualify the new release with fresh emulator state. The same CHD format
does not guarantee that an arbitrary emulator implements the required Indy
hardware; publish the tested emulator/version and configuration.
[Existing disk-boot evidence](https://github.com/salvogendut/xiri/blob/a3b283df395dd76b81154198d1d651d5d63ef96b/docs/XIRI-IMAGE.md).

## Release acceptance

| Gate | Required evidence |
| --- | --- |
| Clean inputs | A new checkout with no lab seeds fetches every required source from the lock; cached and offline builds use identical verified inputs. |
| Upstream incorporation | A known upstream change is present in the candidate source/build report. Conflict and failed-test paths leave the qualified release unchanged. |
| ABI correctness | o32 base/X11/helpers, N64 kernel/modules, correct endianness and boot representations. Module imports and versioned install path agree. |
| Set completeness | All installed files belong to declared components. No missing IRIX module, accidental host libraries or stale kernel sets. |
| Bootable CD | Fresh PROM boots the final SGI-wrapped disc to the installer; its data is readable, including with the installed system's ordinary-user permissions. |
| Installation | Install from the CD to a blank disk without network access; choose the Xiri kernel/module/runtime; detach the CD and boot from disk. |
| CHD | Integrity verification, byte-for-byte extraction match, standalone disk boot and persistent changes through a writable overlay. |
| Native system | Storage, swap, networking, reboot/halt, module loading, native o32 programs and kernel-reading utilities. Reuse native wait/FPU/CD9660 regressions. |
| Display | Native xdm and ctwm, Newport rendering/text/input, serial recovery and repeated login/logout. |
| Imported desktop | When the importer is used: dependency inventory, o32/n32 controls, two independent users, winterm, FAM, catalog, preferences/session persistence and clean logout. |
| Fresh-machine state | First-boot account setup, newly generated host identity, no lab passwords, source user data or old overlays in the artifact. |
| Physical support | Named real-machine tests before advertising support beyond the emulated reference profile. |

The importer gate is conditional on a populated local build; the public
image must still boot and offer a native desktop without IRIX materials.
Do not count a skipped test as a pass. Record build, emulator-qualified and
hardware-qualified states independently.

Publish versioned ISO and CHD files, `SHA256SUMS`, a source lock, build
manifest, component inventory, release notes and boot instructions. Archive
the corresponding sources and notices, and sign the release checksum list
as a release-management step. A normal build should not need signing
secrets or publish anything externally.

Release images will be stored on external hosting. The website on
`kimcarsons` will provide download links for ISO/CHD images and their
checksums; it will not store the release images itself.

## Implementation milestones

1. **Freeze the first profile and curate sources.** Review which changes on
   `xiri` belong in the release; retain the known native fixes and required
   core interfaces, and resolve the unqualified pageout candidate explicitly.
   Record one coherent src revision, xsrc combination and runtime revision
   through submodule pointers, with the remaining inputs in the source lock.
2. **Build from a clean workspace.** Implement fetch/lock/preflight and
   isolated o32/N64 builds. Produce native release sets, matching kernel and
   modules, and complete logs without a preinstalled guest.
3. **Make runtime and X11 reproducible.** Cross-build the native helpers/FAM,
   integrate Newport patches and generate a complete install manifest.
   Pass native desktop and module checks on a newly assembled disk.
4. **Implement both media paths.** Wire sysinst selection and component
   installation; build the SGI CD and fresh raw disk/CHD. Pass blank-disk
   installation and independent disk boots with the same payload manifest.
5. **Add the custom IRIX installation importer.** This is the user's
   explicitly requested follow-up. Consolidate the existing inventories,
   implement `--irix-root`, report dependencies/provenance, and qualify the
   populated local desktop separately from the public image.
6. **Exercise upstream updates and release recovery.** Build a candidate
   against newer upstream src/xsrc, handle failures without replacing the
   qualified release, repeat acceptance and test configuration-preserving
   upgrades with a retained recovery kernel/module pair.
7. **Qualify and release.** Repeat from a clean host, compare reproducibility,
   test the intended physical Indy and publish only the supported profile.

The major engineering work is source-to-release integration and fresh
image construction. Existing kernel and desktop functionality substantially
reduces that work, but wrapping the current CHD packager alone cannot meet
the clean-build, upstream-update and bootable-CD requirements.
