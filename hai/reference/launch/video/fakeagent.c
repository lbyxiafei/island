// Plays a scripted agent session in a real terminal.
// Script lines: "P<ms>|text" print text after ms; "S|label|file" spinner until file exists; "Z" sleep forever.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
int main(int argc, char **argv) {
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    char line[4096];
    const char *spin[] = {"✻", "✶", "✳", "✢", "·", "✢", "✳", "✶"};
    setvbuf(stdout, NULL, _IONBF, 0);
    while (fgets(line, sizeof line, f)) {
        line[strcspn(line, "\n")] = 0;
        if (line[0] == 'P') {
            char *bar = strchr(line, '|');
            usleep(atoi(line + 1) * 1000);
            printf("%s\n", bar ? bar + 1 : "");
        } else if (line[0] == 'S') {
            char *label = strchr(line, '|') + 1, *file = strchr(label, '|');
            *file++ = 0;
            time_t start = time(NULL);
            for (int i = 0; access(file, F_OK) != 0; i++) {
                printf("\r\033[2K\033[38;5;209m%s %s\033[0m \033[2m(%lds · esc to interrupt)\033[0m", spin[i % 8], label, 60 + (long)(time(NULL) - start));
                usleep(100000);
            }
            printf("\r\033[2K");
        } else if (line[0] == 'Z') {
            for (;;) pause();
        }
    }
    return 0;
}
