#include "common.h"

void
call_uudeview(char *filename)
{
        execlp(UUDEVIEW, "uudeview", "-i", "-c", "-d", "-q", filename, NULL);
        execlp("/usr/bin/uudeview", "uudeview", "-i", "-c", "-d", "-q", filename, NULL);
        die("%s", "unable to exec uudeview");
}
