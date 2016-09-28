---
layout: post
title: Speco PC Pro (Under the Hood)
date: 2013-07-18 07:25:55 -0400
---

Introduction
============

I recently acquired a Speco PC Pro (8 channel) DVR.
It's a CCTV DVR that a business might use to record the feed from their security cameras.
What interested me in this DVR was that it is like a standard PC but with some interesting hardware added on (the front panel, the alarm inputs, the output relays, CCTV stuff, etc).
Here are the major hardware specs:

-   AIMB-562 motherboard
-   Intel E2160 (1.8GHz dual-core)
-   1024MiB RAM
-   Nvidia GeForce 9400 GT (128MiB)
-   2GB PQI IDE DiskOnModule flash drive w/write protect switch (Windows XP Embedded)

The front panel of the device is one of the pieces I found interesting.
It connects via USB, requires a proprietary firmware blob to function, and uses an undocumented protocol.
I reverse engineered most of this protocol and wrote code to support the LCD, LEDs, and buttons in Linux.
This article will focus on exploring the front panel and examining the protocol used by the stock firmware.
The next article will involve writing the open-source replacement firmware.

First Impressions
=================

I didn't know what software, if any, would be on this device when I purchased it.
When I fired it up, it booted into the PC Pro software:

{% img 7.jpg|7t.jpg %}

I scoured the internet and located a PDF manual: [PCPro\_PCLMan.pdf](/assets/PCPro_PCLMan.pdf)
This document confirms that it runs Windows XP Embedded.
It seemed pretty restricted at first glance.
It has a (mostly) read-only drive with a ramdisk driver. No taskbar. No alt+tab, ctrl+esc, ctrl+alt+del, etc.

Escaping the Shell
==================

There are numerous ways to bypass the restrictions of this shell. A couple simple methods:

-   There is a menu under Setup->System->System Configuration that lets you install/configure Printers. It's the standard Windows XP control panel option. With View->Explorer Bar->Folders, it becomes the standard folder view of explorer.exe.
-   Ctrl+alt+del seemed to actually function in the early boot stages. It didn't launch the standard taskmgr.exe but it had an option to do so.

I killed DVR.exe and found myself staring at...nothing.
I tried starting explorer.exe but it only opened the folder view, it didn't launch the full shell.
I found the shell was set to some PC Pro executable, SN.exe, in the registry (`HKLM\Software\Microsoft\Windows NT\CurrentVersion\Winlogon\Shell`).
I modified the shell back to explorer.exe and launched it with taskmgr.
This did what I wanted but the machine would always reboot about a minute after killing DVR.exe.
I traced this to a watchdog started in ArgusV.dll via DVR.exe (Argus 5, apparently the name of the PCIe card that handles video/sensors/relays).
A simple solution was to kill DVR.exe very early during launch, before it called ArgusV.dll:A5\_StartWatchDog.

DVR.exe also had an annoying habit of hiding the taskbar so I found myself using WinSpy++ to unhide Shell\_TrayWnd occasionally.
Poking around in the registry, I found `HKLM\Software\DSS\DVR\System\DesktopLock` which seemed interesting.
However, I found that any modifications here were reset whenever DVR.exe was relaunched.
The reason is that the system drive is a read-only ramdisk so DVR.exe was saving it's settings elsewhere and then importing them into the registry at launch.
I found the settings were stored in the Storage Path location `D:\DVRInfo\Registry.ini`.
This is just a renamed .reg file.
Setting `"DesktopLock"=dword:00000000` in this INI file lessened some of the restrictions.

Booting Linux
=============

