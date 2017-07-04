# Falling sand game

This is a falling sand game, based on the idea found in [a game from
dan-ball.jp](https://dan-ball.jp/en/javagame/dust/). It is written in x86
assembly, and the binary fits is 512 bytes.

In order to run it, you need `nasm`. After installing `nasm`, simply run the
Makefile and the `.flp` file will contain the binary. This file can then be
written as the first 512 bytes of an usb, which will then be bootable, or you
can put it in a floppy controller in virtualbox.

# Usage:

Move around the cursor with arrow keys. Press `s` to pause/unpause. The keys 1,
2, 3 and 4 (not numpad) will spawn the various materials available.

    List of materials:
     1 ' ' : air
     2 '#' : wall
     3 '~' : water
     4 '.' : sand

Wall and air never moves. Sand and water falls if above air. If sand is on solid
ground it will form a pile, and if water is on solid ground, it will form a
lake.
