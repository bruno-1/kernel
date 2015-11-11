#!/bin/bash

qemu-system-x86_64 -drive file=pgftdemo.flp,index=0,if=floppy,format=raw -m 16M -cpu Nehalem -serial stdio -no-reboot -serial mon:telnet::4444,server,nowait -nographic

