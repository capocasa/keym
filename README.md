Mash
====

Mash is a very precise musical virtual keyboard program for Jack MIDI. Press keys on your computer keyboard, and get MIDI output on jack MIDI.

It works similar to the many other musical software keyboards out there, but it's much more precise- try it and feel the difference. There is very little jitter and no more delay than jack has. So while it's not velocity sensitive (organs aren't either), it plays like a serious instrument.

Installation
------------

If you don't have the Nim programming language yet, the easiest way to install it is to do

```
curl https://nim-lang.org/choosenim/init.sh -sSf | sh
```

And then install mash

```
nimble install mash
```

You need to add your user to the `input` group to allow access.

```
export USER=`whoami`
echo $USER  # check it's the right one
sudo usermod -aG input $USER
groups  # check that "input" is there
```

Usage
-----

Run it in a terminal. There is no output unless a note is late.

```
$ mash
```

If you get a "cannot open" error, you need to find the /dev/input device for
your main keyboard. Look it up in the device list.

```
less /proc/bus/input/devices
```

Your keyboard should have 'keyboard' in the name. Once you've found it, there will be an entry 'eventX' under 'Handlers', for example `event5`. Your path is `/dev/input/eventX`. Then you run

```
mash /dev/input/event5
```

You can also run it as a service, it's quite light.

Connect it to a software instrument using a jack tool. On the command line:

```
$ # list ports
$ jack_lsp
system:capture_1
system:capture_2
system:playback_1
system:playback_2
yoshimi:left
yoshimi:right
yoshimi:midi in
mash:out
$ jack_connect mash:out "yoshimi:midi in"

```

Now press keys and notes should arrive in your software instrument.

To exit, press Ctrl-C or kill the process

```
killall keym
```

For some finetuning, you can try lower latency. A realtime kernel is recommended. Normally this value should be the same as your jack buffer size.

```
mash -n1  # 2 is default
mash -n0  # 2 is default
```

By default, the keyboard handler has priority 98, but you can change it

```
mash -p90  # maybe this works even better
```

Key mapping
-----------

| Keys | Notes |
| - | - |
| Z X C V B N M , . / | An octave and a half of white piano keys, MIDI notes 60-77  |
| S D G H J L ; | The corresponding black piano keys  |
| Q W E R T Y U I O P [ ] | Another octave and a half of white piano keys, one octave higher, MIDI notes 72-89  |
| 2 3 5 6 7 8 0 | The corresponding black piano keys  |
| Left/Right Arrow | Transpose on semitone up or down |
| Up/Down Arrow | Transpose one octave up or down |
| Esc | Send "all notes off" or panic key |
| F1 - F12 | Set active channel to 1 through 12 |
| Home, End, Insert, Delete | Send active channel to 13, 14, 15, 16 |

This for an American keyboard. The keys are unaffected by international keyboard layouts, so the key position will be the same no matter what layout you have, but a different glyph might be printed on them.

Limitations
-----------

Currently mash only supports linux, and possibly other OS who have /dev/input keyboard events. Implementing other operating systems would be very cool, it just hasn't been done yet.

Internals
---------

Mash reads keyboard events directly from the keyboard driver via /dev/input and translates the kernel keyboard timestamp to jack sound card time via a clock sync that is done at the beginning of every jack period. The keyboard timestamps are delayed by the standard jack latency of two periods to avoid jitter.

Most other keyboard instruments use the windowing system keyboard API- this is a big no-no, because there can be wildly varying delays and jitter, and there are different keyboard layouts to worry about.

License
-------

MIT License

Changelog
---------

```
0.1.0 Inital release- it works!
```

