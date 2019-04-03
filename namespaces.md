% Namespaces
% Iustin Pop, <iustin@k1024.org>
% March 30th, 2019

## About

- A set of slides with information gathered from various places
  - man pages, Wikipedia, blog posts, mailing list archives, etc.
- Main goal was to solidify my own understanding of the issue
  - and present a somewhat logical introduction to this complex topic
- Corrections very welcome!
  - but note this glances over a million small details
  - note: licensed as CC BY-SA 4.0

# In the beginning…

## `chroot()`

- Introduced in Unix V7 in 1979
- Added to BSD in 1982, for the 4.2 release
- Used _to test the 4.2 installation and build system_
- Changes `/` for the process
- Many early articles about it not being a security tool

## problems with `chroot()`

- Not to be used as security tool!
- Case 1: `cd` into directory that is then moved outside of chroot dir
- Case 2: `chroot()` without `cd /`, which defeats the purpose
- The only guarantee it that it changes the root, not that you cannot
  change it back
  - see <https://lkml.org/lkml/2007/9/25/434> ☺

# Other attempts

## FreeBSD jails

- First introduced in FreeBSD version 4 in March 2000
- More powerful than simple `chroot()`
- Used as security tool to confine programs
- Note: I don't have practical experience with them, so take the below
  data with a grain of salt

## FreeBSD jails - basics
- Jails expand chroot by "…by virtualizing access to the file system, the
  set of users, and the networking subsystem"
- A jail is characterized by four elements:
  - A directory subtree: the starting point from which a jail is
    entered. Once inside the jail, a process is not permitted to
    escape outside of this subtree.
  - A hostname: which will be used by the jail.
  - An IP address: which is assigned to the jail. The IP address of a
    jail is often an alias address for an existing network interface.
  - A command: the path name of an executable to run inside the
    jail. The path is relative to the root directory of the jail
    environment.

## FreeBSD jails - limitations

- As you can see, the focus is on _restricting_ the jail, not on
  actually virtualising the resources
- Root in host system is responsible for:
  - setting up mount points
  - allocating the IP
  - creating the jail
- E.g. as networking is done at IP level, not at network stack/device
    level, there are problems with base system daemons and listening
    on `INADDR_ANY`
