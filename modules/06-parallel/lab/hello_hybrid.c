/* Hybrid: several MPI ranks, each with several OpenMP threads. */
#define _GNU_SOURCE
#include <stdio.h>
#include <unistd.h>
#include <sched.h>
#include <mpi.h>
#include <omp.h>

int main(int argc, char **argv) {
    char host[64];
    int provided, rank;

    MPI_Init_thread(&argc, &argv, MPI_THREAD_FUNNELED, &provided);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    gethostname(host, sizeof host);

    #pragma omp parallel
    {
        printf("MAP host=%s rank=%d thread=%d cpu=%d\n",
               host, rank, omp_get_thread_num(), sched_getcpu());
    }

    MPI_Finalize();
    return 0;
}
