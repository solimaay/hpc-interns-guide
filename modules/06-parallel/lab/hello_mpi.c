/* MPI: several processes (ranks). Each rank reports where it runs. */
#define _GNU_SOURCE
#include <stdio.h>
#include <unistd.h>
#include <sched.h>
#include <mpi.h>

int main(int argc, char **argv) {
    char host[64];
    int rank;

    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    gethostname(host, sizeof host);

    printf("MAP host=%s rank=%d thread=- cpu=%d\n", host, rank, sched_getcpu());

    MPI_Finalize();
    return 0;
}
