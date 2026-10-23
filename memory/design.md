# Supported project design

## Package interface

The v0.4 development interface declares Emacs 30.1, Org 9.5 and Org-roam 2.2.0. Standard metadata, runtime requirements and autoloads remain. Removed legacy commands and variables have no compatibility aliases. Keybindings remain user-owned examples.

## Organization

The old move/delete commands, deprecated variables and slash aliases are removed. Do not carry their historical target-path defect forward as an open defect in the replacement interface. Org files hold semantic facts; the Org-roam database is their query index, and MOCs are derived views.

The registry is a list of plists describing organizing records rather than a set of hardcoded tag meanings. Names are safe short identifiers; membership uses the configured tag. Exactly one :moc record identifies the map-of-maps role. Basic records declare directories; at this stage non-basic records do not. MOC paths/titles can be overridden or resolved from record names and the MOC directory without mutating the user's registry.

org-roam-organize-directory is the organizing root and must remain inside org-roam-directory. The separate allow-outside-root switch has been removed. MOC capture is invoked with its own template, rather than relying on installing that template globally. Metadata formatting remains a small structured facility; this is not yet a general provider protocol.

## Setup and diagnostics

Setup combines configuration validation and runtime capability checks through one diagnostic result. Deprecated settings are excluded from startup requirements. The user rejected an unrelated tightening that treated every empty string as invalid; do not silently restore that policy.
