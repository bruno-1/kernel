// ctest.c: Execute c-program in our kernel

// Header
#include <unistd.h>

// Main-function
int main(int argc, char* argv[])
{
	// Print something
	const char str[] = "Hello World!";
	int num = 0;
	num = write(1, str, sizeof(str));

	// That's it
	return num;
}

