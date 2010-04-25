#include "common.h"

static int semid;
static int shmid;
static int child;
static long long int *downloaded;
static int progress;
static char indicator[] = { '/', '-', '\\', '|' };
static struct timeval last_ts;
static long long last_downloaded;
static int current_bytes_per_sec;

/* buffers for human redable output */
static char hbuf1[BUFSIZ];
static char hbuf2[BUFSIZ];
static char hbuf3[BUFSIZ];
static char hbuf4[BUFSIZ];
static char hbuf5[BUFSIZ];

static
void cleanup_ipc()
{
        int ret;

        ret = semctl(semid, 0, IPC_RMID);
        if (ret < 0) {
                die("%s", "semctl IPC_RMID");
        }

        ret = shmctl(shmid, IPC_RMID, 0);
        if (ret < 0) {
                die("%s", "shmctl: IPC_RMID");
        }
}

static void
signalhandler(int signal)
{
        if (signal == SIGCHLD) {
                int ret;
                int status;

                while (0 < (ret = waitpid(-1, &status, WNOHANG))) {
                                struct sembuf sops;
                                sops.sem_num = 0;
                                sops.sem_flg = 0;
                                sops.sem_op  = 1;

                                ret = semop(semid, &sops, 1);
                                if (ret < 0) {
                                        die("%s", "semop");
                                }
                }

        } else if (signal == SIGALRM) {
                int ret;
                struct timeval tv;
                int bytes_per_sec = 0;
                long long eta;

                assert(! child);

                ret = gettimeofday(&tv, NULL);
                assert(0 <= ret);

                if (! last_ts.tv_sec) {
                        bcopy(&tv, &last_ts, sizeof(struct timeval));
                        last_downloaded = *downloaded;
                }

                if (4 < (tv.tv_sec - last_ts.tv_sec)) {
                        current_bytes_per_sec = (*downloaded - last_downloaded) / (tv.tv_sec - last_ts.tv_sec);
                        bcopy(&tv, &last_ts, sizeof(struct timeval));
                        last_downloaded = *downloaded;
                }

                eta = tv.tv_sec - start.tv_sec;

                if (eta && *downloaded && *downloaded < total) {
                        bytes_per_sec = *downloaded / eta;
                        eta = (eta * (total - *downloaded)) / *downloaded;

                } else {
                        eta = 0;
                }

#if 0
int err = ioctl (fd, TIOCGWINSZ, (char *) win);
#endif
                fputs("\r                                                                   ", stderr);
                fprintf(stderr, "\r%c [%s / %s] [AVG %sb/s] [CUR %sb/s] [ETA:%s]",
                        indicator[progress % 4],
                        human_readable_bytes(*downloaded, hbuf1, sizeof(hbuf1)),
                        human_readable_bytes(total, hbuf2, sizeof(hbuf2)),
                        human_readable_bytes(bytes_per_sec, hbuf3, sizeof(hbuf3)),
                        human_readable_bytes(current_bytes_per_sec, hbuf4, sizeof(hbuf4)),
                        human_readable_seconds(eta, hbuf5, sizeof(hbuf5)));
                fflush(stderr);
                progress++;
                alarm(1);

        } else if (signal == SIGINT) {
                if (! child) {
                        cleanup_ipc();
                }
                exit(EXIT_FAILURE);

        } else {
                die("Unsupported Signal: %d", signal);
        }
}

