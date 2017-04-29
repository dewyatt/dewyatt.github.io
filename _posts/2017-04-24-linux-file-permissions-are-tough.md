---
layout: post
title: Linux File Permissions are Tough
date: 2017-04-24 13:10:56 -0400
categories: articles
---

Introduction
============

File permissions on a modern Linux system can be confusing.
There are a number of layers that may be involved.

Much of the complexity is hidden by package management systems, but it's important to know what is going on behind the scenes.

We're going to walk through a scenario in which we want to simply ping a host (as a normal user).
We'll encounter a number of issues along the way due to the system being misconfigured/sabotaged for demonstration purposes.

To make things fun, we'll avoid solutions that would utilize the package management system.

Our test system is running CentOS 7 (1611). Our regular user is 'daniel'. Some actions are performed directly as root.

Ping!
=====

Ok, let's give this a shot.

```
[daniel@cent7 ~]$ ping 8.8.8.8
-bash: /usr/bin/ping: Permission denied
```

It's important to realize that this error is from our shell (bash), which is being denied the rights to execute `/usr/bin/ping`.
The error does _not_ come from ping itself, which was never executed.

A number of things can cause this error, but let's start with the basic file permissions.

DAC/UGO
=======

When it comes to basic file permissions, you want to remember the acronym UGO (user, group, other).

```
[daniel@cent7 ~]$ ll /usr/bin/ping
----------+ 1 root root 62088 Nov  7 05:37 /usr/bin/ping
```

Well the ownership of root:root is OK, but these permissions are all wrong. Let's fix that:

```
[root@cent7 ~]# chmod 755 /usr/bin/ping
chmod: changing permissions of ‘/usr/bin/ping’: Operation not permitted
```

Well that's unusual. Even as root, we're unable to change the permissions of the file.

Perhaps the filesystem is mounted read-only?

```
[daniel@cent7 ~]$ findmnt $(stat -c %m /usr/bin/ping)
TARGET SOURCE                    FSTYPE OPTIONS
/      /dev/mapper/cl_cent7-root xfs    rw,relatime,seclabel,attr2,inode64,noquota
```

No, the filesystem is mounted read-write.

So why are we not able to modify the permissions of `/usr/bin/ping` as superuser?

Sources
----

* `info coreutils 'File permissions'`
* `info coreutils 'ls invocation'`

Attributes
==========

Many modern Linux filesystems support certain file attributes. Let's check those!

```
[root@cent7 ~]# lsattr /usr/bin/ping
----i----------- /usr/bin/ping
```

Aha! The immutable attribute is set, so we can't modify the file data or attributes!

Ok let's unset the immutable attribute:

```
[root@cent7 ~]# chattr -i /usr/bin/ping
```

Now let's try to modify the basic permissions as we did before:

```
[root@cent7 ~]# chmod 755 /usr/bin/ping
[root@cent7 ~]# ll /usr/bin/ping
-rwxr-xr-x+ 1 root root 62088 Nov  7 05:37 /usr/bin/ping
```

Great, let's try to ping again!

```
[daniel@cent7 ~]$ ping 8.8.8.8
-bash: /usr/bin/ping: Permission denied
```

Darn, the same error!

Sources
----------------

* `man 1 chattr` (package e2fsprogs)
* `man 5 xfs` (package xfsprogs)

ACLs
====

Access Control Lists are another feature of modern filesystems. Let's look at those:

```
[daniel@cent7 ~]$ getfacl -p /usr/bin/ping
# file: /usr/bin/ping
# owner: root
# group: root
user::rwx
user:daniel:---
group::---
mask::r-x
other::r-x
```

There's an ACL that specifically prohibits all access to the user daniel, which I happen to be logged in as.

We don't really need any ACLs set on ping, so let's just remove them.

```
[root@cent7 ~]# setfacl -b /usr/bin/ping
```

Let's try again:

```
[daniel@cent7 ~]$ ping 8.8.8.8
ping: socket: Operation not permitted
```

Progress! This time we can see that ping is being executed, but it is encountering an issue when calling socket().

