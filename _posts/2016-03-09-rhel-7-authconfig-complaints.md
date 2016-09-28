---
layout: post
title: RHEL 7 authconfig complaints
date: 2016-03-09 12:40:55 -0400
---
The authconfig suite on RHEL 7 is commonly used to configure network authentication and authorization. In my case, I wanted LDAP authorization and Kerberos authentication.

(I should actually note that this was on CentOS 7.2, rather than RHEL 7.0, but there should not be any difference.)

There are 3 frontend interfaces to the authconfig suite:

* authconfig - command-line, scriptable interface
* authconfig-tui - (deprecated) command-line menu-driven interface
* authconfig-gtk - full graphical interface (aka system-config-authentication)

These frontends all utilize the same backend python code.

Here are my complaints:

1. The manpage for authconfig is pretty sparse. In fact, it's much more useful to run `authconfig --help` than it is `man authconfig`. This is the opposite of what it should be.
2. nslcd vs sssd. If you happen to have the sssd package installed at the time you run the authconfig utilities, sssd may be used. Otherwise, nslcd will be used. It will also depend on `--enablekrb5realmdns` / `--disablekrb5realmdns`. This is completely transparent to the user, no notification whatsoever.
3. authconfig-tui is deprecated, but still recommended by some experts. Perhaps due to the fact that the deprecation is mentioned half way through the manpage in a small notes section.
4. All 3 interfaces have different feature sets. The plain authconfig interface exposes the most features. This may not be a huge issue, but I think the situation could be improved.
