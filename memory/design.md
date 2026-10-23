# Supported project design

## Package interface

Standard Emacs package metadata, runtime requirements and autoloads replace reliance on a personal configuration to make the package loadable. The supported dependency declaration is conservative: Emacs 30.1, Org 9.5 and Org-roam 2.2.0; it is not a measured minimum across older versions.

Public custom variables use hyphens. Old slash spellings remain obsolete aliases, declared before the corresponding custom definitions so pre-load assignments retain their effect. The package no longer installs default keybindings; README bindings and short aliases are user configuration examples.

## Organization

MOCs are ID-linked outlines over Org-roam file nodes. Node tags, file location and outline position remain coupled by the legacy move/delete workflow. Fixed fleeting/permanent directories and movement settings express that convention, not universal attachment ownership.

MOC-tagged nodes carry the tag they manage in properties. Database discovery replaces manually maintained MOC IDs; configuration supplies tag/title pairs and a capture template. The top MOC is opened by file path. MOC updates append missing members and maintain counts; literature completion appends citing-node headlines using external citekeys. These are not full stale-entry reconciliation.
