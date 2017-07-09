# ctest.c
This is a simple c program to test libstartup in our kernel.

# userprogg.asm
These are the original test functions for the custom scheduler.
Now implemented in separate ELF-file.

# pthread_demo.c
Test implementation of pthreads library for our kernel.
Might also run under linux with real pthreads implementation.
Therefore compile as follows:
gcc pthread_demo.c -lpthread -o demo.out

