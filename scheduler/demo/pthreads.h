// pthreads.h: Header file for pthreads, might also use 'real' pthread.h

////////////////
// Structures //
////////////////

typedef unsigned long pthread_t;
typedef void pthread_attr_t;

/////////////////////////
// Function Prototypes //
/////////////////////////

// Cancel running pThread
int pthread_cancel(pthread_t thread);

// Create new pThread
int pthread_create(pthread_t *thread, const pthread_attr_t *attr, void *(*start_routine)(void*), void *arg);

// Exit current pThread
void pthread_exit(void *value_ptr);

// Join running pThread (value pointed by ptr will always be set to zero, not return code)
int pthread_join(pthread_t thread, void **value_ptr);

// Get own pThread ID
pthread_t pthread_self(void);

// Yield to other pThreads
int pthread_yield(void);

