#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <LibreOfficeKit/LibreOfficeKit.h>
#include <LibreOfficeKit/LibreOfficeKitInit.h>

/* Each conversion has its own process and profile. saveAs is synchronous and
 * the document is closed before success. The OS owns process-global office
 * teardown: the release library's explicit office destructor crashes after
 * Writer export in this restricted host. This does not suppress load, save,
 * document-close, signal, timeout, or missing-output failures.
 */
static _Noreturn void finish(int status) {
    fflush(NULL);
    _exit(status);
}

int main(int argc, char **argv) {
    if (argc != 5) {
        fprintf(stderr, "Usage: lok_convert PROGRAM_DIRECTORY PROFILE_URL INPUT OUTPUT_PDF\n");
        return 64;
    }
    LibreOfficeKit *office = lok_init_2(argv[1], argv[2]);
    if (!office) {
        fprintf(stderr, "LibreOfficeKit initialization failed\n");
        return 70;
    }
    char *version = office->pClass->getVersionInfo(office);
    printf("%s\n", version);
    free(version);
    fprintf(stderr, "LOK stage: load\n");
    /* The official batch option disables interactive import dialogs and sets
     * the loader's Silent property, matching headless --convert-to behavior. */
    LibreOfficeKitDocument *document = office->pClass->documentLoadWithOptions(
        office, argv[3], "Batch=true");
    if (!document) {
        char *error = office->pClass->getError(office);
        fprintf(stderr, "LibreOfficeKit import failed: %s\n", error);
        /* Match the CLI's import-refusal status only when the official loader
         * synchronously returned no component. Preserve its exact diagnosis.
         * Other native errors, crashes, and timeouts do not enter this rule. */
        int refused = error && strcmp(error,
            "loadComponentFromURL returned an empty reference") == 0;
        if (refused) {
            fprintf(stderr, "Error: source file could not be loaded\n");
        }
        office->pClass->freeError(error);
        finish(refused ? 1 : 65);
    }
    fprintf(stderr, "LOK stage: save\n");
    int success = document->pClass->saveAs(document, argv[4], "pdf", NULL);
    fprintf(stderr, "LOK save result: %d\n", success);
    if (!success) {
        char *error = office->pClass->getError(office);
        fprintf(stderr, "LibreOfficeKit PDF export failed: %s\n", error);
        office->pClass->freeError(error);
    }
    fprintf(stderr, "LOK stage: close document\n");
    document->pClass->destroy(document);
    fprintf(stderr, "LOK stage: finish\n");
    finish(success ? 0 : 74);
}