- Resources:
  - [man
   page](https://www.freebsd.org/cgi/man.cgi?query=jail&sektion=&n=1)
  - [the handbook](https://www.freebsd.org/doc/handbook/jails.html)

## OpenVZ - first attempt at Linux containers

- First release way back in 2005
- Available in distributions as early as 2006 (Debian; via custom
  kernel)
- Main goal was to enable large-scale hosting
- Did actual containerisation based on patched kernels
  - … they re-implemented/used separated mechanisms for a lot of the
    container work (CPU isolation, disk quota, user resources)
  - … and they were never fully merged
  - but they had working checkpoint/restore, including live migration
    (!)
- Significant parts of the kernel code was contributed to upstream
  - initial namespaces, `uts`, `pid`, `net`, etc. (see later)
- Over time seems (subjective) to have decreased in importance as a
  solution in its own
  - by 2015, most of the code (incl. management) was open-sourced
- <https://openvz.org>

# Linux namespaces

## hello virtualisation

- Originated in 2002 in the 2.4.19 kernel with work on the mount
  namespace kind
- Further work in 2006
- Full container support landed in February 2013, with the 3.8 kernel
- But even today there's continued work on this
- The focus is on virtualising the respective resource, and (mostly)
  allow freedom to configure it, rather than imposing the
  configuration from the root namespace

## local resources

- Access to local resources is isolated to the process, so the
  isolation problem doesn't change this (mostly)
- Local resources:
  - file descriptors (although see `CLONE_FILES`)
  - memory (although see `CLONE_VM`)
  - signal handlers (but see `CLONE_SIGHAND`)
  - current directory (and yet there is `CLONE_FS`)
- All pretty boring, except see the flags above!

## global resources

- These are shared/visible to a tree of processes
- As of kernel 4.10, there are 7 (6+1) namespace types
- 3 boring ones, 3 interesting ones, 1 magical
  - the magical one enables real containers

## interlude: capabilities

- In Linux, root ≠ root!
- The actual permissions associated with `uid 0` are actually
  process capabilities
  - such as `CAP_CHOWN`, make arbitrary changes to file IDs
  - or `CAP_KILL`, send signals to arbitrary processes
- But splitting things nicely is hard…
- So we have `CAP_SYS_ADMIN`: _"Note: this capability is overloaded"_ ☺
- see man page `capabilities(7)`

## boring namespaces

- UTS
  - allows changing the hostname and NIS domain name
  - introduced in 2.6.19 as `CONFIG_UTS_NS`
  - requires `CAP_SYS_ADMIN`
- IPC - inter-process communication
  - isolates old-school IPC resources, e.g. System V IPC objects and
    POSIX message queues
  - "The common characteristic of these IPC mechanisms is that IPC
    objects are identified by mechanisms other than filesystem
    pathnames."
  - introduced in 2.6.19 as `CONFIG_IPC_NS`
  - requires `CAP_SYS_ADMIN`
  - does anyone use this anymore in the http-world?
    - yes: `ipcs|wc -l` → 48 entries on my machine

## Cgroup namespace

- Introduced in 4.6
- Virtualises the view of a process' control groups
  - see `cgroups(7)` - resource isolation/monitoring
  - control groups themselves are a large topic
  - and a good example of 'old deprecated' vs. 'new beta'
- One goal is to hide the actual cgroup hierarchy from processes
  running in such a namespace (security)
- It also allows isolating the control groups of processes running
  under the same UID (security)
- Another goal is to ease container migration, as not the full path
  needs to be identical across hosts (features)
- Requires `CAP_SYS_ADMIN`

## Mount namespace

- The original namespace in 2.4.19, thus named "NS",
  e.g. `CLONE_NEWNS`
- Reminiscent of the `chroot()` effect: isolates the directory
  hierarchy.
- Each mount namespace is owned by a user namespace
  - if the user NS of this mount NS differs from the user NS of the
    parent mount NS, then this mount NS is a "less privileged" NS
- Transitioning to a less privileged NS has large effects on the
  mount-points in the NS:
  - shared mounts become slave mounts
  - mounts that come as a single unit are locked together, and cannot
    be separated
  - some mount flags (`MS_RDONLY`, `MS_NOSUID`, `MS_NOEXEC`) and the
    "atime" flags become locked and cannot be changed anymore
- Note on shared, private, slave and un-bindable mounts
- Mount semantics are… complex
- Yet again, requires `CAP_SYS_ADMIN`

## Net namespace #1

- Introduced in 2.6.24 as `CONFIG_NET_NS`, but completed in 2.6.29
- A network namespace virtualises/provides an isolated view of many
  network-related things:
  - network devices! a network device lives in a single namespace
  - ipv4/ipv6 protocol stacks
  - routing tables (!)
  - firewall rules (!!)
  - port numbers, etc.
  - also isolates the UNIX domain sockets
- Requires `CAP_SYS_ADMIN`

## Net namespace #2
- The single-homing of network devices has interesting implications
- A new net namespace only has a loopback interface, i.e. it is fully
  isolated:

```
# ip -o l
1: lo: …
2: eth0: …
# unshare --net
# ip -o l
1: lo: …
#
```
- To connect it to other namespaces, one uses virtual ethernet
  device pairs (see `veth(4)`)
```
# ip link add veth2-left type veth peer veth2-right
```
- Then moves one of the interfaces to the other namespace:
```
# ip link set veth2-right netns ns-right
```
- And can configure (in both namespaces) the interfaces and the needed
  routing
- Very practical use cases (e.g. no-net software builds in Debian)

## PID namespaces

- Introduced in 2.6.24 as `CONFIG_PID_NS`
- The namespace isolates the process ID numbers
  - multiple processes in different namespaces can have PID 666!
- This is a hierarchical namespace type, meaning a process is present
  (visible) it its namespace and all parent namespaces
  - alternatively, a process can see all processes in its PID
    namespace and all descendant namespaces
  - a process has a different PID in each of the namespaces it is
    present in
  - level of nesting is, as of 3.7, 32
- This makes syscalls that operate on process IDs interesting
  - always interpreted in the caller's namespace
- Requires `CAP_SYS_ADMIN`

## PID namespaces #2 - peculiarities

- Because a process own identifier as returned by `getpid()` should
  never change, a process cannot change PID namespaces (compared to
  all other namespace types)
- Thus, a `setns()` only changes the _namespace for future
  children_ of this process, not for the process itself
- Thus these children will have a parent PID not in their own
  namespace!
  - `getppid()` returns 0 in such cases
- A further interesting aspect is that one can only navigate—via
  `setns()`—downwards, not upwards
  - not even to go back to its original namespace!

## PID namespaces #3 - everybody can be init!

- When creating first child in a new PID namespace, the PID numbering
  starts at 1
- Which means that each PID namespace has an init-like process, with
  init-like semantics:
- If this process terminates, all processes in the PID namespace
  will be killed by the kernel with `SIGKILL`
- Only signals for which a handler has been set can be sent to it,
  both from this namespace and other (ancestor) namespaces
  - with the exception of `SIGKILL`/`SIGSTOP`
- `reboot()` in this namespace works (and terminates it)
  - yay for user experience!

# Finally, the magical user namespace

## why is this special?

- Starting with kernel 3.8, creating a user namespaces is **an
  unprivileged operation!!**
```
test@debian:~$ id
uid=1001(test) gid=1001(test) groups=1001(test)
test@debian:~$ unshare --user
nobody@debian:~$ id; exit
uid=65534(nobody) gid=65534(nogroup) groups=65534(nogroup)
test@debian:~$ unshare --user --map-root-user
root@debian:~# id
uid=0(root) gid=0(root) groups=0(root)
```
- Well, at least as long as things are not disabled!
  - see <https://lwn.net/Articles/673597/>
  - on Debian,
```
echo 1 > /proc/sys/kernel/unprivileged_userns_clone
```

## so what? fake root, right?

- Yes, but having root (actually, all capabilities) means a lot in
  this specific namespace _and in the non-user namespaces owned by it_
- E.g. one can mount various virtual file-systems in this namespace:
```
test@debian:~$ unshare --user --map-root-user --mount
root@debian:~# df -h|grep /mnt
root@debian:~# mount -t tmpfs none /mnt/
root@debian:~# df -h|grep /mnt
none            998M     0  998M   0% /mnt
```
- Basically, when a non-user-namespace is created, it is owned by the
  user namespace in which the creating process was a member at the
  time of the creation of the namespace
  - all your _(other)_ namespaces are belong to me
- Having `CAP_SYS_ADMIN` in a (non-initial) user namespace is not
  quite the real thing
  - but close enough!

## how much _root_?

- you can't change some global things
  - e.g. the system time; not _yet_ virtualised, semantics complex,
    see this [LWN article](https://lwn.net/Articles/766089/), first
    proposed in 2006…
  - you can't load kernel modules, or create devices (`mknod`)
  - and you can't mount any block-based filesystems (only `procfs`,
    `sysfs`, `devpts`, `tmpfs`, `ramfs`, `mqueue`, `bpf`)
- you don't have full read permissions either
  - e.g. `dmesg` to read the kernel logs, if they were originally
    disallowed
- but the more 'normal' root parts (if coupled with other namespaces)
  are there
  - create interfaces, set firewall rules, kill random processes,
    change file ownership, reboot the namespace, listen on port 80, …

## more details

- First functionality around it appeared (`CLONE_NEWUSER` flag) in
  2.6.23, semantics changed to current ones in 3.5, and the final bits
  were added to make it fully usable in 3.8; set `CONFIG_USER_NS`
- User namespaces require support across large parts of the kernel
  subsystems
- Work continues on this
  - e.g. XFS filesystem added support for it in 3.12
  - `bpf` mounting appeared in 4.4,
  - `cgroup` configuration introduced 4.6, etc.
- This virtualises the user and group IDs, the root directory, kernel
  keys and capabilities

## processes and namespaces

- A process is member of exactly one user namespace
- Moving to a different user namespace…:
  - is possible if you have `CAP_SYS_ADMIN` in the target namespace
  - and if you are single-threaded (all threads must belong to a
    single namespace)
  - gives full set of capabilities in the target namespace, but you
    lose capabilities in the parent namespace
    - which means you can't re-join a namespace; _goodbye is forever!_
- Privileges can differ between inside the user namespace and
  "outside" it
  - this makes sense if you think in terms of other namespaces which
    are owned by this user namespace
  - I can own my UTS namespace, and thus can change the hostname, but
    don't own my network namespace, thus can't list firewall rules,
    even with `CAP_NET_ADMIN`
```
test@debian:~$ unshare --user --map-root-user
root@debian:~# iptables -L
iptables: Permission denied (you must be root).
root@debian:~# id
uid=0(root) gid=0(root) groups=0(root)
```


## user and group IDs

::: incremental

- Inside user corresponds to what?
-     test@debian:~$ unshare --user --map-root-user
      root@debian:~# date > /tmp/foo; exit
      test@debian:~$ ls -l /tmp/foo
      -rw-r--r-- 1 test test 29 Mar 30 15:29 /tmp/foo
- OK, so root user inside the NS is my user; what about other users?
-     test@debian:~$ unshare --user --map-root-user
      root@debian:~# su - more-test
      su: Authentication failure
- But can I see their files at least?
-     test@debian:~$ ls -l /tmp/foo
      -rw-r--r-- 1 more-test test 32 Mar 30 15:39 /tmp/foo
      test@debian:~$ unshare --user --map-root-user
      root@debian:~# ls -l /tmp/foo
      -rw-r--r-- 1 nobody root 32 Mar 30 15:39 /tmp/foo

:::

## user and group ID mappings

- In order to switch user/group IDs within the namespace, a mapping
  has to be created
  - i.e., what is user 1000 inside the namespace equivalent to, in the
    parent namespace?
- It is done by mapping ranges of contiguous IDs between parent and
  child
  - e.g. IDs 0-5'000 in the child namespace will be mapped to
    100'000-105'000 in the parent
  - the mapping is used when accessing resources in the parent
    namespace
  - there are funny limitations about the mapping (340 entries!)
  - mapping can only be set once
- A single mapping (with 1 ID) is allowed for non-privileged processes
  - processes with `CAP_SETUID`/`CAP_SETGID` can set arbitrary
    mappings
  - how about nested namespaces? it is fun!
- Technically, see `/proc/$pid/uid_map` (and `gid_map`), and read
  `user_namespaces(7)`

## user and group ID mappings #2

- Before a mapping is created:
  - system calls that change user/group IDs will fail
  - system calls that return user/group IDs will return the overflow
    ID (usually `65534`, `nobody/nogroup`)
- After a mapping is created:
  - changing users (inside the NS) is allowed only to mapped users
  - system calls that take/return IDs will do the mapping
    (e.g. `stat`, `getuid`, `chown`, etc.) as appropriate, both inside
    and outside of the namespace
  - unmapped IDs will still be seen as the overflow ID
  - `setuid`/`setgid` programs works as expected if there is a
    mapping!
- Even with a mapping, you'll see often unmapped IDs
  - e.g. when looking at processes outside your user namespace
  - or at file permissions

# Conclusion

## Did not talk about…

- `setns(2)`: switches one or more namespaces:
  - `ls -l /proc/self/ns/`
  - bind-mount those directories somewhere else to persist the
    namespace beyond lifetime of a single process
  - `setns(2)` takes argument a file descriptor to one such directory
- `unshare(2)`: unshares parts of the execution context
  - it means it can create new namespaces (before switching to them)
  - but also other things related to `CLONE_*` flags
- speaking of which, `clone(2)` is very much worth reading, to
  understand how complex process relationships are
- `ioctl_ns(2)` allows discovering some of the relationships between
  namespaces
- `unshare(1)`, `newuid(1)`, `newgid(1)`, etc.

## Power, but…

- Namespaces as of 4.x kernel are very powerful
- You can't trust anymore:
  - who you are (`CLONE_NEWUSER`)
  - what's your name (`CLONE_NEWUTS`)
  - where you are (`CLONE_NEWNS`)
  - who you can see (`CLONE_NEWPID`)
  - where you can go (`CLONE_NEWNET`)
- But you can run an un-trusted random binary with no worries
  - … well, except kernel bugs
  - or configuration bugs
- Fun!

## Resources

- Start reading man page `namespaces(7)`, and all the "SEE ALSO" pages
- …
- Profit!
- Note: no man pages have been harmed while writing this.

### Thanks!
