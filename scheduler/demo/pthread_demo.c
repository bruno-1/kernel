// pthread_demo.c: First tests for custom pthreads library

////////////
// Header //
////////////

#include <pthread.h>
#include <unistd.h>

//////////////////////
// Thread-functions //
//////////////////////

// Print argument
void* threadA(void* arg)
{
	// Prepare argument
	char argument = ((char)(((int)arg) % 10)) + '0';

	// Print & log something
	char str[] = "Thread S: X";
	str[10] = argument;
	int num = 0;
	num = write(0, str+7, sizeof(str)-7);
	num += write(1, str, sizeof(str));

	// End it
	return arg;
}

// Print in Endless loop
void* threadB(void* arg)
{
	// Prepare argument
	char argument = ((char)(((int)arg) % 10)) + '0';

	// Endless loop
	char str[] = "Thread E: X";
	str[10] = argument;
	int num = 0;
	while(1) {
		// Print & log something
		num += write(0, str+7, sizeof(str)-7);
		num += write(1, str, sizeof(str));

		// Waste some time
		for(volatile int i=0; i<0x7FFFFF; ++i);
	}

	// End it
	return arg;
}

// Print in a long loop
void* threadC(void* arg)
{
	// Prepare argument
	char argument = ((char)(((int)arg) % 10)) + '0';

	// Long loop
	char str[] = "Thread L: X";
	str[10] = argument;
	int num = 0;
	Label_start:
	for(int j=0; j<5; ++j) {
		// Print & log something
		num += write(0, str+7, sizeof(str)-7);
		num += write(1, str, sizeof(str));

		// Waste some time
		for(volatile int i=0; i<0x7FFFFF; ++i);
	}

	// Print & log something
	num += write(0, str+7, sizeof(str)-7);
	num += write(1, str, sizeof(str));

	// End it
	pthread_exit(arg);
	goto Label_start; // Just making sure to never return
	return (void*)num;
}

// Print argument (PID)
void* threadD(void* arg)
{
	// Prepare argument
	char argument = ((char)((*((int*)arg)) % 10)) + '0';

	// Print & log something
	char str[] = "Thread PX-X";
	str[8] = (char)(pthread_self() % 10) + '0';
	str[10] = argument;
	int num = 0;
	num = write(0, str+7, sizeof(str)-7);
	num += write(1, str, sizeof(str));

	// End it
	return arg;
}

// Main-function
int main(int argc, char* argv[])
{
	// Create threads
	pthread_t t[6];
	int ret[6];
	ret[0] = pthread_create(&t[0], 0, &threadA, (void*)1);
	ret[1] = pthread_create(&t[1], 0, &threadA, (void*)2);
	ret[2] = pthread_create(&t[2], 0, &threadB, (void*)3);
	ret[3] = pthread_create(&t[3], 0, &threadC, (void*)4);
	ret[4] = pthread_create(&t[4], 0, &threadC, (void*)5);
	ret[5] = pthread_create(&t[5], 0, &threadD, (void*)&t[5]);

	// Print & log something
	const char str[] = "MainProgg";
	int num = 0;
	num += write(0, str, sizeof(str));
	num += write(1, str, sizeof(str));

	// Waste some time
	for(volatile int i=0; i<0x7FFFFF; ++i);

	// Wait for thread
	const char join[] = "TryJoin";
	num += write(0, join, sizeof(join));
	num += write(1, join, sizeof(join));
	if(pthread_join(t[3], 0) == 0) {
		const char result[] = "Successful Join";
		num += write(0, result, sizeof(result));
		num += write(1, result, sizeof(result));
	}
	else {
		const char result[] = "Failed Join";
		num += write(0, result, sizeof(result));
		num += write(1, result, sizeof(result));
	}

	// Waste some more time
	for(volatile int i=0; i<0x7FFFFF; ++i);

	// Kill thread
	if(pthread_cancel(t[2]) == 0) {
		const char result[] = "Successful Kill";
		num += write(0, result, sizeof(result));
		num += write(1, result, sizeof(result));
	}
	else {
		const char result[] = "Failed Kill";
		num += write(0, result, sizeof(result));
		num += write(1, result, sizeof(result));
	}

	// Waste some more time
	for(volatile int i=0; i<0x7FFFFF; ++i);

	// Wait for thread -> should already have ended
	num += write(0, join, sizeof(join));
	num += write(1, join, sizeof(join));
	if(pthread_join(t[4], 0) == 0) {
		const char result[] = "Failed not Joining";
		num += write(0, result, sizeof(result));
		num += write(1, result, sizeof(result));
	}
	else {
		const char result[] = "Successfully not Joined";
		num += write(0, result, sizeof(result));
		num += write(1, result, sizeof(result));
	}

	// That's it
	return ret[0]+ret[1]+ret[2]+ret[3]+ret[4]+ret[5];
}

