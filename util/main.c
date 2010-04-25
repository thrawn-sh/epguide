#include "common.h"

struct timeval start;

int
main(int argc, char **argv)
{
        int ret;
        read_config();

        argc--;
        while (argc) {
                process_nzb_file(argv[argc]);
                argc--;
        }

        ret = gettimeofday(&start, NULL);
        assert(0 <= ret);

        retrieve_files();

        return 0;
}
