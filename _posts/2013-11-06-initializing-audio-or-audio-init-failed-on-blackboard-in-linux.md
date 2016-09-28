---
layout: post
title: "\"Initializing audio\" or \"Audio init failed\" on Blackboard in Linux"
date: 2013-11-06 12:20:21 -0400
---

Introduction
============

{% img 17.png|17t.png %}

Have you been unfortunate enough to come upon a screen like this on Blackboard?

This is part of Blackboard Collaborate Voice (formerly Wimba Voice).

In this article I will walk through the steps I took to discover the issue and solve it.


The Issue
=========

You're browsing a Blackboard course and you encounter this:

{% img 15.png|15t.png %}

And it just sits there.

It's a Java applet (you were probably prompted to run it) and it's doing a whole lot of nothing.

Let's examine the setup wizard page as an example: <http://demo2.wimba.com/demo/wizard/playback.jsp>

The Javascript
==============

It uses a bit of Javascript ([play.js](http://demo2.wimba.com/demo/ve/play.js)) to generate an appropriate applet/object. It's either not very up-to-date or just attempts to support very old software. A few choice lines:

```javascript
if (w_is_Windows95()) return "Windows 95";
...
// These result in a bug in Netscape 4.
// Why take the chance of bugs with other browsers?
...
//////////// Linux, Solaris, etc. (probably Netscape) ////////////
```

Windows 95 and Netscape? Not in my house.

The HTML
========

On Linux the Javascript will generate markup like this:

```html
<applet codebase="http://demo2.wimba.com:80" code="Player.class" id="player" name="player" archive="http://demo2.wimba.com:80/demo/code/hwclients.jar" height="48" align="bottom" width="240">
<param name="filename" value="http://demo2.wimba.com/demo/wizard/audio.wav">
<param name="loglevel" value="debug">
<param name="alt" value="[ Java Applet should load here ]">
<param name="autostart" value="true">
<param name="name" value="player">
<param name="id" value="player">
<param name="archive" value="http://demo2.wimba.com:80/demo/code/hwclients.jar">
<param name="code" value="Player.class">
<param name="diagnostic" value="false">
<param name="server_url" value="http://demo2.wimba.com:80/demo/com">
<param name="gui" value="http://demo2.wimba.com:80/demo/gui/player/player.zip">
<param name="ErrorMessage" value="Message does not exist.\(You need to be online\to play this message)">
<param name="align" value="baseline">
<param name="codebase" value="http://demo2.wimba.com:80">
<param name="context_path" value="/demo">
<param name="font" value="Arial Unicode MS, Dialog">
<div class="error">Java is not installed, or the version of Java is too old.
Please, run the <a href="javascript:startwizard()">Setup Wizard</a> and  select to install Java when prompted.</div>
</applet>
```

Now, in this case we can see one of the parameters is a .wav file. So we could just copy that link and access it directly.
However, let's assume this isn't always the case (it isn't).

Debugging It
============

One thing we can do is examine output in the Java Console. You can bring up the Java Control Panel to enable the Java Console:

`$ $JAVA_HOME/jre/bin/ControlPanel`

or, perhaps

`$ /usr/lib/jvm/java-7-oracle/bin/ControlPanel`

In the Advanced tab, enable logging and select "Show console". Save those settings and restart your browser and the Java Console will present itself to you when a Java applet is run.

The output I received initially included the following line:

`[info] AUDIOPROXY_ERR /home/daniel/.horizonwimba/JSecureDoor/audioproxy_1.0.4/data/audioproxy: error while loading shared libraries: libjack-0.100.0.so.0: cannot open shared object file: No such file or directory`

So, apparently the applet downloads and executes (ugh) this audioproxy program which tries to load a version of libjack that I don't have. So, next I installed the (32-bit) jack library and created a symlink:

`# ln -s /usr/lib32/libjack.so.0 /usr/lib32/libjack-0.100.0.so.0`

This allowed things to proceed a little farther:


![](/assets/images/16.png)

The next console output had this error:

`[info] AUDIOPROXY_ERR PortAudio error at Unable to open streams: Illegal error number`

If you search for "Unable to open streams: Illegal error number", you'll learn that the issue is related to OSS.
You can also simply examine the audioproxy executable a bit.
The program is old ('03) and is statically linked with a fairly old (~'08) version of PortAudio.
OSS was the Linux sound system before ALSA came in at Linux 2.5.
The solution is to load/install some sort of compatibility layer that supports OSS.
For me, this was simple:

`# modprobe snd_pcm_oss`

The kernel module snd\_pcm\_oss is part of the compatibility layer that allows OSS to work through ALSA.
You may also try osspd which is a userland solution.

Final Solution
==============

Ubuntu 13.10 64-bit (Saucy Salamander)
--------------------------------------

On a fresh install, this is all that is needed:

1.  `sudo apt-get install libc6:i386 libasound2:i386 libjack-jackd2-0:i386 osspd icedtea-plugin`
2.  `sudo ln -s /usr/lib/i386-linux-gnu/libjack.so.0 /usr/lib/i386-linux-gnu/libjack-0.100.0.so.0`

Generic
-------

1.  Install the required 32-bit libraries: libc6 libasound2 libjack
2.  Create a symlink to the 32-bit jack library:
    Example: `ln -s /usr/lib32/libjack.so.0 /usr/lib32/libjack-0.100.0.so.0`
3.  Load OSS compatibility:
    This varies by distribution.
    If you're lucky, it will be as simple as: `modprobe snd_pcm_oss`

Ta da!