static void
retrieve_file(struct filelist *f)
{
        int ret;
        int tempfile;
        char tempname[MAXPATHLEN];
        char * data;
        size_t size;
        struct mailstorage *storage;
        struct mailfolder *folder;
        struct mailmessage *msg;

        storage = mailstorage_new(NULL);

        ret = nntp_mailstorage_init(storage, NNTP_SERVER, NNTP_PORT, NULL,
                NNTP_USETLS ? CONNECTION_TYPE_TLS : CONNECTION_TYPE_PLAIN,
                NNTP_AUTH_TYPE_PLAIN, NNTP_USERNAME, NNTP_PASSWORD, 0, NULL, NULL);

        if (ret != MAIL_NO_ERROR) {
                die("can't connect to newsserver: %s", NNTP_SERVER);
        }

        folder = mailfolder_new(storage, (char *) f->group, NULL);

        ret = mailfolder_connect(folder);
        if (ret != MAIL_NO_ERROR) {
                die("no such newsgroup: %s", (char *) f->group);
        }

        struct segment *s = f->segment;
        ret = mailfolder_get_message_by_uid(folder, "1", &msg);
        assert(ret == 0);

        snprintf(tempname, MAXPATHLEN, "%s", "/dev/shm/nzb-XXXXXXX");

        tempfile = mkstemp(tempname);
        if (tempfile < 0) {
                die("%s", "can't create tempfile.");
        }

        while (s) {
                ret = newsnntp_article_by_message_id(
                        ((struct nntp_session_state_data *) msg->msg_session->sess_data)->nntp_session,
                        (char *) s->msgid, &data, &size);

                if (ret == MAIL_NO_ERROR) {
                        int written = 0;
                        while (written < size) {
                                ret = write(tempfile, data + written, size - written);
                                if (ret < 0) {
                                        die("%s", "couldn't write temporary file");
                                }

                                written += ret;
                                *downloaded += ret;
                        }
                        free(data);
                }
                mailmessage_flush(msg);
                s = s->next;
        }

        close(tempfile);

        mailfolder_free(folder);
        mailstorage_free(storage);

        call_uudeview(tempname);
}

static pid_t
fork_download_process(struct filelist *f)
{
        pid_t pid;

        pid = fork();

        if (pid < 0) {
                die("%s", "fork of download process failed");

        } else if (! pid) {
                child = 1;
                retrieve_file(f);
                exit(EXIT_SUCCESS);
        }

        return pid;
}

static void
install_signalhandlers(void)
{
        int ret;
        struct sigaction action;

        bzero(&action, sizeof(action));
        sigemptyset(&action.sa_mask);
        action.sa_handler = signalhandler;

        ret = sigaction(SIGCHLD, &action, NULL);
        if (ret < 0) {
                die("%s", "sigaction");
        }

        ret = sigaction(SIGINT, &action, NULL);
        if (ret < 0) {
                die("%s", "sigaction");
        }

        ret = sigaction(SIGALRM, &action, NULL);
        if (ret < 0) {
                die("%s", "sigaction");
        }

        alarm(1);
}

static void
install_semaphore(void)
{
        int ret;

        semid = semget(IPC_PRIVATE, 1, 0600 | IPC_CREAT | IPC_EXCL);
        if (semid < 0) {
                die("%s", "semget");
        }

        ret = semctl(semid, 0, SETVAL, NNTP_CONNECTIONS);
        if (ret < 0) {
                die("%s", "semctl");
        }

        shmid = shmget(IPC_PRIVATE, sizeof(unsigned long long int), 0600 | IPC_CREAT | IPC_EXCL);
        if (shmid < 0) {
                die("%s", "shmget");
        }

        downloaded = shmat(shmid, 0, 0);
        assert(0 < downloaded);
}

void
retrieve_files(void)
{
        int ret;
        struct filelist *f;
        struct sembuf sops;

        install_semaphore();
        install_signalhandlers();

        sops.sem_num = 0;
        sops.sem_flg = 0;
        sops.sem_op  = -1;

        f = first;
        while (f && f->filename && !access(f->filename, F_OK)) {
                total -= f->bytes;
                f = f->next;
        }

        while (f) {
again:
                ret = semop(semid, &sops, 1);
                if (ret < 0) {
                        if (errno == EINTR) {
                                goto again;
                        }
                        die("%s", "semop");
                }

                fork_download_process(f);
                f = f->next;
                while (f && f->filename && !access(f->filename, F_OK)) {
                        total -= f->bytes;
                        f = f->next;
                }
        }

        while (semctl(semid, 0, GETVAL, 0) < NNTP_CONNECTIONS) {
                /* wait for childs to finish */
                sleep(1);
        }

        cleanup_ipc();

        fputc('\n', stderr);
}