Sources
----------------

* `man 5 acl` (package acl)
* `man 1 setfacl` (package acl)

Capabilities
============

For quite a while, Linux has also had something called capabilities.
These are useful for fine-tuning access requirements for a process.

One special thing that ping requires is the ability to create certain types of sockets (DGRAM, RAW), depending on a few factors.

Normally, these require superuser privileges. So we _could_ set the SUID permission bit and be done with it (which is how it was typically done in the past).

However, using capabilities allows for finer-grained control. So let's try that:

```
[root@cent7 ~]# setcap cap_net_admin,cap_net_raw+p /usr/bin/ping
[root@cent7 ~]# getcap /usr/bin/ping
/usr/bin/ping = cap_net_admin,cap_net_raw+p
```

And try again:

```
[daniel@cent7 ~]$ ping 8.8.8.8
ping: socket: Permission denied
```

Hmmm, a very similar error. We get "Permission denied" (EACCES), instead of "Operation not permitted" (EPERM).

Sources
----------------

* `man 7 capabilities` (package man-pages)
* `man 3 cap_from_text` (package libcap-devel)

SELinux
=======

This one is tricky because, on my system, there are no errors logged in the usual places (journalctl, audit.log, etc).
Let's confirm whether SELinux could be a potential culprit:

```
[root@cent7 ~]# sestatus
SELinux status:                 enabled
SELinuxfs mount:                /sys/fs/selinux
SELinux root directory:         /etc/selinux
Loaded policy name:             targeted
Current mode:                   enforcing
Mode from config file:          enforcing
Policy MLS status:              enabled
Policy deny_unknown status:     allowed
Max kernel policy version:      28
```

Sure enough, SELinux is enabled and enforcing, with the default targeted policy.
Maybe the file label is to blame?

```
[root@cent7 ~]# restorecon -v /usr/bin/ping
[daniel@cent7 ~]$ ll -Z /usr/bin/ping
-rwx---r-x. root root system_u:object_r:ping_exec_t:s0 /usr/bin/ping
[daniel@cent7 ~]$ ping 8.8.8.8
ping: socket: Permission denied
```

No such luck, restorecon didn't show any output, which indicates the label was already in compliance with the stored policy (and ping_exec_t certainly looks right).

What about a SELinux boolean?

```
[daniel@cent7 ~]$ getsebool -a | egrep 'ping|icmp'
selinuxuser_ping --> off
```

How devious! Our user is not unconfined (`id -Z`), and we have set `selinuxuser_ping` to off, so certain calls to `socket()` are being denied.

The fix is simple:

```
[root@cent7 ~]# setsebool -P selinuxuser_ping on
```

And now...

```
[daniel@cent7 ~]$ ping 8.8.8.8
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
64 bytes from 8.8.8.8: icmp_seq=1 ttl=39 time=65.9 ms
^C
--- 8.8.8.8 ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 65.986/65.986/65.986/0.000 ms
```

It works!

Sources
----------------

1. `sepolicy manpage -a -p /usr/share/man/man8` (package policycoreutils-python)
2. `mandb`
3. `man 8 ping_selinux`
4. `man -k _selinux`

Conclusion
==========

Finally, we're able to ping a host as a normal user. What an accomplishment!

In the process, we have touched on a few different layers that can affect authorization.
In order of complexity (SELinux being the most complex by far):

* Basic file permissions - These are the classic user/group/other read/write/execute permissions.
We also mentioned the SUID (setuid) bit that is (at least in part) being replaced by more specific
capabilities.
* Attributes - Attributes are not often used in my experience. Which attributes can be used is
filesystem-specific.
* ACLs - Access Control Lists allow much finer control of permissions than the classic UGO/RWX.
They are supported on all modern Linux filesystems, and are relatively common in my experience.
* SELinux - SELinux is much more common than it used to be. Plenty of system administrators
are guilty of disabling it, but it should be left enabled and enforcing on all modern
RHEL-based distributions.

All of these technologies have a good reason to exist and they all work in concert.

A competent system administrator should strive to understand the basics of all of them.

