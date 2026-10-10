#include <libproc.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc > 2) {
        return 2;
    }

    pid_t pid = argc == 1 ? getpid() : (pid_t)strtol(argv[1], NULL, 10);
    struct proc_bsdinfo info;
    int result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info));
    if (result != (int)sizeof(info)) {
        return 1;
    }

    printf("%llu.%06llu\n", info.pbi_start_tvsec, info.pbi_start_tvusec);
    return 0;
}
