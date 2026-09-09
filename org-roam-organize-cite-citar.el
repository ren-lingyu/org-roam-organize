;;; org-roam-organize-cite-citar.el --- Citar adapter for Org-roam Organize -*- lexical-binding: t; -*-

;;; Commentary:

;; This optional adapter lets Citar select, activate, and act on bibliography
;; citekeys while Org files continue to store managed literature node UUIDs as
;; Org Cite keys.  Loading this library does not load Citar; adapter setup
;; loads Citar only when the Citar backend is enabled.

;;; Code:

(require 'rx)
(require 'org-roam-organize-core)
(require 'org-roam-organize-capture)
(require 'org-roam-organize-cite)

(defvar org-roam-organize-mode)

(declare-function citar-key-at-point "citar" ())
(declare-function citar-citation-at-point "citar" ())
(declare-function citar-get-entries "citar" ())
(declare-function citar-run-default-action "citar" (citekeys))
(declare-function citar-register-notes-source "citar" (name config))
(declare-function citar-remove-notes-source "citar" (name))
(declare-function citar-create-note "citar" (key &optional entry))
(declare-function citar-format--entry
                  "citar-format" (format entry &optional width &rest options))
(declare-function citar-org-cite-basic-activate "citar-org" (citation))
(declare-function org-roam-node-from-id "org-roam-node" (id))
(declare-function org-roam-node-visit
                  "org-roam-node" (node &optional other-window force))
(declare-function org-roam-ref-add "org-roam-node" (ref))
(declare-function org-roam-db-update-file
                  "org-roam-db" (&optional file-path deprecated-arg))

(defvar citar--entries)
(defvar citar-notes-source)
(defvar citar-notes-sources)

(defconst org-roam-organize-cite-citar--minimum-tested-version "1.4.0"
  "The value records the minimum tested Citar version.

This value documents the compatibility baseline used by maintainers.  Setup
does not compare installed package versions because Citar does not expose a
portable runtime version API; actual compatibility is validated through
`org-roam-organize-cite-citar--capability-alist' and adapter integration
tests.")

(defconst org-roam-organize-cite-citar--capability-alist
  '((citar-at-point-function . variable)
    (citar--entries . variable)
    (citar-notes-source . variable)
    (citar-notes-sources . variable)
    (citar-get-entry . function)
    (citar-get-entries . function)
    (citar-key-at-point . function)
    (citar-citation-at-point . function)
    (citar-run-default-action . function)
    (citar-register-notes-source . function)
    (citar-remove-notes-source . function)
    (citar-create-note . function)
    (citar-format--entry . function)
    (citar-dwim . function)
    (citar-insert-citation . function)
    (citar-org-insert-citation . function)
    (citar-org-select-key . function)
    (citar-org-follow . function)
    (citar-org-cite-basic-activate . function)
    (org-roam-node-from-id . function)
    (org-roam-node-visit . function)
    (org-roam-ref-add . function)
    (org-roam-db-update-file . function))
  "The alist describes runtime capabilities expected by the Citar adapter.

Each entry maps a Citar symbol to the capability type accepted by
`org-roam-organize--check-capabilities'.  Setup checks the table only after
loading `citar' and `citar-org'.  It includes the functions called or advised
by the adapter, the public Citar boundaries whose behavior the adapter is
intended to preserve, and the internal `citar--entries' dynamic-binding
contract exercised by activation integration tests.")

(defconst org-roam-organize-cite-citar--uuid-regexp
  (rx string-start
      (= 8 xdigit) "-"
      (= 4 xdigit) "-"
      (= 4 xdigit) "-"
      (= 4 xdigit) "-"
      (= 12 xdigit)
      string-end)
  "The regexp matches UUID-shaped citation keys used by Org-roam Organize.

The regexp accepts hexadecimal UUID text in the canonical 8-4-4-4-12 layout.
It identifies keys that require a managed UUID-to-citekey mapping; it does not
verify that a matching Org-roam node exists.")

(defconst org-roam-organize-cite-citar--default-title-format "${title}"
  "The Citar format used for node titles when no backend title is configured.")

(defconst org-roam-organize-cite-citar--notes-source
  'org-roam-organize-cite-citar
  "The symbol identifies Org-roam Organize's Citar notes source.

Setup will reject an existing source with this name instead of replacing
configuration owned by another package or an earlier incomplete installation.")

(defconst org-roam-organize-cite-citar--notes-config
  (list :name "Org-roam Organize Notes"
        :category 'org-roam-node
        :items 'org-roam-organize-cite-citar--get-notes
        :hasitems 'org-roam-organize-cite-citar--has-notes
        :open 'org-roam-organize-cite-citar--open-note
        :create 'org-roam-organize-cite-citar--create-note)
  "The plist describes Org-roam Organize's Citar notes source.

The callbacks use managed node UUIDs as Citar note identifiers.  The `:create'
callback is implemented with the node-creation stage of the adapter; source
registration occurs only after every callback and capability is available.

Rationale: A formal notes source preserves Citar's note selection and action
pipeline while keeping UUID-to-citekey translation inside the adapter.")

(defvar org-roam-organize-cite-citar--installed-p nil
  "The value is non-nil when the complete Citar adapter is installed.")

(defvar org-roam-organize-cite-citar--previous-at-point-function nil
  "The value stores Citar's default at-point function before installation.

Teardown restores this value only while the adapter still owns Citar's current
default, so a later user change is preserved.")

(defvar org-roam-organize-cite-citar--previous-notes-source nil
  "The value stores Citar's notes source before adapter installation.

Teardown restores this value only while the adapter still owns both its
registered source configuration and `citar-notes-source'.")

(defun org-roam-organize-cite-citar--notes-source-owned-p ()
  "Return non-nil when Citar retains this adapter's notes source config.

Compare the registered plist for
`org-roam-organize-cite-citar--notes-source' with
`org-roam-organize-cite-citar--notes-config'.  Return nil when Citar is not
loaded, the source is absent, or another value now owns that source name.
This function does not modify Citar state.

Rationale: Teardown should undo configuration installed by this adapter without
removing a later replacement that happens to reuse the same symbol."
  (and (boundp 'citar-notes-sources)
       (equal
        (cdr (assq org-roam-organize-cite-citar--notes-source
                   citar-notes-sources))
        org-roam-organize-cite-citar--notes-config)))

(defun org-roam-organize-cite-citar--ensure-mode ()
  "Require Org-roam Organize mode for Citar adapter operations.

Signal `user-error' when `org-roam-organize-mode' is nil.  Return non-nil when
the mode is enabled.

Rationale: Advice functions and at-point commands can be invoked through Citar
instead of the core mode lifecycle, so each stateful operation must enforce the
package mode boundary itself."
  (unless org-roam-organize-mode
    (user-error "Org-roam Organize mode must be enabled"))
  t)

(defun org-roam-organize-cite-citar--cite-record ()
  "Return the configured citation registry record.

Signal `user-error' unless exactly one `:cite t' record is configured.  Require
`org-roam-organize-mode' to be enabled.

Implementation notes: The function uses
`org-roam-organize--registry-cite-records' to enforce the same registry
selection boundary as core citation synchronization and export mapping.

Rationale: Keeping record selection in one helper lets adapter queries and node
creation share the same registry identity instead of independently selecting a
tag and capture template."
  (org-roam-organize-cite-citar--ensure-mode)
  (let ((records (org-roam-organize--registry-cite-records)))
    (cond
     ((null records)
      (user-error "No :cite t registry record is configured"))
     ((cdr records)
      (user-error "Multiple :cite t registry records are configured"))
     (t
      (car records)))))

(defun org-roam-organize-cite-citar--cite-record-tag ()
  "Return the tag of the configured citation registry record.

Signal `user-error' unless exactly one `:cite t' record with a string tag is
configured.  Require `org-roam-organize-mode' to be enabled.

Implementation notes: Record selection is delegated to
`org-roam-organize-cite-citar--cite-record' so creation and database queries
use the same citation record boundary."
  (let ((tag
         (org-roam-organize--record-tag
          (org-roam-organize-cite-citar--cite-record))))
    (if (stringp tag)
        tag
      (user-error "The :cite t registry record has no valid tag"))))

(defun org-roam-organize-cite-citar--get-notes (&optional citekeys)
  "Return managed Org-roam note identifiers for CITEKEYS.

Return a hash table mapping each external citekey to a list of managed
literature node UUIDs.  When CITEKEYS is nil, include every managed citekey;
otherwise include only matching keys.  Duplicate database rows are removed
without discarding distinct nodes for an ambiguous citekey.  Signal
`user-error' when `org-roam-organize-mode' is disabled or the citation registry
record is invalid.  This function reads the Org-roam database and does not
modify buffers or files.

Implementation notes:
`org-roam-organize--cite-managed-identity-map-data' queries the citation
record's managed level-0 nodes and constructs both lookup directions.  This
function returns its citekey-to-UUID table directly.

Rationale: Citar's `:items' callback must represent missing and multiple notes
instead of enforcing the stricter single-result contract used when inserting a
citation."
  (org-roam-organize-cite-citar--ensure-mode)
  (let* ((tag (org-roam-organize-cite-citar--cite-record-tag))
         (map-data
          (org-roam-organize--cite-managed-identity-map-data
           tag
           (if citekeys 'citekey 'all)
           citekeys)))
    (plist-get map-data :citekey-to-uuids)))

(defun org-roam-organize-cite-citar--has-notes ()
  "Return a predicate that tests whether a citekey has managed notes.

Return nil when no managed citation nodes exist.  Otherwise return a function
of one CITEKEY that is non-nil exactly when the database snapshot taken by this
call contains at least one corresponding node.  Signal `user-error' under the
same invalid mode or registry conditions as
`org-roam-organize-cite-citar--get-notes'.

Implementation notes: The function loads all notes once and closes over their
hash table so Citar can test many bibliography entries without issuing one
database query per entry.

Rationale: This matches Citar's `:hasitems' callback contract rather than
mistaking it for a predicate called separately for each citekey."
  (let ((notes (org-roam-organize-cite-citar--get-notes)))
    (unless (= (hash-table-count notes) 0)
      (lambda (citekey)
        (and (gethash citekey notes) t)))))

(defun org-roam-organize-cite-citar--open-note (uuid)
  "Visit the managed Org-roam node identified by UUID.

UUID is the note identifier previously returned by
`org-roam-organize-cite-citar--get-notes'.  Signal `user-error' when
`org-roam-organize-mode' is disabled, UUID is not a string, or no current
Org-roam database node has that ID.  Return the value of
`org-roam-node-visit'; visiting may change the selected buffer and window.

Implementation notes: Resolve the current node with `org-roam-node-from-id'
immediately before visiting it instead of retaining file paths or database
positions in Citar candidates.

Rationale: Org-roam owns node locations, while the stable UUID is sufficient
for Citar's note selection boundary."
  (org-roam-organize-cite-citar--ensure-mode)
  (unless (stringp uuid)
    (user-error "Citar note ID must be a node UUID string"))
  (if-let* ((node (org-roam-node-from-id uuid)))
      (org-roam-node-visit node)
    (user-error "No Org-roam node for Citar note ID: %s" uuid)))

(defun org-roam-organize-cite-citar--validate-info-formats (formats)
  "Validate Citar capture info FORMATS and return non-nil.

FORMATS must be nil or a proper plist whose keys are unique keywords and whose
values are Citar format strings.  Signal `user-error' for malformed input.
This function does not load Citar, parse format strings, or inspect an entry.

Rationale: Capture info names belong to user configuration, while the adapter
must reject ambiguous or incomplete mappings before starting a capture."
  (unless (org-roam-organize--plistp formats)
    (user-error "Citar backend :info must be a proper plist"))
  (let (seen)
    (while formats
      (let ((key (pop formats))
            (format-string (pop formats)))
        (unless (keywordp key)
          (user-error "Citar backend :info key must be a keyword: %S" key))
        (when (memq key seen)
          (user-error "Duplicate Citar backend :info key: %S" key))
        (unless (stringp format-string)
          (user-error
           "Citar backend :info format for %S must be a string"
           key))
        (push key seen))))
  t)

(defun org-roam-organize-cite-citar--validate-backend-options (record)
  "Validate the Citar backend options in registry RECORD and return non-nil.

Accept only unique `:title' and `:info' keys.  `:title', when present, must be
a string.  `:info' is validated by
`org-roam-organize-cite-citar--validate-info-formats'.  A symbol backend has no
options and is valid.  Signal `user-error' for an unknown, duplicated, or
malformed option.

Implementation notes: Core registry validation owns the generic tagged backend
shape.  This adapter owns the meaning of the option plist and validates it
during setup so failure disables only the optional backend."
  (let ((options (org-roam-organize--record-backend-options record))
        seen)
    (unless (org-roam-organize--plistp options)
      (user-error "Citar backend options must be a proper plist"))
    (while options
      (let ((key (pop options))
            (value (pop options)))
        (unless (memq key '(:title :info))
          (user-error "Unknown Citar backend option: %S" key))
        (when (memq key seen)
          (user-error "Duplicate Citar backend option: %S" key))
        (push key seen)
        (pcase key
          (:title
           (unless (stringp value)
             (user-error "Citar backend :title must be a format string")))
          (:info
           (org-roam-organize-cite-citar--validate-info-formats value)))))
    t))

(defun org-roam-organize-cite-citar--creation-request (record citekey entry)
  "Return a managed capture request for RECORD, CITEKEY, and Citar ENTRY.

Interpret RECORD's Citar backend `:title' and `:info' values as Citar format
strings.  Return a plist containing the formatted `:title' and `:info'.  Use
`org-roam-organize-cite-citar--default-title-format' when `:title' is absent,
and fall back to CITEKEY when the formatted title is blank.  Preserve
configured empty info strings so Org-roam does not prompt for those
placeholders.

Signal `user-error' when the backend options are invalid or Citar returns a
non-string formatted value.  This function does not query the bibliography,
start capture, or modify ENTRY.

Rationale: Citar owns bibliography parsing and interpolation, while the record
declares how formatted strings map onto Org-roam capture information."
  (org-roam-organize-cite-citar--validate-backend-options record)
  (let* ((options (org-roam-organize--record-backend-options record))
         (title-format
          (if (plist-member options :title)
              (plist-get options :title)
            org-roam-organize-cite-citar--default-title-format))
         (title (citar-format--entry title-format entry))
         (info-formats (plist-get options :info))
         info)
    (unless (stringp title)
      (user-error "Citar formatted node title must be a string"))
    (while info-formats
      (let* ((key (pop info-formats))
             (format-string (pop info-formats))
             (value (citar-format--entry format-string entry)))
        (unless (stringp value)
          (user-error
           "Citar formatted capture info for %S must be a string"
           key))
        (setq info (plist-put info key value))))
    (list :title
          (if (org-roam-organize--blank-string-p title) citekey title)
          :info info)))

(defun org-roam-organize-cite-citar--store-cite-ref (citekey)
  "Persist CITEKEY as a cite ref on the node at point.

Add `@CITEKEY' to the current Org-roam node, save its file, and immediately
update that file in the Org-roam database.  Signal `user-error' when the
current buffer does not visit a file.  Propagate errors from Org-roam property
mutation, saving, or database update.

Implementation notes: This function runs from the successful-finalize callback
installed by `org-roam-organize--capture-node'.  Explicit database update keeps
the new mapping observable even when Org-roam autosync is disabled.

Rationale: The adapter, rather than the user's capture template, owns the cite
ref required for UUID-to-citekey translation."
  (unless (buffer-file-name (or (buffer-base-buffer) (current-buffer)))
    (user-error "Cannot store a cite ref outside a file-visiting buffer"))
  (org-roam-ref-add (concat "@" citekey))
  (save-buffer)
  (org-roam-db-update-file))

(defun org-roam-organize-cite-citar--create-note (citekey entry)
  "Create a managed citation-record node for CITEKEY and ENTRY.

CITEKEY is supplied by Citar and must be a non-blank string.  ENTRY is Citar's
bibliography entry.  The citation record's tagged backend options format the
initial node title and capture info; a blank title falls back to CITEKEY.  Start
the record's managed capture when no corresponding node exists.  Signal
`user-error' without opening or modifying a node when one already exists, when
multiple nodes make the mapping ambiguous, or when the citation record cannot
produce a capture template.  Existing-node errors identify the citation record
by its configured `:name'.

The capture remains interactive and finalizes by visiting the created file.
Only successful finalization adds the cite ref, saves the file, and updates the
Org-roam database.  This function does not invoke the record's ordinary
`:provider'.  The capture template remains responsible for writing the
citation record's tag; a created node without that tag is outside the managed
note lookup and citekey-to-UUID mapping boundary.

Implementation notes: `org-roam-organize-cite-citar--get-notes' performs the
preflight lookup.  Creation delegates to `org-roam-organize--capture-node' with
a lexical success callback that calls
`org-roam-organize-cite-citar--store-cite-ref'.

Rationale: Citar owns bibliography selection, while Org-roam Organize owns the
managed node layout and the cite ref needed by its UUID citation model."
  (org-roam-organize-cite-citar--ensure-mode)
  (unless (and (stringp citekey)
               (not (org-roam-organize--blank-string-p citekey)))
    (user-error "Citar citekey cannot be empty"))
  (let* ((record (org-roam-organize-cite-citar--cite-record))
         (record-name (org-roam-organize--record-name record))
         (matches
          (gethash citekey
                   (org-roam-organize-cite-citar--get-notes (list citekey)))))
    (cond
     ((null matches)
      (let ((template
             (org-roam-organize--record-node-capture-template record))
            (request
             (org-roam-organize-cite-citar--creation-request
              record citekey entry)))
        (unless (and template (car-safe template))
          (user-error
           "Cannot create a managed node for citation record: %S"
           record))
        (org-roam-organize--capture-node
         (plist-get request :title)
         template
         (plist-get request :info)
         '(:finalize find-file)
         record
         (lambda ()
           (org-roam-organize-cite-citar--store-cite-ref citekey)))))
     ((cdr matches)
      (user-error
       (concat "Multiple managed nodes for citation record %S already exist "
               "for citekey %s: %s")
       record-name
       citekey
       (mapconcat #'identity matches ", ")))
     (t
      (user-error
       (concat "A managed node for citation record %S already exists "
               "for citekey %s: %s")
       record-name
       citekey
       (car matches))))))

(defun org-roam-organize-cite-citar--citekeys-to-uuids (citekeys)
  "Return managed citation-record node UUIDs corresponding to CITEKEYS.

The returned UUID list preserves the order and multiplicity of CITEKEYS.
Signal `user-error' identifying the citation record by its configured `:name'
when no managed node declares a citekey.  Also signal `user-error' when more
than one managed node declares a citekey or when `org-roam-organize-mode' is
disabled.  The function reads the Org-roam database and does not modify it or
the current buffer.

Implementation notes:
`org-roam-organize--cite-managed-identity-map-data' loads both directions for
the selected external citekeys in one database query.  This function restores
input order and applies the strict insertion policy.

Rationale: Citar selects external citekeys, but Org-roam Organize stores UUIDs
in Org citations.  Reverse mapping must reject duplicate citekeys because
silently choosing a node would make insertion nondeterministic."
  (org-roam-organize-cite-citar--ensure-mode)
  (let* ((record (org-roam-organize-cite-citar--cite-record))
         (record-name (org-roam-organize--record-name record))
         (tag (org-roam-organize-cite-citar--cite-record-tag))
         (map-data
          (org-roam-organize--cite-managed-identity-map-data
           tag 'citekey citekeys))
         (table (plist-get map-data :citekey-to-uuids))
         missing
         ambiguous
         uuids)
    (dolist (citekey citekeys)
      (let ((matches (gethash citekey table)))
        (cond
         ((null matches)
          (push citekey missing))
         ((cdr matches)
          (push (cons citekey matches) ambiguous))
         (t
          (push (car matches) uuids)))))
    (when missing
      (user-error
       "No managed node for citation record %S and citekey%s: %s"
       record-name
       (if (cdr missing) "s" "")
       (mapconcat #'identity (nreverse missing) ", ")))
    (when ambiguous
      (user-error
       "Citekey mapping is ambiguous: %s"
       (mapconcat
        (lambda (entry)
          (format "%s -> %s"
                  (car entry)
                  (mapconcat #'identity (cdr entry) ", ")))
        (nreverse ambiguous)
        "; ")))
    (nreverse uuids)))

(defun org-roam-organize-cite-citar--uuid-citekey-table (keys)
  "Return managed UUID-to-citekey candidates for KEYS.

Return an `equal'-tested hash table whose keys are managed literature UUIDs
present in KEYS and whose values are deduplicated external citekey lists in
database row order.  UUIDs without a managed citation ref are absent.  Signal
`user-error' when `org-roam-organize-mode' is disabled or the citation registry
record is invalid.  This function reads the Org-roam database and does not
modify KEYS, buffers, or files.

Implementation notes:
`org-roam-organize--cite-managed-identity-map-data' queries both directions
for KEYS and this function returns its UUID-to-citekey table.  Keeping every
candidate lets strict action translation reject ambiguity while activation
projection can conservatively omit an ambiguous alias.

Rationale: UUID lookup policy differs between interactive actions and passive
Font Lock activation, but both boundaries must derive mappings from the same
managed-node query."
  (org-roam-organize-cite-citar--ensure-mode)
  (let* ((tag (org-roam-organize-cite-citar--cite-record-tag))
         (map-data
          (org-roam-organize--cite-managed-identity-map-data
           tag 'uuid keys)))
    (plist-get map-data :uuid-to-citekeys)))

(defun org-roam-organize-cite-citar--uuids-to-citekeys (keys)
  "Replace managed UUIDs in KEYS with their external citekeys.

Return a list that preserves the order and multiplicity of KEYS.  Ordinary
non-UUID citation keys are returned unchanged.  Signal `user-error' when a
UUID-shaped key has no managed cite ref or when a managed UUID declares
multiple cite refs, or when `org-roam-organize-mode' is disabled.  The function
reads the Org-roam database and does not modify it or the current buffer.

Implementation notes:
`org-roam-organize-cite-citar--uuid-citekey-table' loads all managed
candidates in one database query.  This function then applies the strict
action policy while preserving ordinary citekeys for mixed citations.

Rationale: Citar actions operate on external bibliography keys, while source
Org citations retain stable Org-roam UUIDs.  Unmapped UUID-shaped keys fail
clearly instead of being passed to Citar as if they were external citekeys."
  (let* ((table (org-roam-organize-cite-citar--uuid-citekey-table keys))
         missing
         ambiguous
         citekeys)
    (dolist (key keys)
      (let ((matches (gethash key table)))
        (cond
         ((null matches)
          (if (string-match-p org-roam-organize-cite-citar--uuid-regexp key)
              (push key missing)
            (push key citekeys)))
         ((cdr matches)
          (push (cons key matches) ambiguous))
         (t
          (push (car matches) citekeys)))))
    (when missing
      (user-error
       "No external citekey for managed UUID%s: %s"
       (if (cdr missing) "s" "")
       (mapconcat #'identity (nreverse missing) ", ")))
    (when ambiguous
      (user-error
       "UUID mapping is ambiguous: %s"
       (mapconcat
        (lambda (entry)
          (format "%s -> %s"
                  (car entry)
                  (mapconcat #'identity (cdr entry) ", ")))
        (nreverse ambiguous)
        "; ")))
    (nreverse citekeys)))

(defun org-roam-organize-cite-citar--project-activation-entries (citation)
  "Return Citar entries extended for managed UUIDs in CITATION.

Return a copied hash table containing Citar's active bibliography entries plus
UUID aliases for unambiguous managed references in CITATION.  Each alias maps
to the entry belonging to the corresponding external citekey.  Return nil
when CITATION contains no UUID-shaped key or no alias can be resolved.  The
original Citar entries table and Org citation object are not modified.

Implementation notes: UUID candidates come from `org-cite-get-references'.
`org-roam-organize-cite-citar--uuid-citekey-table' restricts the database
query to those candidates.  `citar-get-entries' is copied lazily only after
both a single citekey mapping and its bibliography entry have been found.  No
projection is retained after activation, so later fontification observes
current Org-roam mappings and Citar entries.

Rationale: Citar's basic activation validates keys and formats tooltips through
its active entries table.  Temporary UUID aliases let that implementation
operate unchanged without presenting UUIDs as external keys to Citar actions,
file sources, link sources, or notes sources."
  (let (uuid-keys)
    (dolist (reference (org-cite-get-references citation))
      (let ((key (org-element-property :key reference)))
        (when (and (stringp key)
                   (string-match-p
                    org-roam-organize-cite-citar--uuid-regexp key))
          (push key uuid-keys))))
    (setq uuid-keys (delete-dups (nreverse uuid-keys)))
    (when uuid-keys
      (let* ((table
              (org-roam-organize-cite-citar--uuid-citekey-table uuid-keys))
             (entries (citar-get-entries))
             projected-entries)
        (when (hash-table-p entries)
          (dolist (uuid uuid-keys)
            (let ((citekeys (gethash uuid table)))
              (when (and citekeys (null (cdr citekeys)))
                (when-let* ((entry (gethash (car citekeys) entries)))
                  (unless projected-entries
                    (setq projected-entries (copy-hash-table entries)))
                  (puthash uuid entry projected-entries))))))
        projected-entries))))

(defun org-roam-organize-cite-citar--activate-with-projected-entries
    (function citation)
  "Call Citar activation FUNCTION with UUID aliases for CITATION.

When the Citar adapter and `org-roam-organize-mode' are active in an Org
buffer, dynamically bind `citar--entries' to a copied entry table containing
managed UUID aliases, then call FUNCTION with CITATION.  Otherwise call
FUNCTION unchanged.  Mapping or projection errors emit a warning and fall
back to unchanged Citar activation.  Return FUNCTION's value and call it
exactly once.  Do not modify source text or CITATION.

Implementation notes: This function is installed as `:around' advice on
`citar-org-cite-basic-activate'.  The dynamic binding follows Citar's
documented internal contract for `citar--entries'; both `citar-get-entries'
and the `citar-get-entry' path used by tooltip formatting observe the same
temporary projection.

Rationale: Passive Font Lock activation must degrade to Citar's ordinary
invalid-key presentation when Org-roam data is unavailable instead of
interrupting editing.  Restricting the projection to basic activation keeps
Citar's citation-level keymap and all non-activation identity boundaries
unchanged."
  (if (not (and org-roam-organize-mode
                org-roam-organize-cite-citar--installed-p
                (derived-mode-p 'org-mode)))
      (funcall function citation)
    (let ((entries
           (condition-case err
               (org-roam-organize-cite-citar--project-activation-entries
                citation)
             (error
              (message
               (concat
                "[WARNING] Org-roam Organize Citar activation aliases "
                "are unavailable: %s")
               (error-message-string err))
              nil))))
      (if entries
          (let ((citar--entries entries))
            (funcall function citation))
        (funcall function citation)))))

(defun org-roam-organize-cite-citar--filter-org-insert-args (args)
  "Return Citar Org insertion ARGS with citekeys replaced by UUIDs.

ARGS is the argument list accepted by `citar-org-insert-citation'.  Preserve
all arguments after its initial key list.  Signal `user-error' when
`org-roam-organize-mode' is disabled or when a key has no unambiguous managed
UUID mapping.  The function does not modify the current buffer.

Implementation notes: This function is installed as `:filter-args' advice on
`citar-org-insert-citation', after `citar-insert-citation' has selected
external citekeys but before Citar compares or inserts Org citation keys.

Rationale: Advising the Org-specific insertion boundary preserves Citar's
native command and avoids changing its LaTeX or Markdown behavior."
  (org-roam-organize-cite-citar--ensure-mode)
  (cons
   (org-roam-organize-cite-citar--citekeys-to-uuids (car args))
   (cdr args)))

(defun org-roam-organize-cite-citar--filter-selected-key (result)
  "Return Citar Org selection RESULT with citekeys replaced by UUIDs.

RESULT may be a single citekey string, a citekey list, or nil, matching the
contract of `citar-org-select-key'.  Preserve that return shape.  Signal
`user-error' when `org-roam-organize-mode' is disabled, when RESULT has an
unexpected type, or when a key has no unambiguous managed UUID mapping.

Implementation notes: This function is installed as `:filter-return' advice
on `citar-org-select-key', which is the selection boundary used when
`org-cite-insert' delegates to the Citar insert processor.

Rationale: The Org Cite processor does not call
`citar-org-insert-citation', so its selected keys require a separate adapter
boundary without advising Citar's general selection functions."
  (org-roam-organize-cite-citar--ensure-mode)
  (cond
   ((null result)
    nil)
   ((listp result)
    (org-roam-organize-cite-citar--citekeys-to-uuids result))
   ((stringp result)
    (car (org-roam-organize-cite-citar--citekeys-to-uuids (list result))))
   (t
    (user-error "Unexpected Citar Org selection result: %S" result))))

(defun org-roam-organize-cite-citar--org-cite-keys-at-point ()
  "Return Org Cite keys at point, or nil when point has no citation.

Return a one-element list for a `citation-reference' context and every key in
source order for a `citation' context.  Return nil outside an Org-derived mode.
This function reads Org's element tree without modifying the buffer or point.

Implementation notes: `org-element-context' identifies the citation boundary,
and `org-element-map' extracts `:key' from its citation references.

Rationale: Managed UUIDs are intentionally absent from Citar bibliographies,
so Citar's at-point helpers may reject them before this adapter can translate
them to external citekeys."
  (when (derived-mode-p 'org-mode)
    (let ((context (org-element-context)))
      (pcase (org-element-type context)
        ('citation-reference
         (list (org-element-property :key context)))
        ('citation
         (org-element-map context 'citation-reference
           (lambda (reference)
             (org-element-property :key reference))))))))

(defun org-roam-organize-cite-citar--dwim ()
  "Run Citar's default action for the citation at point.

Invoke this command with point on a citation supported by Citar.  Managed UUID
keys are translated to external citekeys, while ordinary non-UUID keys remain
unchanged.  Signal `user-error' when point has no citation, when a UUID has no
managed cite ref, when its mapping is ambiguous, or when
`org-roam-organize-mode' is disabled.  The command does not edit the citation,
but the configured Citar action may change buffers or external state.

Implementation notes: The command mirrors `citar-dwim' by preferring
`citar-key-at-point' over `citar-citation-at-point', then falls back to Org's
element tree when Citar rejects managed UUID keys.  It normalizes the result
to a list, resolves UUIDs with
`org-roam-organize-cite-citar--uuids-to-citekeys', and passes the translated
list to `citar-run-default-action'.

Rationale: Translation at the action boundary lets source Org files retain
stable Org-roam UUIDs without reimplementing Citar's action system."
  (interactive)
  (org-roam-organize-cite-citar--ensure-mode)
  (if-let* ((keys (or (citar-key-at-point)
                      (citar-citation-at-point)
                      (org-roam-organize-cite-citar--org-cite-keys-at-point))))
      (let* ((keys (if (listp keys) keys (list keys)))
             (citekeys
              (org-roam-organize-cite-citar--uuids-to-citekeys keys)))
        (citar-run-default-action citekeys))
    (user-error "No citation keys found")))

(defun org-roam-organize-cite-citar--setup ()
  "Install UUID and notes integration for Citar.

Require `org-roam-organize-mode' to be enabled.  Install insertion advice for
both `citar-insert-citation' in Org buffers and the Citar processor used by
`org-cite-insert'.  Install activation advice that exposes managed UUIDs as
temporary Citar entry aliases.  Register and select the managed Citar notes
source, and set the default value of `citar-at-point-function' to
`org-roam-organize-cite-citar--dwim'.  Repeated calls are idempotent and return
non-nil after successful installation.  Signal `user-error'
when Citar or its Org integration cannot be loaded, when no valid citation
registry record is configured, when its Citar backend options are invalid,
when a required runtime capability is unavailable, or when the adapter's notes
source name is already registered.

Implementation notes: The function validates the managed citation record
before loading Citar, then checks
`org-roam-organize-cite-citar--capability-alist' after loading `citar' and
`citar-org'.  A fresh installation saves Citar's notes source and at-point
function before registering `org-roam-organize-cite-citar--notes-config'.  It
advises `citar-org-insert-citation' with
`org-roam-organize-cite-citar--filter-org-insert-args' and
`citar-org-select-key' with
`org-roam-organize-cite-citar--filter-selected-key'.  It advises
`citar-org-cite-basic-activate' with
`org-roam-organize-cite-citar--activate-with-projected-entries'.  Failed
installation removes any advice and notes source added during the attempt and
restores all saved values.

Rationale: Explicit installation during Org-roam Organize mode setup provides
a deterministic lifecycle without deferred `with-eval-after-load' callbacks."
  (org-roam-organize-cite-citar--ensure-mode)
  ;; Reject invalid managed citation configuration before loading optional
  ;; dependencies or changing any Citar global state.
  (org-roam-organize-cite-citar--cite-record-tag)
  (org-roam-organize-cite-citar--validate-backend-options
   (org-roam-organize-cite-citar--cite-record))
  (unless (require 'citar nil t)
    (user-error
     "Citar is required by the Org-roam Organize Citar adapter"))
  (unless (require 'citar-org nil t)
    (user-error
     (concat "Citar Org integration is required by the "
             "Org-roam Organize Citar adapter")))
  ;; Capability validation is the portable compatibility boundary.  Citar has
  ;; no runtime version API that works across package.el and Nix installations.
  (let ((result
         (org-roam-organize--check-capabilities
          org-roam-organize-cite-citar--capability-alist)))
    (unless (car result)
      (user-error
       "Citar adapter capability check failed (minimum tested version %s): %s"
       org-roam-organize-cite-citar--minimum-tested-version
       (cdr result))))
  (unless org-roam-organize-cite-citar--installed-p
    (when (assq org-roam-organize-cite-citar--notes-source
                citar-notes-sources)
      (user-error
       "Citar notes source is already registered: %s"
       org-roam-organize-cite-citar--notes-source))
    ;; Save ownership state before changing Citar so failure cleanup can
    ;; restore it without leaving a partially active adapter.
    (setq org-roam-organize-cite-citar--previous-at-point-function
          (default-value 'citar-at-point-function))
    (setq org-roam-organize-cite-citar--previous-notes-source
          citar-notes-source)
    (let (notes-source-registered)
      (condition-case err
          (progn
            (citar-register-notes-source
             org-roam-organize-cite-citar--notes-source
             org-roam-organize-cite-citar--notes-config)
            (setq notes-source-registered t)
            (advice-add
             'citar-org-insert-citation
             :filter-args
             #'org-roam-organize-cite-citar--filter-org-insert-args)
            (advice-add
             'citar-org-select-key
             :filter-return
             #'org-roam-organize-cite-citar--filter-selected-key)
            (advice-add
             'citar-org-cite-basic-activate
             :around
             #'org-roam-organize-cite-citar--activate-with-projected-entries)
            (set-default 'citar-at-point-function
                         #'org-roam-organize-cite-citar--dwim)
            (setq citar-notes-source
                  org-roam-organize-cite-citar--notes-source)
            (setq org-roam-organize-cite-citar--installed-p t))
        (error
         (advice-remove
          'citar-org-insert-citation
          #'org-roam-organize-cite-citar--filter-org-insert-args)
         (advice-remove
          'citar-org-select-key
          #'org-roam-organize-cite-citar--filter-selected-key)
         (advice-remove
          'citar-org-cite-basic-activate
          #'org-roam-organize-cite-citar--activate-with-projected-entries)
         (when notes-source-registered
           (citar-remove-notes-source
            org-roam-organize-cite-citar--notes-source))
         (setq citar-notes-source
               org-roam-organize-cite-citar--previous-notes-source)
         (set-default 'citar-at-point-function
                      org-roam-organize-cite-citar--previous-at-point-function)
         (setq org-roam-organize-cite-citar--previous-notes-source nil)
         (setq org-roam-organize-cite-citar--previous-at-point-function nil)
         (signal (car err) (cdr err))))))
  t)

(defun org-roam-organize-cite-citar--teardown ()
  "Remove UUID and notes integration from Citar.

Remove the insertion and activation advice functions installed by
`org-roam-organize-cite-citar--setup'.  Remove the managed notes source and
restore the saved `citar-notes-source' only while the registered source still
has this adapter's configuration.  Restore the saved default value of
`citar-at-point-function' only when it still names
`org-roam-organize-cite-citar--dwim'; preserve a value changed by the user
while the adapter was active.  Return nil after teardown.  This function
intentionally works while `org-roam-organize-mode' is disabled.

Implementation notes: Advice removal is safe when an advice is already absent.
The installation flag distinguishes saved values from an adapter that was
never installed.  Notes-source ownership is checked before restoration so a
later replacement is preserved.

Rationale: Mode teardown must be able to undo global Citar integration after
the mode flag has already changed, while avoiding overwriting newer user
configuration."
  (when org-roam-organize-cite-citar--installed-p
    (advice-remove
     'citar-org-insert-citation
     #'org-roam-organize-cite-citar--filter-org-insert-args)
    (advice-remove
     'citar-org-select-key
     #'org-roam-organize-cite-citar--filter-selected-key)
    (advice-remove
     'citar-org-cite-basic-activate
     #'org-roam-organize-cite-citar--activate-with-projected-entries)
    ;; Restore only the value installed by this adapter.  A different current
    ;; value belongs to the user or another integration.
    (when (eq (default-value 'citar-at-point-function)
              #'org-roam-organize-cite-citar--dwim)
      (set-default 'citar-at-point-function
                   org-roam-organize-cite-citar--previous-at-point-function))
    (when (org-roam-organize-cite-citar--notes-source-owned-p)
      (when (eq citar-notes-source
                org-roam-organize-cite-citar--notes-source)
        (setq citar-notes-source
              org-roam-organize-cite-citar--previous-notes-source))
      (citar-remove-notes-source
       org-roam-organize-cite-citar--notes-source))
    (setq org-roam-organize-cite-citar--installed-p nil)
    (setq org-roam-organize-cite-citar--previous-notes-source nil)
    (setq org-roam-organize-cite-citar--previous-at-point-function nil))
  nil)

(provide 'org-roam-organize-cite-citar)

;;; org-roam-organize-cite-citar.el ends here
