#include "common.h"

#define MINUTE 60
#define HOUR (MINUTE * 60)
#define DAY (HOUR * 24)
#define YEAR (DAY * 365)

#define KBYTE 1024.0
#define MBYTE (1024 * KBYTE)
#define GBYTE (1024 * MBYTE)
#define TBYTE (1024 * GBYTE)

char *
human_readable_seconds(long long seconds, char *output, size_t output_size)
{
        int sum = seconds / YEAR;

        output[0] = '\0';

        if (0 < sum) {
                snprintf(output, output_size, " %dy", sum);
        }
        seconds -= sum * YEAR;

        sum = seconds / DAY;
        if (0 < sum) {
                snprintf(output + strlen(output),
                output_size - strlen(output), " %dd", sum);
        }
        seconds -= sum * DAY;

        sum = seconds / HOUR;
        if (0 < sum) {
                snprintf(output + strlen(output),
                output_size - strlen(output), " %dh", sum);
        }
        seconds -= sum * HOUR;

        sum = seconds / MINUTE;
        if (0 < sum) {
                snprintf(output + strlen(output),
                output_size - strlen(output), " %dm", sum);
        }
        seconds -= sum * MINUTE;

        if (0 < seconds) {
                snprintf(output + strlen(output),
                output_size - strlen(output), " %ds", (int) seconds);
        }

        return output;
}

char *
human_readable_bytes(long long bytes, char *output, size_t output_size)
{
        float sum = bytes / TBYTE;
        if (0 < (int) sum) {
                snprintf(output, output_size, "%.3fT", sum);
                return output;
        }

        sum = bytes / GBYTE;
        if (0 < (int) sum) {
                snprintf(output, output_size, "%.2fG", sum);
                return output;
        }

        sum = bytes / MBYTE;
        if (0 < (int) sum) {
                snprintf(output, output_size, "%.1fM", sum);
                return output;
        }

        sum = bytes / KBYTE;
        if (0 < (int) sum) {
                snprintf(output, output_size, "%.0fK", sum);
                return output;
        }

        snprintf(output, output_size, "0");
        return output;
}
