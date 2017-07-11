// pthread_demo.c: First tests for custom pthreads library

/////////////////
// Definitions //
/////////////////

// pthread_yield is non-standard -> only implemented in DHBW kernel
#ifdef __DHBW__
#define sched_yield() pthread_yield()
#endif

////////////
// Header //
////////////

#include <unistd.h>
#ifdef __DHBW__
#include "pthreads.h" // custom Header for pthread_yield
#else
#include <pthread.h> // original Header without pthread_yield
#endif

///////////////////////
// Globale Variablen //
///////////////////////

volatile int my_sync = 0;

//////////////////////
// Thread-functions //
//////////////////////

// Print argument
void* threadA(void* arg)
{
	// Prepare argument
	char argument = ((char)(((int)arg) % 10)) + '0';

	// Print & log something
	char str[] = "Thread O: X";
	str[10] = argument;
	int num = 0;
	num = write(0, str+7, sizeof(str)-7);
	num += write(1, str, sizeof(str));

	// End it
	return arg;
}

// Print in endless loop
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

// Print in yielding loop
void* threadC(void* arg)
{
	// Prepare argument
	char argument = ((char)(((int)arg) % 10)) + '0';

	// Yielding loop
	char str[] = "Thread Y: X";
	str[10] = argument;
	int num = 0;
	for(int j=0; j<5; ++j) {
		// Print & log something
		num += write(0, str+7, sizeof(str)-7);
		num += write(1, str, sizeof(str));

		// Yield to other tasks (standard function)
		num += sched_yield();
	}

	// End it
	return arg;
}

// Print in a long loop
void* threadD(void* arg)
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
void* threadE(void* arg)
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

// Synchronize
void* threadF(void* arg)
{
	// Prepare argument
	int param = (int)arg;
	char argument = ((char)(((int)arg) % 10)) + '0';

	// Print & log something
	char str1[] = "Thread Ss X";
	str1[10] = argument;
	int num = 0;
	num += write(0, str1+7, sizeof(str1)-7);
	num += write(1, str1, sizeof(str1));

	// Waste some time
	for(volatile int i=0; i<0x7FFFFF; ++i);

	// Two options
	if(param == 0) {
		// Long loop
		char str[] = "Thread Sm X";
		str[10] = argument;
		for(int j=0; j<5; ++j) {
			// Print & log something
			num += write(0, str+7, sizeof(str)-7);
			num += write(1, str, sizeof(str));

			// Waste some time
			for(volatile int i=0; i<0x7FFFFF; ++i);
		}

		// Send sync
		my_sync = 1;

		// Print & log something
		const char str3[] = "Thread sync";
		num += write(0, str3+7, sizeof(str3)-7);
		num += write(1, str3, sizeof(str3));
	}
	else {
		// Wait for sync
		char str[] = "Thread Sm X";
		str[10] = argument;
		while(!my_sync) {
			// Print & log something
			num += write(0, str+7, sizeof(str)-7);
			num += write(1, str, sizeof(str));

			// Waste some time
			for(volatile int i=0; i<0x7FFFFF; ++i);
		}
	}

	// Print & log something
	char str2[] = "Thread Se X";
	str2[10] = argument;
	num += write(0, str2+7, sizeof(str2)-7);
	num += write(1, str2, sizeof(str2));

	// End it
	return arg;
}

// Main-function
int main(int argc, char* argv[])
{
	// Create threads
	pthread_t t[9];
	int ret[9];
	ret[0] = pthread_create(&t[0], 0, &threadA, (void*)1);
	ret[1] = pthread_create(&t[1], 0, &threadA, (void*)2);
	ret[2] = pthread_create(&t[2], 0, &threadB, (void*)3);
	ret[3] = pthread_create(&t[3], 0, &threadC, (void*)4);
	ret[4] = pthread_create(&t[4], 0, &threadD, (void*)5);
	ret[5] = pthread_create(&t[5], 0, &threadD, (void*)6);
	ret[6] = pthread_create(&t[6], 0, &threadE, (void*)&t[6]);
	ret[7] = pthread_create(&t[7], 0, &threadF, (void*)0);
	ret[8] = pthread_create(&t[8], 0, &threadF, (void*)1);

	// Print something if pthread_create failed
	int num = 0;
	for(int i=0; i<9; ++i) {
		if(ret[0] != 0) {
			const char result[] = "Unable to create thread!";
			num += write(1, result, sizeof(result));
		}
	}

	// Print & log something
	const char str[] = "MainProgg";
	num += write(0, str, sizeof(str));
	num += write(1, str, sizeof(str));

	// Waste some time
	for(volatile int i=0; i<0x7FFFFF; ++i);

	// Wait for thread 4
	const char join[] = "TryJoin";
	num += write(0, join, sizeof(join));
	num += write(1, join, sizeof(join));
	if(pthread_join(t[4], 0) == 0) {
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

	// Kill thread 2
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

	// Wait for thread 5 -> should already have ended
	num += write(0, join, sizeof(join));
	num += write(1, join, sizeof(join));
	if(pthread_join(t[5], 0) == 0) {
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
	return ret[0]+ret[1]+ret[2]+ret[3]+ret[4]+ret[5]+ret[6]+ret[7]+ret[8];
}

