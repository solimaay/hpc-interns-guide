/* OpenMP: one process, several threads. Each thread reports where it runs. */
#define _GNU_SOURCE
#include <stdio.h>
#include <unistd.h>
#include <sched.h>
#include <omp.h>

int main(void) {
    char host[64];
    gethostname(host, sizeof host);

    #pragma omp parallel
    {
        printf("MAP host=%s rank=- thread=%d cpu=%d\n",
               host, omp_get_thread_num(), sched_getcpu());
    }
    return 0;
}
