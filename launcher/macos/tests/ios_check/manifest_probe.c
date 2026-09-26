/* Prints the iOS app's verdict on a Documents directory: "state=N why=...". */
#include <stdio.h>
#include "gow2_ios_install_manifest.h"

int main(int argc, char** argv)
{
    char why[256];
    if (argc < 2)
        return 2;
    const gow2_install_state s = gow2_ios_install_state(argv[1], why, sizeof why);
    printf("state=%d why=%s\n", (int)s, why);
    return 0;
}
