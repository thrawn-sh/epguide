#include "common.h"

struct filelist *first = NULL;
struct filelist *last = NULL;

unsigned long long int total = 0;

#if 0 /* debugging purposes */
static void
print_element_names(xmlNodePtr a_node)
{
        xmlNodePtr cur_node = NULL;

        for (cur_node = a_node; cur_node; cur_node = cur_node->next) {
                if (cur_node->type == XML_ELEMENT_NODE) {
                        printf("node type: Element, name: %s\n", cur_node->name);
                }

                print_element_names(cur_node->children);
        }
}

void
print_segment_list(void)
{
        struct filelist *f = first;
        while (f) {
                printf("Group: %s\n", f->group);
                struct segment *s = f->segment;
                while (s) {
                        printf("\tMsgid: %s\n", s->msgid);
                        s = s->next;
                }
                f = f->next;
        }
}
#endif

static void
add_file(void)
{
        struct filelist *p = malloc(sizeof(struct filelist));

        if (p == NULL) {
                die("%s", "malloc");
        }

        if (first == NULL) {
                first = last = p;

        } else {
                last = last->next = p;
        }

        p->next = NULL;
        p->segment = NULL;
        p->group = NULL;
        p->filename = NULL;
        p->bytes = 0;
}

static void
add_segment(xmlChar *key)
{
        struct segment *p = malloc(sizeof(struct segment));


        if (p == NULL) {
                die("%s", "malloc");
        }

        if (last->segment == NULL) {
                last->segment = p;

        } else {
                struct segment *c = last->segment;
                while (c->next != NULL) {
                        c = c->next;
                }
                c->next = p;
        }

        p->next = NULL;
        p->msgid = key;
}

static void
parse_segments(xmlDocPtr doc, xmlNodePtr cur)
{
        cur = cur->xmlChildrenNode;
        while (cur != NULL) {
                if (! xmlStrcmp(cur->name, (const xmlChar *) "segment")) {
                        int ret, bytes_int;
                        xmlChar *key, *bytes;

                        key = xmlNodeListGetString(doc, cur->xmlChildrenNode, 1);
                        assert(key);
                        add_segment(key);

                        bytes = xmlGetProp(cur, (const xmlChar *) "bytes");
                        assert(bytes);

                        ret = sscanf((const char *) bytes, "%u", &bytes_int);
                        assert (0 < ret);

                        total += bytes_int;
                        last->bytes += bytes_int;
                }
                cur = cur->next;
        }
}

static void
parse_groups(xmlDocPtr doc, xmlNodePtr cur)
{
        cur = cur->xmlChildrenNode;
        while (cur != NULL) {
                if (!xmlStrcmp(cur->name, (const xmlChar *) "group")) {
                        last->group = xmlNodeListGetString(doc, cur->xmlChildrenNode, 1);
                        /* only account the first group */
                        return;
                }
                cur = cur->next;
        }
}

static void
parse_filename(xmlDocPtr doc, xmlNodePtr cur)
{
        xmlChar *subject;
        char *start, *end;

        subject = xmlGetProp(cur, (const xmlChar *) "subject");
        if (subject == NULL) {
                return;
        }

        start = strchr((const char *) subject, QUOTE_CHAR);
        if (start == NULL) {
                return;
        }

        start += 1;

        end = strrchr((const char *) subject, QUOTE_CHAR);
        if (end == NULL) {
                return;
        }

        if (start == end) {
                return;
        }

        *end = '\0';

        last->filename = malloc(strlen(start) + 1);
        if (last->filename == NULL) {
                die("%s", "malloc");
        }

        bcopy(start, last->filename, strlen(start) + 1);
}

static void
parse_file(xmlDocPtr doc, xmlNodePtr cur)
{
        add_file();

        parse_filename(doc, cur);

        cur = cur->xmlChildrenNode;
        while (cur != NULL) {
                if (!xmlStrcmp(cur->name, (const xmlChar *) "groups")) {
                        parse_groups(doc, cur);
                }

                if (!xmlStrcmp(cur->name, (const xmlChar *) "segments")) {
                        parse_segments(doc, cur);
                }
                cur = cur->next;
        }
}

static void
parse_nzb(xmlDocPtr doc, xmlNodePtr cur)
{
        cur = cur->xmlChildrenNode;
        while (cur != NULL) {
                if (!xmlStrcmp(cur->name, (const xmlChar *) "file")) {
                        parse_file(doc, cur);
                }
                cur = cur->next;
        }
}

void
process_nzb_file(const char *filename)
{
        xmlDocPtr doc;
        xmlNodePtr root_element;

        doc = xmlReadFile(filename, NULL, 0);
        if (doc == NULL) {
                die("Failed to parse file '%s'", filename);
        }

        root_element = xmlDocGetRootElement(doc);

        if (xmlStrcmp(root_element->name, (const xmlChar *) "nzb")) {
                die("This isn't an nzb xml file '%s'", filename);
        }

        parse_nzb(doc, root_element);

        xmlFreeDoc(doc);
}
