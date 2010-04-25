#include "common.h"

char * NNTP_USERNAME;
char * NNTP_PASSWORD;
char * NNTP_SERVER;
short NNTP_PORT = 119;
int NNTP_CONNECTIONS = 1;
int NNTP_USETLS = 0;
char * UUDEVIEW;

static char passphrase[BUFSIZ];

void
read_passphrase(void)
{
        struct termios termios_before, termios_echo_off;
        int ret = 0;

        bzero(passphrase, BUFSIZ);

        if (tcgetattr(STDIN_FILENO, &termios_before) == -1) {
                die("%s", "tcgetattr");
        }

        termios_echo_off = termios_before;
        termios_echo_off.c_lflag &= ~ECHO;

        termios_echo_off.c_cc[VMIN] = 1;
        termios_echo_off.c_cc[VTIME] = 0;

        if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &termios_echo_off) == -1) {
                die("%s", "tcsetattr");
        }

        fprintf(stderr, "Enter Password: ");
        fflush(stderr);

        ret = read(0, passphrase, BUFSIZ - 1);
        if (ret <= 0) {
                die("%s", "read");
        }

        if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &termios_before) == -1) {
                die("%s", "tcsetattr");
        }
}


static void
parse_config(xmlDocPtr doc, xmlNodePtr cur)
{
        cur = cur->xmlChildrenNode;
        while (cur != NULL) {
                if (!xmlStrcmp(cur->name, (const xmlChar *) "username")) {
                        NNTP_USERNAME = (char *) xmlNodeListGetString(doc,
                                        cur->xmlChildrenNode, 1);

                } else if (!xmlStrcmp(cur->name, (const xmlChar *) "password")) {
                        NNTP_PASSWORD = (char *) xmlNodeListGetString(doc,
                                        cur->xmlChildrenNode, 1);

                        if (NNTP_PASSWORD &&
			    strncasecmp(NNTP_PASSWORD, "ask", strlen(NNTP_PASSWORD)) == 0) {
                                read_passphrase();
                                NNTP_PASSWORD = passphrase;
                        }

                } else if (!xmlStrcmp(cur->name, (const xmlChar *) "newsserver")) {
                        NNTP_SERVER = (char *) xmlNodeListGetString(doc,
                                        cur->xmlChildrenNode, 1);

                } else if (!xmlStrcmp(cur->name, (const xmlChar *) "uudeview")) {
                        UUDEVIEW = (char *) xmlNodeListGetString(doc,
                                        cur->xmlChildrenNode, 1);

                } else if (!xmlStrcmp(cur->name, (const xmlChar *) "port")) {
                        NNTP_PORT = (unsigned short) atoi((char *)
                                xmlNodeListGetString(doc, cur->xmlChildrenNode, 1));
                        if (NNTP_PORT == 563
                        ||  NNTP_PORT == 443) {
                                NNTP_USETLS = 1;
                        }

                } else if (!xmlStrcmp(cur->name, (const xmlChar *) "connections")) {
                        NNTP_CONNECTIONS = atoi((char *) xmlNodeListGetString(doc,
                                                cur->xmlChildrenNode, 1));
                } else if (!xmlStrcmp(cur->name, (const xmlChar *) "usetls")) {
                        NNTP_USETLS = atoi((char *) xmlNodeListGetString(doc,
                                                cur->xmlChildrenNode, 1));
		}
                cur = cur->next;
        }

        assert(NNTP_SERVER);
}

void
read_config(void)
{
        char path[2048];
        char *home;
        int ret;
        xmlDocPtr doc;
        xmlNodePtr root_element;

        home = getenv("HOME");
        if (home == NULL) {
                die("%s", "please set the environment variable HOME");
        }

        ret = snprintf(path, 2048, "%s/.nzbrc", home);
        if (ret < 0) {
                die("%s", "couldn't prepare path to .nzbrc");
        }

        doc = xmlReadFile(path, NULL, 0);
        if (doc == NULL) {
                die("Failed to parse file '%s'", path);
        }

        root_element = xmlDocGetRootElement(doc);

        if (xmlStrcmp(root_element->name, (const xmlChar *) "nzbconfig")) {
                die("This isn't an nzb config file '%s'", path);
        }

        parse_config(doc, root_element);

        xmlFreeDoc(doc);
}
