/******************************************************************
** scheduler_algorithm.c
**
** Implementation of scheduler algorithms
** Easily exchangable because hardware specifics are done in asm code
**
******************************************************************/

/******************************************************************
** Scheduler C definitions
******************************************************************/

// Max number of PCBs to store (>=2)
#define MAX_PCBS 128

/******************************************************************
** Scheduler C structures
******************************************************************/

// List structure
typedef struct _PCBlist_t {
	void* PCB;
	struct _PCBlist_t* next;
	struct _PCBlist_t* last;
} PCBlist_t;

// PCB structure (full implementation in context_pcb.inc)
typedef struct {
	unsigned long PID;
	unsigned long status;
	unsigned long ticks;
	unsigned long wait;
	// and more but that's irrelevant here
} PCB_t;

/******************************************************************
** Scheduler C variables
******************************************************************/

// Full PCB list
PCBlist_t PCBlist[MAX_PCBS];

// Active ptr
PCBlist_t* active = PCBlist;

// next never used spot in PCB list
PCBlist_t* next = 0;

/******************************************************************
** Scheduler C functions
******************************************************************/

// Store new PCB in scheduler queue
// IN: Pointer to newly created PCB
// RET: PID (0xFFFFFFFF on failure)
unsigned long setup_idle(void* PCB)
{
	// Check if anything else has been setup
	if(MAX_PCBS < 2) {
		// Not enough PCBs for anything...
		return 0xFFFFFFFF;
	}
	else if(next == 0) {
		// Nothing setup, so close loop
		PCBlist[0].next = &PCBlist[0];
		PCBlist[0].last = &PCBlist[0];
	}

	// Fake idle task ID to zero -> one arbitrary ID > 0 is never used
	(*(PCB_t*)PCB).PID = 0;

	// Store idle task at first position
	PCBlist[0].PCB = PCB;
	return (*(PCB_t*)PCB).PID;
}

// Store new PCB in scheduler queue
// IN: Pointer to newly created PCB
// RET: PID (0xFFFFFFFF on failure)
unsigned long sched_new(void* PCB)
{
	// Has any PCB been installed?
	if(next == 0) {
		// Initial setup -> first PCB in queue
		PCBlist[1].PCB = PCB;
		PCBlist[0].next = &PCBlist[1];
		PCBlist[0].last = &PCBlist[1];
		PCBlist[1].next = &PCBlist[0];
		PCBlist[1].last = &PCBlist[0];

		// Prepare for more PCBs -> setup next ptr
		next = &PCBlist[2];
		return (*(PCB_t*)PCB).PID;
	}
	else {
		// Check for space before next is used
		PCBlist_t* ptr = &PCBlist[1];
		do {
			// Check if free
			if((*ptr).PCB == 0) {
				// Found free space
				(*ptr).PCB = PCB;

				// Close list loop again
				(*ptr).next = (*active).next;
				(*ptr).last = active;
				(*active).next = ptr;
				(*((*ptr).next)).last = ptr;

				// Return PID
				return (*(PCB_t*)PCB).PID;
			}

			// Select next PCB
			++ptr;
		} while(ptr < next);

		// No free space found, try new one
		if(next >= &PCBlist[MAX_PCBS]) {
			// No more space for new PCBs
			return 0xFFFFFFFF;
		}

		// New space at the end
		(*next).PCB = PCB;

		// Close list loop again
		(*next).next = (*active).next;
		(*next).last = active;
		(*active).next = next;
		(*((*next).next)).last = next;

		// Prepare for more PCBs
		++next;
		return (*(PCB_t*)PCB).PID;
	}

	// General error code
	return 0xFFFFFFFF;
}

// Find PCB in queue by PID
// IN: PID
// RET: Pointer to PCB (0 on failure)
void* sched_find(unsigned long PID)
{
	// Iterate thru list to find PID
	PCBlist_t* ptr = &PCBlist[0];
	do {
		// Compare PIDs
		if((*((PCB_t*)((*ptr).PCB))).PID == PID) {
			// Found it
			return (*ptr).PCB;
		}

		// Next entry
		ptr = (*ptr).next;
	} while(ptr != &PCBlist[0]);

	// Found nothing
	return 0;
}

