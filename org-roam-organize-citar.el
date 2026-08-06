;;; org-roam-organize-citar.el --- Citar adapter for Org-roam Organize -*- lexical-binding: t; -*-

;;; Commentary:

;; This optional adapter lets Citar select and act on bibliography citekeys
;; while Org files continue to store managed literature node UUIDs as Org Cite
;; keys.  Loading this library does not load Citar; adapter setup loads Citar
;; only when the Citar backend is enabled.

;;; Code:

(require 'rx)
(require 'org-roam-organize)

(declare-function citar-key-at-point "citar" ())
(declare-function citar-citation-at-point "citar" ())
(declare-function citar-run-default-action "citar" (citekeys))
(declare-function citar-register-notes-source "citar" (name config))
(declare-function citar-remove-notes-source "citar" (name))
(declare-function citar-create-note "citar" (key &optional entry))
(declare-function citar-format--entry
                  "citar-format" (format entry &optional width &rest options))
(declare-function org-roam-node-from-id "org-roam-node" (id))
(declare-function org-roam-node-visit
                  "org-roam-node" (node &optional other-window force))
(declare-function org-roam-ref-add "org-roam-node" (ref))
(declare-function org-roam-db-update-file
                  "org-roam-db" (&optional file-path deprecated-arg))

(defvar citar-notes-source)
(defvar citar-notes-sources)

(defconst org-roam-organize-citar--minimum-tested-version "1.4.0"
  "The value records the minimum tested Citar version.

This value documents the compatibility baseline used by maintainers.  Setup
does not compare installed package versions because Citar does not expose a
portable runtime version API; actual compatibility is validated through
`org-roam-organize-citar--capability-alist'.")

(defconst org-roam-organize-citar--capability-alist
  '((citar-at-point-function . variable)
    (citar-notes-source . variable)
    (citar-notes-sources . variable)
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
    (org-roam-node-from-id . function)
    (org-roam-node-visit . function)
    (org-roam-ref-add . function)
    (org-roam-db-update-file . function))
  "The alist describes runtime capabilities expected by the Citar adapter.

Each entry maps a Citar symbol to the capability type accepted by
`org-roam-organize--check-capabilities'.  Setup checks the table only after
loading `citar' and `citar-org'.  It includes the functions called or advised
by the adapter and the public Citar boundaries whose behavior the adapter is
intended to preserve.")

(defconst org-roam-organize-citar--uuid-regexp
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

(defconst org-roam-organize-citar--default-title-format "${title}"
  "The Citar format used for node titles when no backend title is configured.")

(defconst org-roam-organize-citar--notes-source
  'org-roam-organize-citar
  "The symbol identifies Org-roam Organize's Citar notes source.

Setup will reject an existing source with this name instead of replacing
configuration owned by another package or an earlier incomplete installation.")

(defconst org-roam-organize-citar--notes-config
  (list :name "Org-roam Organize Notes"
        :category 'org-roam-node
        :items 'org-roam-organize-citar--get-notes
        :hasitems 'org-roam-organize-citar--has-notes
        :open 'org-roam-organize-citar--open-note
        :create 'org-roam-organize-citar--create-note)
  "The plist describes Org-roam Organize's Citar notes source.

The callbacks use managed node UUIDs as Citar note identifiers.  The `:create'
callback is implemented with the node-creation stage of the adapter; source
registration occurs only after every callback and capability is available.

Rationale: A formal notes source preserves Citar's note selection and action
pipeline while keeping UUID-to-citekey translation inside the adapter.")

(defvar org-roam-organize-citar--installed-p nil
  "The value is non-nil when the complete Citar adapter is installed.")

(defvar org-roam-organize-citar--previous-at-point-function nil
  "The value stores Citar's default at-point function before installation.

Teardown restores this value only while the adapter still owns Citar's current
default, so a later user change is preserved.")

(defvar org-roam-organize-citar--previous-notes-source nil
  "The value stores Citar's notes source before adapter installation.

Teardown restores this value only while the adapter still owns both its
registered source configuration and `citar-notes-source'.")

(defun org-roam-organize-citar--unique-values (values)
  "Return VALUES without duplicates while preserving their order.

The returned list is a copy, and VALUES is not modified.  Equality follows the
`delete-dups' comparison semantics."
  (delete-dups (copy-sequence values)))

(defun org-roam-organize-citar--notes-source-owned-p ()
  "Return non-nil when Citar retains this adapter's notes source config.

Compare the registered plist for `org-roam-organize-citar--notes-source' with
`org-roam-organize-citar--notes-config'.  Return nil when Citar is not loaded,
the source is absent, or another value now owns that source name.  This
function does not modify Citar state.

Rationale: Teardown should undo configuration installed by this adapter without
removing a later replacement that happens to reuse the same symbol."
  (and (boundp 'citar-notes-sources)
       (equal
        (cdr (assq org-roam-organize-citar--notes-source
                   citar-notes-sources))
        org-roam-organize-citar--notes-config)))

(defun org-roam-organize-citar--ensure-mode ()
  "Require Org-roam Organize mode for Citar adapter operations.

Signal `user-error' when `org-roam-organize-mode' is nil.  Return non-nil when
the mode is enabled.

Rationale: Advice functions and at-point commands can be invoked through Citar
instead of the core mode lifecycle, so each stateful operation must enforce the
package mode boundary itself."
  (unless org-roam-organize-mode
    (user-error "Org-roam Organize mode must be enabled"))
  t)

(defun org-roam-organize-citar--cite-record ()
  "Return the configured citation registry record.

Signal `user-error' unless exactly one `:cite t' record is configured.  Require
`org-roam-organize-mode' to be enabled.

Implementation notes: The function uses
`org-roam-organize--registry-cite-records' to enforce the same registry
selection boundary as core citation synchronization and export mapping.

Rationale: Keeping record selection in one helper lets adapter queries and node
creation share the same registry identity instead of independently selecting a
tag and capture template."
  (org-roam-organize-citar--ensure-mode)
  (let ((records (org-roam-organize--registry-cite-records)))
    (cond
     ((null records)
      (user-error "No :cite t registry record is configured"))
     ((cdr records)
      (user-error "Multiple :cite t registry records are configured"))
     (t
      (car records)))))

(defun org-roam-organize-citar--cite-record-tag ()
  "Return the tag of the configured citation registry record.

Signal `user-error' unless exactly one `:cite t' record with a string tag is
configured.  Require `org-roam-organize-mode' to be enabled.

Implementation notes: Record selection is delegated to
`org-roam-organize-citar--cite-record' so creation and database queries use the
same citation record boundary."
  (let ((tag
         (org-roam-organize--record-tag
          (org-roam-organize-citar--cite-record))))
    (if (stringp tag)
        tag
      (user-error "The :cite t registry record has no valid tag"))))

(defun org-roam-organize-citar--get-notes (&optional citekeys)
  "Return managed Org-roam note identifiers for CITEKEYS.

Return a hash table mapping each external citekey to a list of managed
literature node UUIDs.  When CITEKEYS is nil, include every managed citekey;
otherwise include only matching keys.  Duplicate database rows are removed
without discarding distinct nodes for an ambiguous citekey.  Signal
`user-error' when `org-roam-organize-mode' is disabled or the citation registry
record is invalid.  This function reads the Org-roam database and does not
modify buffers or files.

Implementation notes: One `org-roam-db-query' joins cite `refs', the citation
record's `tags', and level-0 `nodes'.  UUID lists preserve database row order
after duplicate removal.

Rationale: Citar's `:items' callback must represent missing and multiple notes
instead of enforcing the stricter single-result contract used when inserting a
citation."
  (org-roam-organize-citar--ensure-mode)
  (let* ((tag (org-roam-organize-citar--cite-record-tag))
         (query
          `[:select [r:ref r:node_id]
            :from (as refs r)
            :join (as tags t)
            :on (= t:node_id r:node_id)
            :join (as nodes n)
            :on (and (= n:id r:node_id) (= n:level 0))
            :where (and (= r:type "cite")
                        (= t:tag $s1)
                        ,@(when citekeys
                            '((in r:ref $v2))))])
         (rows
          (if citekeys
              (org-roam-db-query query tag (vconcat citekeys))
            (org-roam-db-query query tag)))
         (notes (make-hash-table :test 'equal)))
    (dolist (row rows)
      (let* ((citekey (nth 0 row))
             (uuid (nth 1 row))
             (uuids (gethash citekey notes)))
        (unless (member uuid uuids)
          (puthash citekey (cons uuid uuids) notes))))
    (maphash
     (lambda (citekey uuids)
       (puthash citekey (nreverse uuids) notes))
     notes)
    notes))

(defun org-roam-organize-citar--has-notes ()
  "Return a predicate that tests whether a citekey has managed notes.

Return nil when no managed citation nodes exist.  Otherwise return a function
of one CITEKEY that is non-nil exactly when the database snapshot taken by this
call contains at least one corresponding node.  Signal `user-error' under the
same invalid mode or registry conditions as
`org-roam-organize-citar--get-notes'.

Implementation notes: The function loads all notes once and closes over their
hash table so Citar can test many bibliography entries without issuing one
database query per entry.

Rationale: This matches Citar's `:hasitems' callback contract rather than
mistaking it for a predicate called separately for each citekey."
  (let ((notes (org-roam-organize-citar--get-notes)))
    (unless (= (hash-table-count notes) 0)
      (lambda (citekey)
        (and (gethash citekey notes) t)))))

(defun org-roam-organize-citar--open-note (uuid)
  "Visit the managed Org-roam node identified by UUID.

UUID is the note identifier previously returned by
`org-roam-organize-citar--get-notes'.  Signal `user-error' when
`org-roam-organize-mode' is disabled, UUID is not a string, or no current
Org-roam database node has that ID.  Return the value of
`org-roam-node-visit'; visiting may change the selected buffer and window.

Implementation notes: Resolve the current node with `org-roam-node-from-id'
immediately before visiting it instead of retaining file paths or database
positions in Citar candidates.

Rationale: Org-roam owns node locations, while the stable UUID is sufficient
for Citar's note selection boundary."
  (org-roam-organize-citar--ensure-mode)
  (unless (stringp uuid)
    (user-error "Citar note ID must be a node UUID string"))
  (if-let* ((node (org-roam-node-from-id uuid)))
      (org-roam-node-visit node)
    (user-error "No Org-roam node for Citar note ID: %s" uuid)))

(defun org-roam-organize-citar--validate-info-formats (formats)
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

(defun org-roam-organize-citar--validate-backend-options (record)
  "Validate the Citar backend options in registry RECORD and return non-nil.

Accept only unique `:title' and `:info' keys.  `:title', when present, must be
a string.  `:info' is validated by
`org-roam-organize-citar--validate-info-formats'.  A symbol backend has no
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
           (org-roam-organize-citar--validate-info-formats value)))))
    t))

(defun org-roam-organize-citar--creation-request (record citekey entry)
  "Return a managed capture request for RECORD, CITEKEY, and Citar ENTRY.

Interpret RECORD's Citar backend `:title' and `:info' values as Citar format
strings.  Return a plist containing the formatted `:title' and `:info'.  Use
`org-roam-organize-citar--default-title-format' when `:title' is absent, and
fall back to CITEKEY when the formatted title is blank.  Preserve configured
empty info strings so Org-roam does not prompt for those placeholders.

Signal `user-error' when the backend options are invalid or Citar returns a
non-string formatted value.  This function does not query the bibliography,
start capture, or modify ENTRY.

Rationale: Citar owns bibliography parsing and interpolation, while the record
declares how formatted strings map onto Org-roam capture information."
  (org-roam-organize-citar--validate-backend-options record)
  (let* ((options (org-roam-organize--record-backend-options record))
         (title-format
          (if (plist-member options :title)
              (plist-get options :title)
            org-roam-organize-citar--default-title-format))
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

(defun org-roam-organize-citar--store-cite-ref (citekey)
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

(defun org-roam-organize-citar--create-note (citekey entry)
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

Implementation notes: `org-roam-organize-citar--get-notes' performs the
preflight lookup.  Creation delegates to `org-roam-organize--capture-node' with
a lexical success callback that calls
`org-roam-organize-citar--store-cite-ref'.

Rationale: Citar owns bibliography selection, while Org-roam Organize owns the
managed node layout and the cite ref needed by its UUID citation model."
  (org-roam-organize-citar--ensure-mode)
  (unless (and (stringp citekey)
               (not (org-roam-organize--blank-string-p citekey)))
    (user-error "Citar citekey cannot be empty"))
  (let* ((record (org-roam-organize-citar--cite-record))
         (record-name (org-roam-organize--record-name record))
         (matches
          (gethash citekey
                   (org-roam-organize-citar--get-notes (list citekey)))))
    (cond
     ((null matches)
      (let ((template
             (org-roam-organize--record-node-capture-template record))
            (request
             (org-roam-organize-citar--creation-request
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
           (org-roam-organize-citar--store-cite-ref citekey)))))
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

(defun org-roam-organize-citar--citekeys-to-uuids (citekeys)
  "Return managed citation-record node UUIDs corresponding to CITEKEYS.

The returned UUID list preserves the order and multiplicity of CITEKEYS.
Signal `user-error' identifying the citation record by its configured `:name'
when no managed node declares a citekey.  Also signal `user-error' when more
than one managed node declares a citekey or when `org-roam-organize-mode' is
disabled.  The function reads the Org-roam database and does not modify it or
the current buffer.

Implementation notes: One `org-roam-db-query' joins `refs', `tags', and
level-0 `nodes' for the configured citation record tag.  An in-memory table
then restores input order and detects missing or ambiguous reverse mappings.

Rationale: Citar selects external citekeys, but Org-roam Organize stores UUIDs
in Org citations.  Reverse mapping must reject duplicate citekeys because
silently choosing a node would make insertion nondeterministic."
  (org-roam-organize-citar--ensure-mode)
  (let* ((record (org-roam-organize-citar--cite-record))
         (record-name (org-roam-organize--record-name record))
         (tag (org-roam-organize-citar--cite-record-tag))
         (rows
          (when citekeys
            (org-roam-db-query
             (vector :select (vector 'r:ref 'r:node_id)
                     :from '(as refs r)
                     :join '(as tags t)
                     :on '(= t:node_id r:node_id)
                     :join '(as nodes n)
                     :on '(and (= n:id r:node_id) (= n:level 0))
                     :where '(and (= r:type "cite")
                                  (= t:tag $s1)
                                  (in r:ref $v2)))
             tag
             (vconcat citekeys))))
         (table (make-hash-table :test 'equal))
         missing
         ambiguous
         uuids)
    (dolist (row rows)
      (let ((citekey (nth 0 row))
            (uuid (nth 1 row)))
        (puthash citekey
                 (cons uuid (gethash citekey table))
                 table)))
    (dolist (citekey citekeys)
      (let ((matches
             (org-roam-organize-citar--unique-values
              (nreverse (gethash citekey table)))))
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

(defun org-roam-organize-citar--uuids-to-citekeys (keys)
  "Replace managed UUIDs in KEYS with their external citekeys.

Return a list that preserves the order and multiplicity of KEYS.  Ordinary
non-UUID citation keys are returned unchanged.  Signal `user-error' when a
UUID-shaped key has no managed cite ref or when a managed UUID declares
multiple cite refs, or when `org-roam-organize-mode' is disabled.  The function
reads the Org-roam database and does not modify it or the current buffer.

Implementation notes: One `org-roam-db-query' joins `refs', `tags', and
level-0 `nodes' for the configured citation record tag.  An in-memory table
then replaces mapped UUIDs while preserving ordinary citekeys for mixed
citations.

Rationale: Citar actions operate on external bibliography keys, while source
Org citations retain stable Org-roam UUIDs.  Unmapped UUID-shaped keys fail
clearly instead of being passed to Citar as if they were external citekeys."
  (org-roam-organize-citar--ensure-mode)
  (let* ((tag (org-roam-organize-citar--cite-record-tag))
         (rows
          (when keys
            (org-roam-db-query
             (vector :select (vector 'r:node_id 'r:ref)
                     :from '(as refs r)
                     :join '(as tags t)
                     :on '(= t:node_id r:node_id)
                     :join '(as nodes n)
                     :on '(and (= n:id r:node_id) (= n:level 0))
                     :where '(and (= r:type "cite")
                                  (= t:tag $s1)
                                  (in r:node_id $v2)))
             tag
             (vconcat keys))))
         (table (make-hash-table :test 'equal))
         missing
         ambiguous
         citekeys)
    (dolist (row rows)
      (let ((uuid (nth 0 row))
            (citekey (nth 1 row)))
        (puthash uuid
                 (cons citekey (gethash uuid table))
                 table)))
    (dolist (key keys)
      (let ((matches
             (org-roam-organize-citar--unique-values
              (nreverse (gethash key table)))))
        (cond
         ((null matches)
          (if (string-match-p org-roam-organize-citar--uuid-regexp key)
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

(defun org-roam-organize-citar--filter-org-insert-args (args)
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
  (org-roam-organize-citar--ensure-mode)
  (cons
   (org-roam-organize-citar--citekeys-to-uuids (car args))
   (cdr args)))

(defun org-roam-organize-citar--filter-selected-key (result)
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
  (org-roam-organize-citar--ensure-mode)
  (cond
   ((null result)
    nil)
   ((listp result)
    (org-roam-organize-citar--citekeys-to-uuids result))
   ((stringp result)
    (car (org-roam-organize-citar--citekeys-to-uuids (list result))))
   (t
    (user-error "Unexpected Citar Org selection result: %S" result))))

;;;###autoload
(defun org-roam-organize-citar-dwim ()
  "Run Citar's default action for the citation at point.

Invoke this command with point on a citation supported by Citar.  Managed UUID
keys are translated to external citekeys, while ordinary non-UUID keys remain
unchanged.  Signal `user-error' when point has no citation, when a UUID has no
managed cite ref, when its mapping is ambiguous, or when
`org-roam-organize-mode' is disabled.  The command does not edit the citation,
but the configured Citar action may change buffers or external state.

Implementation notes: The command mirrors `citar-dwim' by preferring
`citar-key-at-point' over `citar-citation-at-point'.  It normalizes the result
to a list, resolves UUIDs with
`org-roam-organize-citar--uuids-to-citekeys', and passes the translated list to
`citar-run-default-action'.

Rationale: Translation at the action boundary lets source Org files retain
stable Org-roam UUIDs without reimplementing Citar's action system."
  (interactive)
  (org-roam-organize-citar--ensure-mode)
  (if-let* ((keys (or (citar-key-at-point)
                      (citar-citation-at-point))))
      (let* ((keys (if (listp keys) keys (list keys)))
             (citekeys
              (org-roam-organize-citar--uuids-to-citekeys keys)))
        (citar-run-default-action citekeys))
    (user-error "No citation keys found")))

(defun org-roam-organize-citar-setup ()
  "Install UUID translation and managed notes integration for Citar.

Require `org-roam-organize-mode' to be enabled.  Install insertion advice for
both `citar-insert-citation' in Org buffers and the Citar processor used by
`org-cite-insert'.  Register and select the managed Citar notes source, and set
the default value of `citar-at-point-function' to
`org-roam-organize-citar-dwim'.  Repeated calls are idempotent and return
non-nil after successful installation.  Signal `user-error' when Citar or its
Org integration cannot be loaded, when no valid citation registry record is
configured, when its Citar backend options are invalid, when a required runtime
capability is unavailable, or when the adapter's notes source name is already
registered.

Implementation notes: The function validates the managed citation record
before loading Citar, then checks
`org-roam-organize-citar--capability-alist' after loading `citar' and
`citar-org'.  A fresh installation saves Citar's notes source and at-point
function before registering `org-roam-organize-citar--notes-config'.  It
advises `citar-org-insert-citation' with
`org-roam-organize-citar--filter-org-insert-args' and
`citar-org-select-key' with
`org-roam-organize-citar--filter-selected-key'.  Failed installation removes
any advice and notes source added during the attempt and restores both saved
values.

Rationale: Explicit installation during Org-roam Organize mode setup provides
a deterministic lifecycle without deferred `with-eval-after-load' callbacks."
  (org-roam-organize-citar--ensure-mode)
  ;; Reject invalid managed citation configuration before loading optional
  ;; dependencies or changing any Citar global state.
  (org-roam-organize-citar--cite-record-tag)
  (org-roam-organize-citar--validate-backend-options
   (org-roam-organize-citar--cite-record))
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
          org-roam-organize-citar--capability-alist)))
    (unless (car result)
      (user-error
       "Citar adapter capability check failed (minimum tested version %s): %s"
       org-roam-organize-citar--minimum-tested-version
       (cdr result))))
  (unless org-roam-organize-citar--installed-p
    (when (assq org-roam-organize-citar--notes-source
                citar-notes-sources)
      (user-error
       "Citar notes source is already registered: %s"
       org-roam-organize-citar--notes-source))
    ;; Save ownership state before changing Citar so failure cleanup can
    ;; restore it without leaving a partially active adapter.
    (setq org-roam-organize-citar--previous-at-point-function
          (default-value 'citar-at-point-function))
    (setq org-roam-organize-citar--previous-notes-source
          citar-notes-source)
    (let (notes-source-registered)
      (condition-case err
          (progn
            (citar-register-notes-source
             org-roam-organize-citar--notes-source
             org-roam-organize-citar--notes-config)
            (setq notes-source-registered t)
            (advice-add
             'citar-org-insert-citation
             :filter-args
             #'org-roam-organize-citar--filter-org-insert-args)
            (advice-add
             'citar-org-select-key
             :filter-return
             #'org-roam-organize-citar--filter-selected-key)
            (set-default 'citar-at-point-function
                         #'org-roam-organize-citar-dwim)
            (setq citar-notes-source
                  org-roam-organize-citar--notes-source)
            (setq org-roam-organize-citar--installed-p t))
        (error
         (advice-remove
          'citar-org-insert-citation
          #'org-roam-organize-citar--filter-org-insert-args)
         (advice-remove
          'citar-org-select-key
          #'org-roam-organize-citar--filter-selected-key)
         (when notes-source-registered
           (citar-remove-notes-source
            org-roam-organize-citar--notes-source))
         (setq citar-notes-source
               org-roam-organize-citar--previous-notes-source)
         (set-default 'citar-at-point-function
                      org-roam-organize-citar--previous-at-point-function)
         (setq org-roam-organize-citar--previous-notes-source nil)
         (setq org-roam-organize-citar--previous-at-point-function nil)
         (signal (car err) (cdr err))))))
  t)

(defun org-roam-organize-citar-teardown ()
  "Remove UUID translation and managed notes integration from Citar.

Remove both insertion advice functions installed by
`org-roam-organize-citar-setup'.  Remove the managed notes source and restore
the saved `citar-notes-source' only while the registered source still has this
adapter's configuration.  Restore the saved default value of
`citar-at-point-function' only when it still names
`org-roam-organize-citar-dwim'; preserve a value changed by the user while the
adapter was active.  Return nil after teardown.  This function intentionally
works while `org-roam-organize-mode' is disabled.

Implementation notes: Advice removal is safe when an advice is already absent.
The installation flag distinguishes previously nil values from an adapter that
was never installed.  Notes-source ownership is checked before restoring or
removing it so a later replacement under the same symbol is preserved.

Rationale: Mode teardown must be able to undo global Citar integration after
the mode flag has already changed, while avoiding overwriting newer user
configuration."
  (when org-roam-organize-citar--installed-p
    (advice-remove
     'citar-org-insert-citation
     #'org-roam-organize-citar--filter-org-insert-args)
    (advice-remove
     'citar-org-select-key
     #'org-roam-organize-citar--filter-selected-key)
    ;; Restore only the value installed by this adapter.  A different current
    ;; value belongs to the user or another integration.
    (when (eq (default-value 'citar-at-point-function)
              #'org-roam-organize-citar-dwim)
      (set-default 'citar-at-point-function
                   org-roam-organize-citar--previous-at-point-function))
    (when (org-roam-organize-citar--notes-source-owned-p)
      (when (eq citar-notes-source
                org-roam-organize-citar--notes-source)
        (setq citar-notes-source
              org-roam-organize-citar--previous-notes-source))
      (citar-remove-notes-source
       org-roam-organize-citar--notes-source))
    (setq org-roam-organize-citar--installed-p nil)
    (setq org-roam-organize-citar--previous-notes-source nil)
    (setq org-roam-organize-citar--previous-at-point-function nil))
  nil)

(provide 'org-roam-organize-citar)

;;; org-roam-organize-citar.el ends here
