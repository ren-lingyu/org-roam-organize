# Supported project design

## Package interface

The package is at the v0.3.0 compatibility boundary, declaring Emacs 30.1, Org 9.5 and Org-roam 2.2.0. Standard metadata, runtime requirements, autoloads and hyphenated variables remain. Old aliases are retained where applicable; default command bindings are examples owned by users.

## Organization

The fixed fleeting-to-permanent move command, headline deletion, related directories and movement variables are obsolete. They remain for compatibility in v0.3.0 and are planned for removal in v0.4.0. Deprecated directory settings no longer gate setup or automatic directory creation. Fleeting notes need not be unfinished permanent notes.

Deletion was deprecated rather than redesigned: without a clear ownership model, removing a note file alone may leave attachments, while recursively deleting its directory may remove unrelated content. A replacement directory/MOC model is deferred.

MOC-tagged file nodes declare the tag they manage in properties, allowing database discovery of tag-to-MOC-ID mappings. Configuration supplies tag/title pairs and a creation template; the top MOC opens by file path. MOC maintenance writes counts and appends missing members as headlines. Literature completion appends citing-node headlines using external citekeys. Neither comprehensively removes stale entries.

## Setup and diagnostics

Setup combines configuration validation and runtime capability checks through one diagnostic result. Deprecated settings are excluded from startup requirements. The user rejected an unrelated tightening that treated every empty string as invalid; do not silently restore that policy.
