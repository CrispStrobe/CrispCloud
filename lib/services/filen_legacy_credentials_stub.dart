// Browsers have no legacy SDK filesystem credentials to remove. In particular,
// do not attempt dart:io operations and treat an UnsupportedError as success.
void deleteLegacyFilenCredentials(String configPath) {}
