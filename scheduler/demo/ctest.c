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

	// Log something
	const char log[] = "UserProgg!";
	num += write(0, log, sizeof(log));

	// That's it
	return num;
}

