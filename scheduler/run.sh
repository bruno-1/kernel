#!/bin/bash

make && qemu-system-x86_64 -fda scheduler.flp -m 1024M -curses

