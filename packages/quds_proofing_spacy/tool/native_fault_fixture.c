// Developer-only fake C ABI for exercising the actual Dart FFI boundary.
// It performs no trained inference and must never be packaged as a runtime.
#include "spacy_pipeline.h"
#include <stdlib.h>
#include <string.h>

struct crispembed_spacy_context { int sentinel; };
struct crispembed_spacy_document { char *text; size_t bytes; };
static int mode;
static int contexts;
static int documents;
static int freed_documents;
static size_t input_bytes;

void fixture_mode(int value) { mode = value; }
int fixture_contexts(void) { return contexts; }
int fixture_documents(void) { return documents; }
int fixture_document_frees(void) { return freed_documents; }
size_t fixture_input_bytes(void) { return input_bytes; }

uint32_t crispembed_spacy_abi_version(void) { return mode == 22 ? 2 : 1; }
uint32_t crispembed_spacy_text_abi_version(void) { return 1; }
uint32_t crispembed_spacy_capabilities(void) { return 3; }
uint32_t crispembed_spacy_context_capabilities(const crispembed_spacy_context *context) {
    return context ? (mode == 21 ? 3 : 15) : 0;
}
crispembed_spacy_context *crispembed_spacy_create_with_resources(
    const char *model, const char *model_hash, const char *resources,
    const char *resources_hash, char *error, size_t capacity) {
    (void)model; (void)model_hash; (void)resources; (void)resources_hash;
    if (mode == 20) {
        if (capacity) { memset(error, 'A', capacity); error[capacity-1] = 0; }
        return NULL;
    }
    crispembed_spacy_context *context = malloc(sizeof(*context));
    if (context) { context->sentinel = 1; contexts++; }
    return context;
}
void crispembed_spacy_free(crispembed_spacy_context *context) {
    if (context) { contexts--; free(context); }
}
int crispembed_spacy_analyze_utf8(crispembed_spacy_context *context,
    const char *text, size_t length, crispembed_spacy_document **out,
    crispembed_spacy_trace_callback trace, void *trace_user,
    crispembed_spacy_cancel_callback cancel, void *cancel_user,
    char *error, size_t capacity) {
    (void)context; (void)trace; (void)trace_user; (void)cancel; (void)cancel_user;
    input_bytes = length;
    *out = NULL;
    if (mode == 2) return 0;
    crispembed_spacy_document *doc = malloc(sizeof(*doc));
    if (!doc) return 4;
    doc->text = malloc(length + 1);
    if (!doc->text) { free(doc); return 4; }
    memcpy(doc->text, text, length);
    doc->text[length] = 0;
    doc->bytes = length;
    *out = doc;
    documents++;
    if (mode == 1 || mode == 13) {
        if (capacity) {
            memset(error, 'E', capacity); // Deliberately no NUL for mode 13.
            if (mode != 13) error[capacity-1] = 0;
        }
        return 5;
    }
    return 0;
}
size_t crispembed_spacy_document_token_count(const crispembed_spacy_document *doc) {
    return mode == 3 ? 2049 : (doc->bytes ? 1 : 0);
}
int crispembed_spacy_document_is_analyzed(const crispembed_spacy_document *doc) {
    (void)doc;
    return mode == 4 ? 0 : 1;
}
static crispembed_spacy_text_view view(const char *text) {
    crispembed_spacy_text_view result = {text, strlen(text)};
    return result;
}
int crispembed_spacy_document_token(const crispembed_spacy_document *doc,
    size_t index, crispembed_spacy_token_view *token) {
    (void)index;
    memset(token, 0, sizeof(*token));
    if (mode == 5) return 2;
    token->text.data = doc->text;
    token->text.length = doc->bytes;
    token->norm = token->text;
    token->lemma = token->text;
    token->tag = view("NN");
    token->pos = view("NOUN");
    token->dependency = view("ROOT");
    token->byte_end = doc->bytes;
    for (size_t i = 0; i < doc->bytes;) {
        unsigned char c = (unsigned char)doc->text[i];
        size_t n = c < 0x80 ? 1 : c < 0xe0 ? 2 : c < 0xf0 ? 3 : 4;
        token->scalar_end++;
        token->utf16_end += n == 4 ? 2 : 1;
        i += n;
    }
    token->head = 0;
    token->flags = CRISPEMBED_SPACY_SENTENCE_START | CRISPEMBED_SPACY_SENTENCE_END;
    switch (mode) {
    case 6: token->text.length = 1024u * 1024u + 1; break;
    case 7: token->text.data = NULL; token->text.length = 1; break;
    case 8: token->text.data = "\xff"; token->text.length = 1; break;
    case 9: token->byte_end--; break;
    case 10: token->utf16_end++; break;
    case 11: token->head = 2; break;
    case 12: token->flags |= 16; break;
    case 14: token->scalar_end++; break;
    case 15: token->flags &= ~CRISPEMBED_SPACY_SENTENCE_END; break;
    }
    return 0;
}
void crispembed_spacy_document_free(crispembed_spacy_document *doc) {
    if (doc) { documents--; freed_documents++; free(doc->text); free(doc); }
}