Regardless, at this point I decided I wanted to try booting Linux.
It PXE booted with no hassle.
lsusb showed this interesting device:
`Bus 001 Device 002: ID 04b4:0084 Cypress Semiconductor Corp. `
Searching the internet yielded no information on this specific VID:PID.
I physically disassembled the DVR and found the front panel has a PCB with a [CY7C68013A-128AXC](http://www.cypress.com/?mpn=CY7C68013A-128AXC) EZ-USB FX2LP. This is what controls the 8x2 LCD, LEDs, buttons, and infrared sensor.
This is an interesting device that provides a USB interface and an 8051 MCU.
The datasheet (Technical Reference Manual) is available [here](http://www.cypress.com/?rID=38232).
After reading up on it a few minutes, I found that it requires firmware which can either be loaded from an EEPROM or uploaded directly into RAM.
There was no EEPROM on the PCB and the fact that this device showed up as "Cypress ..." told me it was probably not programmed.
Once the firmware is uploaded, a new device will show up.
I wanted to know how to communicate with the stock firmware, so I decided to load up VirtualBox and capture the USB traffic while DVR.exe was launching .
The advantage to doing it this way is that there is no hardware watchdog to get in the way.
(There are a number of other ways to go about this!)

Running in VirtualBox
=====================

I used dd to make a copy of the DiskOnModule drive and created a VDI disk from it:

```
# dd if=/dev/sdb of=sdb.dd
# VBoxManage convertdd sdb.dd sdb.vdi --format VDI
```

I then created a VM (Windows XP 32-bit, 1024MiB RAM) and launched it.
I connected the front panel USB cables to my development machine's motherboard.
Once XP Embedded booted up, I was greeted with some error about a serial.
This was the shell, SN.exe, likely checking the serial against some hardware signature and complaining.
I decided to simply set the shell back to explorer.exe.
I used `chntpw -e` on `\Windows\System32\config\SOFTWARE` (in the VDI) to edit the key `HKLM\Software\Microsoft\Windows NT\CurrentVersion\Winlogon\Shell` and relaunched the VM.
This results in a much more standard Windows XP experience.
Now, I looked at the available USB devices in VirtualBox and found the familiar "Unknown device 04b4:0084".
Once connected, something interesting happened.
I found the device disappeared and a new device appeared: `AverMedia SA7001`.
What's happening is the firmware is immediately being uploaded to the FX2LP which then "ReNumerates".

I loaded usbmon in my Linux host (`modprobe usbmon`) and launched Wireshark to capture the USB traffic.
I launched DVR.exe in the VM and captured a good bit of traffic.
To be clear, it is not actually DVR.exe that is generating all this traffic, it's FPanel.exe. The PC Pro software is a collection of separate programs that work together via FindWindow/PostMessage.
So, I found that FPanel.exe, upon launching, performs an endless number of USB control IN transfers.
I guessed that it was probably polling the state of the device (which was a little disappointing as it seems a waste of resources).
I captured the traffic as I pressed a button here and there and found that this control transfer was indeed affected by button presses.
The first byte indicates an event:

| byte0         | meaning                                |
|---------------|----------------------------------------|
| 0xff          | nothing new                            |
| 0             | button released                        |
| anything else | identifier of button currently pressed |

The last byte is a group of flags indicating the state of the FN key and a few other bits I don't have time to investigate.

I searched through the capture for messages I saw on the 8x2 LCD screen as well.
A quick examination revealed there was a BULK endpoint which took a format like so:

`<line> <char0> ... <char7>`

Where line was 0 for the first line of the LCD, 1 for the second. For example:

`0x00, Hello!!!`

For the LEDs I had to step through DVR.exe until I saw one of the LEDs change state and then review the USB traffic.
I won't go into details here as the [source code]({% post_url 2013-08-25-fpanelcpp %}) later on speaks for itself.
Now I knew something of the protocol used to communicate.
However, I wanted to be able to do this in Linux.
That required loading the firmware blob in Linux.

Extracting the firmware
=======================

Now, I could just try to extract the firmware from the usb traffic. However, there is an easier way.
I downloaded the FX2LP Development Kit ISO from [here](http://www.cypress.com/?rID=14321).
Reading the EZ-USB Development Kit User Guide revealed that the driver loading the firmware is CyLoad.sys (this can be verified in Device Manager). The INF file `/WINDOWS/INF/CyLoad.inf` indicated it loads `/WINDOWS/system32/CyLoad/CyLoad.spt`. The spt is a script file that contains .ihx ([Intel Hex](http://en.wikipedia.org/wiki/Intel_HEX)) that is run on the 8051.
I found a tool to extract the .ihx files from the .spt script: [cyusb-fw-extract](https://ftp.dlitz.net/pub/dlitz/cyusb-fw-extract/current/cyusb-fw-extract.py)
I extracted the files with:
`python2 cyusb-fw-extract.py -v -oavermedia ~/CyLoad.spt`
With 76 warnings, it did manage to extract avermedia\_1.ihx and avermedia\_2.ihx (I renamed these to .hex).

Control Center is the program that generates the spt script files.
The source is available with the DVK at `C:\Cypress\Cypress Suite USB 3.4.7\CyUSB.NET\examples\Control Center\Form1.cs` so I decided if the .ihx files generated did not work, I would start my investigation there.

So, I wondered, how can I load this firmware in Linux?

Loading the firmware in Linux
=============================

I found there are a few tools that are supposed to be able to load this firmware in Linux.
However, only one wanted to work for me: [cycfx2prog](http://www.triplespark.net/elec/periph/USB-FX2/software/)

After resetting the device (unplugging the USB cables so it shows up as 04b4:0084 again), I used the following sequence of commands:

```
# ./cycfx2prog -id=04b4.0084 prg:avermedia_1.hex
# ./cycfx2prog -id=04b4.0084 run
# ./cycfx2prog -id=04b4.0084 prg:avermedia_2.hex
# ./cycfx2prog -id=04b4.0084 run
```

Note: avermedia\_1.hex is not actually necessary, it seems to be some kind of a stub.

After this, the new device shows up on the USB bus:
`Bus 001 Device 004: ID 07ca:a002 AVerMedia Technologies, Inc. `

Communicating with the firmware
===============================

Now that I had the firmware loaded in Linux, I wanted to communicate with it!
The example, using libusbx, is [here.]({% post_url 2013-08-25-fpanelcpp %})
It supports the buttons, LCD, and LEDs.
I don't have the remote control for the DVR so I can't test the IR functionality.
It may be that the IR input is in the 11-byte USB control IN transfer, I don't know.

Open-source firmware!
=====================

So far, this is what's possible:

-   Load the proprietary firmware in Linux
-   Read button state
-   Write to the LCD
-   Control the LEDs

However, this all requires custom software on the PC and raw USB I/O. Plus, it requires that proprietary firmware blob which isn't really ideal.

In the next article I will go over how I wrote open-source firmware to solve some of these issues.
