// Web fallbacks. The browser has no host uid, disk or file-mode operations.

int? currentUserId() => null;

int? fileOwnerUserId(String path) => null;

int? freeDiskBytes(String path) => null;

bool setFileMode(String path, int mode) => false;

bool createHardLink(String target, String linkPath) => false;

bool commandExists(String command) => false;

bool isMountPoint(String path) => false;
