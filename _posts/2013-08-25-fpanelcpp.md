---
layout: post
title: fpanel.cpp
date: 2013-08-25 13:30:56 -0400
categories: articles
visible: false
---

This example uses libusbx to communicate with the AVerMedia SA7001 firmware.

{% highlight cpp linenos %}
/**
* The MIT License (MIT)
*
* Copyright (c) 2013 Daniel Wyatt
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in
* all copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
* THE SOFTWARE.
**/
/*
  This code is for communicating with the stock firmware of a
  Speco PC Pro front panel (AVerMedia SA7001).
*/
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

extern "C" {
#include <libusb.h>
}

#define TIMEOUT_MS      10

#define ENDPOINT_FPANEL 4

#define REQUEST_LEDS        0xA0
#define REQUEST_BUTTON_STATE   0xA3

#define LED_BOTH        0
#define LED_NETWORK     1
#define LED_RECORDING   2
#define LED_OFF         3

//is the FN button active?
#define FLAGS_FN        (1 << 7)

namespace fpanel {

/* Must be called before the LCD will function */
bool init_lcd ( libusb_device_handle *device ) {
    uint8_t buffer[] = {0xff, 0x55, 0xaa, 0x55, 0xaa, 0x55, 0xaa, 0x55, 0xaa};
    int bytes;
    return 0 == libusb_bulk_transfer ( device, ENDPOINT_FPANEL, buffer, 9,
        &bytes, TIMEOUT_MS );
}

/*
    Write string to LCD.
    line: 0 or 1
    s:    maximum 8 chars
*/
bool write_lcd ( libusb_device_handle *device, int line, const char *s ) {
    char text[8];
    int length = strlen ( s );
    memcpy ( text, s, length );
    for ( int i = length; i < 8; i++ )
        text[i] = ' ';

    uint8_t buffer[9];
    buffer[0] = line;
    memcpy ( &buffer[1], &text[0], 8 );
    int bytes = 0;
    return 0 == libusb_bulk_transfer ( device, ENDPOINT_FPANEL, buffer, 9,
    &bytes, TIMEOUT_MS );
}

/* set the recording and network LED states */
bool set_leds ( libusb_device_handle *device, bool recording, bool network ) {
    int wval = 3 - ( recording ? LED_RECORDING : 0 ) - ( network ? LED_NETWORK : 0 );
    return 0 != libusb_control_transfer ( device,
        LIBUSB_REQUEST_TYPE_CLASS
        | LIBUSB_RECIPIENT_INTERFACE
        | LIBUSB_ENDPOINT_OUT,
    REQUEST_LEDS,
    wval,
    0,
    (unsigned char*)"\x00",
    1,
    TIMEOUT_MS );
}

/*
    Poll the buttons state.
    button: button pressed or 0xff if none (0 = button released)
    fn:     state of the FN button
*/
bool poll_buttons ( libusb_device_handle *device, uint8_t &button, bool &fn ) {
    uint8_t state[11];
    if ( 0 == libusb_control_transfer ( device,
        LIBUSB_REQUEST_TYPE_CLASS
        | LIBUSB_RECIPIENT_INTERFACE
        | LIBUSB_ENDPOINT_IN,
    REQUEST_BUTTON_STATE,
    0,
    0,
    state,
    11,
    TIMEOUT_MS ) )
        return false;

    button = state[0];
    fn = state[10] & FLAGS_FN;
    return true;
}

}
{% endhighlight %}