// Remove PCB from queue by PID
// IN: PID
// RET: Pointer to removed PCB (0 on failure)
void* sched_remove(unsigned long PID)
{
	// Iterate thru list to find PID
	PCBlist_t* ptr = &PCBlist[0];
	do {
		// Compare PID
		if((*((PCB_t*)((*ptr).PCB))).PID == PID) {
			// Check if active
			if(active == ptr)
				return 0;

			// Delete it
			(*((*ptr).last)).next = (*ptr).next;
			(*((*ptr).next)).last = (*ptr).last;
			void* tmp = (*ptr).PCB; // store it temporarily
			(*ptr).PCB = 0;

			// Search if other threads are waiting for this one
			ptr = &PCBlist[0];
			do {
				// Check if blocked and blocked for the right PID
				if((*((PCB_t*)((*ptr).PCB))).status == 0xFFFFFFFF && (*((PCB_t*)((*ptr).PCB))).wait == (*((PCB_t*)tmp)).PID) {
					// Unblock thread
					(*((PCB_t*)((*ptr).PCB))).status = 0;
				}

				// Next entry
				ptr = (*ptr).next;
			} while(ptr != &PCBlist[0]);

			// Return removed PCB
			return tmp;
		}

		// Next entry
		ptr = (*ptr).next;
	} while(ptr != &PCBlist[0]);

	// Found nothing
	return 0;
}

// Get currently active PID and set task status as not running
// IN: ---
// RET: PID of current task
unsigned long sched_getPIDinactive(void)
{
	(*((PCB_t*)((*active).PCB))).status = 0;
	return (*((PCB_t*)((*active).PCB))).PID;
}

// Get currently active PID
// IN: ---
// RET: PID of current task
unsigned long sched_getPID(void)
{
	return (*((PCB_t*)((*active).PCB))).PID;
}

// Get currently active PCB
// IN: ---
// RET: Currently running PCB
void* sched_getPCB(void)
{
	return (*active).PCB;
}

// Select ANOTHER PCB
// IN: Execution time of old task in ticks
// RET: Pointer to new PCB
void* sched_next(unsigned long exec_time)
{
	// Store tick count
	(*((PCB_t*)((*active).PCB))).ticks = exec_time;

	// Select next PCB
	active = (*active).next;

	// Check if it is blocked
	while((*((PCB_t*)((*active).PCB))).status == 0xFFFFFFFF) {
		// Possible deadlock if all tasks are blocked -> idle task schould never be blocked
		active = (*active).next;
	}

	// Return next PCB
	return (*active).PCB;
}

// Select ANOTHER PCB and block current one
// IN: PID to wait for && Execution time of old task in ticks
// RET: Pointer to new PCB (0 on error)
void* sched_block(unsigned long exec_time, unsigned long PID)
{
	// Check if PID of other thread exists
	PCBlist_t* ptr = &PCBlist[0];
	do {
		// Compare PID
		if((*((PCB_t*)((*ptr).PCB))).PID == PID) {
			// Found PID to wait for
			unsigned int max_check = MAX_PCBS;

			// Check if task to wait for is also blocked (iteratively)
			while((*((PCB_t*)((*ptr).PCB))).status == 0xFFFFFFFF) {
				// Search that PCB
				PCBlist_t* tmp = &PCBlist[0];
				do {
					// Compare PIDs
					if((*((PCB_t*)((*tmp).PCB))).PID == (*((PCB_t*)((*ptr).PCB))).wait) {
						// Found it
						ptr = tmp;
						break;
					}

					// Next entry
					tmp = (*tmp).next;
				} while(tmp != &PCBlist[0]);

				// Schould have found it (waiting for nonexistent task is prevented)
				// Continue outer-loop until chain is resolved or loop is found
				if(active == ptr) {
					// Found loop -> deadlock
					// Prevent waiting for this PID
					return 0;
				}

				// Kernel deadlock prevention
				if(max_check-- == 0) {
					// Loop took longer than there are PCBs -> endless loop found
					// Prevent waiting for this PID (other wait-loop already exists)
					return 0;
				}
			}

			// Set blocked and save PID
			(*((PCB_t*)((*active).PCB))).status = 0xFFFFFFFF;
			(*((PCB_t*)((*active).PCB))).wait = PID;
			return sched_next(exec_time);
		}

		// Next entry
		ptr = (*ptr).next;
	} while(ptr != &PCBlist[0]);

	// No matching PID found -> prevent deadlocks by waiting on nonexistent thread
	return 0;
}

