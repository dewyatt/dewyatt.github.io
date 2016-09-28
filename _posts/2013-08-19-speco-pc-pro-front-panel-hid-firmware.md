---
layout: post
title: Speco PC Pro Front Panel HID Firmware
date: 2013-08-19 13:16:38 -0400
---

Introduction
============

This article goes over the firmware I wrote for the front panel of my Speco PC Pro DVR which has a [CY7C68013A-128AXC EZ-USB FX2LP](http://www.cypress.com/?mpn=CY7C68013A-128AXC).
It emulates a keyboard.
The repository is on github: <https://github.com/dewyatt/fpanelkb>
This firmware is HID-compliant so it "just works", for the most part, no need to write a PC driver.

fx2lib
======

The EZ-USB FX2LP Development Kit software is for Windows and comes with the Keil compiler and a supporting library for FX2LP development.
The Keil compiler is great but it is commercial software and limited to a certain output size unless you purchase a license.

For Linux, we have the [Small Device C Compiler](http://sdcc.sourceforge.net/) compiler.
However, we cannot use the EZ-USB development library that comes with the DVK.
This is where [fx2lib](https://github.com/mulicheng/fx2lib) comes in.

Ports
=====

I discovered most of the port connections by using a multimeter. For some of them, I used a simple continuity test. For others, I uploaded firmware that would toggle ports on and off and tested the voltage on wires here and there. Lastly, for a few I had to resort to disassembling the stock firmware for a hint.
The results:

| port(s) | function                                                                                   |
|---------|--------------------------------------------------------------------------------------------|
| PA0     | Infrared receiver                                                                          |
| PA1-PA4 | Not sure, reported as flags in keys report of stock firmware (last byte), alongside FN key |
| PA5     | LCD, E                                                                                     |
| PA6     | LCD, RS                                                                                    |
| PA7     | LCD, RW                                                                                    |
| PB0-PB1 | Dial                                                                                       |
| PB2-PB5 | Shuttle wheel                                                                              |
| PB6-PB7 | No clue, though they are read by the stock firmware                                        |
| PC0-PC7 | LCD, DATA                                                                                  |
| PD0-PD4 | Button matrix                                                                              |
| PD5     | Recording LED                                                                              |
| PD6     | Network LED                                                                                |
| PD7     | FN button LED                                                                              |
| PE0-PE7 | Button matrix                                                                              |

Human Interface Device
======================

[USB Human Interface Devices (HID)](http://en.wikipedia.org/wiki/USB_human_interface_device_class) are a class of USB devices well-suited for things like keyboards and mice.
What's nice about an HID device is that it generally does not require writing a driver on the PC side.

HID devices use descriptors to describe reports.
They're a bit confusing at first.
The descriptor fpanelkb uses is located at [src/dscr.a51](https://github.com/dewyatt/fpanelkb/blob/5e3d610/src/dscr.a51).
Here is an excerpt:

```
                                      ;;;lcd (first byte = line(0/1), 8 bytes are character data)
  .db 0x06, 0x00, 0xff              ;   USAGE_PAGE (Vendor Defined Page 1)
  .db 0x09, 0x01                    ;   USAGE (Vendor Usage 1)
  .db 0x85, 0x03                    ;   REPORT_ID (3)
  .db 0x75, 0x08                    ;   REPORT_SIZE (8)
  .db 0x95, 0x09                    ;   REPORT_COUNT (9)
  .db 0x92, 0x00, 0x01              ;   OUTPUT (Data,Ary,Abs,Buf)
```

This particular report is for writing to the LCD. It has a report ID so we can differentiate between the other 3 reports. It consists of 9 bytes (REPORT\_SIZE \* REPORT\_COUNT = 72 bits).

Buttons
=======

There are 39 pushbuttons. They are arranged in a matrix and 7 buttons can be pressed at a time.
The code is a bit confusing if you're not accustomed to dealing with button matrices.
Resources on button matrices:

-   [How a Key Matrix Work](http://pcbheaven.com/wikipages/How_Key_Matrices_Works/)
-   [Input Matrix Scanning](http://www.openmusiclabs.com/learning/digital/input-matrix-scanning/)

```c
WORD make_keycode ( WORD e, WORD r ) {
  switch ( e ) {
    case 0x7C:
      return r * 6 + 1;
    case 0xBC:
      return r * 6 + 2;
    case 0xDC:
      return r * 6 + 3;
    case 0xEC:
      return r * 6 + 4;
    case 0xF4:
      return r * 6 + 5;
    case 0xF8:
      return r * 6 + 6;
  }
  return 0;
}

//Fills buttons[7] array with any pressed keys
void scan_buttons () {
  int i;
  for ( i = 0; i < 5; i++ ) {
    //overly complex version:
    //IOD = ( IOD & 0xE0 ) | (0x1F & (~(1 << i)));
    IOD |= 0x1F; //Turn on all bits except top 3 (LED outputs)
    IOD &= ~(1 << i); //Turn off column i
    IOE = 0xFF;
    buttons[i] = make_keycode ( IOE & 0xFC, i );
  }
  IOD |= 0x1F;
  IOE = 0xFE;
  buttons[5] = make_keycode ( IOE & 0xFC, 5 );
  IOD |= 0x1F;
  IOE = 0xFD;
  buttons[6] = make_keycode ( IOE & 0xFC, 6 );
  IOE = 0xFF;
}
```

`scan_buttons` is called every 5 milliseconds using a timer. This takes care of [debouncing](http://www.labbookpages.co.uk/electronics/debounce.html). It fills the `buttons[7]` array with any pressed buttons (0 if nothing pressed).

When a button is pressed on the front panel, it is mapped to a keyboard key using `button_keymap[]` which uses constants defined in [include/hidkeys.h](https://github.com/dewyatt/fpanelkb/blob/5e3d610/include/hidkeys.h).

Wheels
======

There are two "wheels". One is the shuttle wheel, the spring-loaded wheel that returns to a neutral position when you release it. This is typically used for fast-forwarding and rewinding at different speeds. It is mapped to keyboard keys via `shuttle_keymap[]`.

The other wheel is more of a dial. It has an indentation to rest your finger and spin it. It is typically used for frame-by-frame seeking. It is mapped to keyboard keys via `dial_keymap[]`.

Infrared
========

The infrared receiver is connected to PA0.
When infrared light is present, PA0 is driven LOW, otherwise it remains HIGH.
The code is somewhat interesting. This is how it's used in [src/device.c](https://github.com/dewyatt/fpanelkb/blob/5e3d610/src/device.c) :

```c
 //init
  ir_init();
  ir_start();
...
    } else if ( !button_pressed && got_ir ) {
      //infrared
      if ( decode_ir ( &mode, &toggle, &address, &command ) ) {
        button = remote_key_map ( command );
        if ( button ) {
          send_key_report ( button );
          while ( EP1INCS & bmEPBUSY ) {}
          send_key_report ( 0 );
        }
      }
      ir_start ();
```

`ir_init()` sets up a timer and external interrupt but does not enable them. `ir_start()` enables external interrupt 0 (falling edge) which is conveniently on the IR port (PA0). When the interrupt triggers, we end up in [ir.c](https://github.com/dewyatt/fpanelkb/blob/5e3d610/src/ir.c) `ir_ie0_isr()`.
This function enables a timer for RC6\_UNIT/4 microseconds. See [this](http://www.sbprojects.com/knowledge/ir/rc6.php) page for info on RC-6 Mode 0. This lets us jump part way into the IR stream. When the timer triggers, we'll land in [ir.c](https://github.com/dewyatt/fpanelkb/blob/5e3d610/src/ir.c) `ir_timer_isr()`.
This function records 58 samples at 444 microsecond intervals. It's important that this function simply record the data and not interpret it as we're dealing with some tight timing on a 48MHz CPU.
Once all 58 samples have been recorded, `got_ir` is set to TRUE. At this point, `decode_ir` can be called to see if it is a valid RC-6 Mode 0 data stream.

The remote commands are then mapped to keyboard keys with `remote_key_map()`.

LEDs
====

There are 3 LEDs total. The recording LED, network LED, and the FN button LED (LED under the FN button).
They use up ports PD5, PD6, and PD7, respectively.

The FN LED is used as the CAPS LOCK key and is a separate HID report. The firmware handles it as follows:

```c
  if ( !(EP1OUTCS & bmEPBUSY) ) {
    //report id
    switch ( EP1OUTBUF[0] ) {
      //keyboard LEDs
      case 2:
        PD7 = 0;
        //caps lock (FN button) LED
        if ( EP1OUTBUF[1] & 2 )
          PD7 = 1;

      break;
```

The other LEDs are handled a bit farther down:

```c
      //recording & network LEDs
      case 4:
        PD5 = !(EP1OUTBUF[1] & 1);
        PD6 = !(EP1OUTBUF[1] & 2);
      break;
```

These require a little bit of software on the client side to control.
There are a couple of libraries available for raw HID I/O:

-   [libhid](http://bfoz.github.io/libhid/)
-   [hidapi](http://www.signal11.us/oss/hidapi/)

I used hidapi. Here is an excerpt from [tests/leds.c](https://github.com/dewyatt/fpanelkb/blob/5e3d610/tests/leds.c) :

```c
void leds_write ( hid_device *handle, int recording, int network ) {
  unsigned char buffer[2];
  //byte 0 is the Report ID (4)
  buffer[0] = 0x4;
  //byte 1 is the state of the LEDs
  buffer[1] = 0;
  if ( recording )
    buffer[1] |= 1;

  if ( network )
   buffer[1] |= 2;

  if ( hid_write ( handle, buffer, 2 ) == -1 )
    fprintf ( stderr, "Warning: hid_write failed\n" );
}
```

LCD
===

The LCD is [HD44780](http://en.wikipedia.org/wiki/Hitachi_HD44780_LCD_controller) compatible.
There are a ton of libraries to handle these display controllers.
I wrote my little library in [src/lcd.c](https://github.com/dewyatt/fpanelkb/blob/5e3d610/src/lcd.c).
The code that handles LCD reports in the firmware is simple:

{% highlight c %}      //LCD
      case 3:
        lcd_goto ( 0, EP1OUTBUF[1] );
        EP1OUTBUF[10] = 0;
        lcd_write_string ( &EP1OUTBUF[2] );
      break;
{% endhighlight %}

Similarly to the LEDs, the LCD requires client-side software.
Here is an excerpt from [tests/lcd.c](https://github.com/dewyatt/fpanelkb/blob/5e3d610/tests/lcd.c) :

```c
void lcd_write ( hid_device *handle, int line, const char *s ) {
  char buffer[10];
  int length = strlen ( s );
  int i;
  //byte 0 is the Report ID (3)
  buffer[0] = 0x3;
  //byte 1 is the LCD line (0 or 1)
  buffer[1] = line;

  //copy the string to &buffer[2]
  strncpy ( buffer + 2, s, 8 );

  //fill out the rest of the string with spaces if necessary
  for ( i = length; i < 8; i++ )
    buffer[i + 2] = ' ';

  //send it off
  if ( hid_write ( handle, (unsigned char *)buffer, 10 ) == -1 )
    fprintf ( stderr, "Warning: hid_write failed\n" );
}
```