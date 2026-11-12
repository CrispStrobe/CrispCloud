# Maintaining offline help

The canonical guide is [English](../USER_GUIDE.md). The complete
[German](USER_GUIDE.de.md) and [French](USER_GUIDE.fr.md) translations keep the
same 23 stable topic IDs and ordering. All three are bundled with the app.
The help controls support the existing nine UI locales. Other app languages
receive an explicit English fallback and can select an available guide.

## Content and revision workflow

1. Check user instructions against the delivered feature and its source/test
   evidence. Update English first; preserve existing topic IDs for deep links.
2. Run `python3 tool/check_help_guides.py --refresh-source`. This changes only
   the English digest. An older translation stays visibly stale and the
   validator fails until it is reviewed. The app shows current English with
   a localized explanation if a stale translation is bundled.
3. Translate the changed workflow fully, including source/account identity,
   conflict decisions, cancellation/recovery and platform/size limits.
4. After review, run `python3 tool/check_help_guides.py --approve-translation de`
   and/or `--approve-translation fr` for the translations actually reviewed.
   These flags explicitly acknowledge each translation's current English source.
5. Run the default validator and help service/dialog tests. Verify narrow and
   enlarged-text layouts when headings or controls change.

The Linux analysis/test job runs the same validator before resolving app
dependencies. A changed source or translation with an outdated digest fails
that check; the runtime fallback remains available for previously built assets.

The manifest records exact UTF-8 SHA-256 digests, so a content edit cannot
silently retain a valid translation stamp. It is an internal consistency
check, not a signature or a guarantee of linguistic correctness. Human
terminology review remains valuable when adding or materially changing a language.

## Topic and link contract

Each section starts with `<a id="stable-topic-id"></a>` immediately followed by
its level-two heading. IDs remain English machine identifiers in all guides;
headings and body text are translated. The in-app reader removes the anchor
markup and renders one topic at a time, with topic/body search and selectable
text. Context entry points use `showUserGuide(context, topicId: ...)`.

In-bundle topic links work offline. External links open only on a deliberate
click and are limited to HTTPS documentation routes in this repository.
They are supplementary; connection, operations, recovery, encryption and
keyboard instructions are included in each offline guide. Unknown topics,
unavailable links and missing/invalid guides show bounded localized messages.

No screenshots are required for these text-first instructions. If a future
guide adds an image, include its source revision, translated caption, asset
license and replacement workflow; do not rely on remotely hosted images to
explain an essential action.

## Corrected source instructions

This increment reconciles the previous guide with actual source-bound panes,
current keyboard scopes, operation review, guarded saves, full-content
duplicate verification, bounded archive creation, original encryption-key
recovery, protocol-specific proxy routing and application-lifetime scheduling.
It removes unverified package-installation/release promises and unsupported
remote external-editor upload claims. Feature limits remain explicit in all
three translations.
