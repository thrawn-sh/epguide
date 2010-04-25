#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <assert.h>
#include <errno.h>
#include <sys/wait.h>
#include <sys/types.h>
#include <signal.h>
#include <sys/time.h>
#include <sys/socket.h>
#include <netinet/ip.h>
#include <netinet/ip_icmp.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <syslog.h>
#include <sys/ipc.h>
#include <sys/sem.h>
#include <sys/shm.h>
#include <termios.h>

#include <libxml/parser.h>
#include <libxml/tree.h>

#include <libetpan/libetpan.h>
#include <libetpan/mailstorage_types.h>

/* Macros */

#define die(format, ...) \
{ \
        char buf[BUFSIZ]; \
        snprintf(buf, sizeof(buf), \
                        "%s(%d): %d: %s: " format, \
                        __FILE__, getpid(), (int) __LINE__, __FUNCTION__,  __VA_ARGS__); \
        perror(buf); \
        exit(EXIT_FAILURE); \
}

#define QUOTE_CHAR '"'

/* Function prototypes */

void
process_nzb_file(const char *filename);

void
retrieve_files(void);

void
call_uudeview(char *filename);

void
read_config(void);

char *
human_readable_seconds(long long bytes, char *output, size_t output_size);

char *
human_readable_bytes(long long bytes, char *output, size_t output_size);

/* Global Datastructures */

struct segment
{
        struct segment *next;
        xmlChar *msgid;
};

struct filelist
{
        struct filelist *next;
        struct segment *segment;
        xmlChar *group;
        char *filename;
        int bytes;
};

/* Global Datastructure Prototypes */

extern struct timeval start;

extern struct filelist *first;
extern struct filelist *last;

extern unsigned long long int total;

extern char * NNTP_USERNAME;
extern char * NNTP_PASSWORD;
extern char * NNTP_SERVER;
extern short NNTP_PORT;
extern int NNTP_CONNECTIONS;
extern int NNTP_USETLS;
extern char * UUDEVIEW;
