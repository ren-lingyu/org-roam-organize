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

(defconst org-roam-organize-citar--minimum-tested-version "1.4.0"
  "Minimum Citar version against which this adapter is tested.")

(defconst org-roam-organize-citar--capability-alist
  '((citar-at-point-function . variable)
    (citar-key-at-point . function)
    (citar-citation-at-point . function)
    (citar-run-default-action . function)
    (citar-dwim . function)
    (citar-insert-citation . function)
    (citar-org-insert-citation . function)
    (citar-org-select-key . function)
    (citar-org-follow . function))
  "Runtime capabilities required or expected by the Citar adapter.")

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

(defvar org-roam-organize-citar--installed-p nil
  "Non-nil when the Citar adapter is installed.")

(defvar org-roam-organize-citar--previous-at-point-function nil
  "Default Citar at-point function saved before adapter installation.")

(defun org-roam-organize-citar--unique-values (values)
  "Return VALUES without duplicates while preserving their order.

The returned list is a copy, and VALUES is not modified.  Equality follows the
`delete-dups' comparison semantics."
  (delete-dups (copy-sequence values)))

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

(defun org-roam-organize-citar--cite-record-tag ()
  "Return the tag of the configured citation registry record.

Signal `user-error' unless exactly one `:cite t' record with a string tag is
configured.

Implementation notes: The function uses
`org-roam-organize--registry-cite-records' to enforce the same registry
selection boundary as core citation synchronization and export mapping.

Rationale: Adapter queries must be limited to managed literature nodes rather
than every Org-roam node that happens to declare a cite ref."
  (org-roam-organize-citar--ensure-mode)
  (let ((records (org-roam-organize--registry-cite-records)))
    (cond
     ((null records)
      (user-error "No :cite t registry record is configured"))
     ((cdr records)
      (user-error "Multiple :cite t registry records are configured"))
     (t
      (let ((tag (org-roam-organize--record-tag (car records))))
        (if (stringp tag)
            tag
          (user-error "The :cite t registry record has no valid tag")))))))

(defun org-roam-organize-citar--citekeys-to-uuids (citekeys)
  "Return managed literature node UUIDs corresponding to CITEKEYS.

The returned UUID list preserves the order and multiplicity of CITEKEYS.
Signal `user-error' when no managed literature node declares a citekey or when
more than one managed node declares it, or when `org-roam-organize-mode' is
disabled.  The function reads the Org-roam database and does not modify it or
the current buffer.

Implementation notes: One `org-roam-db-query' joins `refs', `tags', and
level-0 `nodes' for the configured citation record tag.  An in-memory table
then restores input order and detects missing or ambiguous reverse mappings.

Rationale: Citar selects external citekeys, but Org-roam Organize stores UUIDs
in Org citations.  Reverse mapping must reject duplicate citekeys because
silently choosing a node would make insertion nondeterministic."
  (org-roam-organize-citar--ensure-mode)
  (let* ((tag (org-roam-organize-citar--cite-record-tag))
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
       "No managed literature node for citekey%s: %s"
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
  "Install UUID translation at Citar's Org integration boundaries.

Require `org-roam-organize-mode' to be enabled.  Install insertion advice for
both `citar-insert-citation' in Org buffers and the Citar processor used by
`org-cite-insert'.  Set the default value of `citar-at-point-function' to
`org-roam-organize-citar-dwim'.  Repeated calls are idempotent and return
non-nil after successful installation.  Signal `user-error' when Citar or its
Org integration cannot be loaded, when no valid citation registry record is
configured, or when a required runtime capability is unavailable.

Implementation notes: The function validates the managed citation record
before loading Citar, then checks
`org-roam-organize-citar--capability-alist' after loading `citar' and
`citar-org'.  It advises `citar-org-insert-citation' with
`org-roam-organize-citar--filter-org-insert-args' and
`citar-org-select-key' with
`org-roam-organize-citar--filter-selected-key'.  It records Citar's previous
default at-point function before changing it.  Failed installation removes any
advice added during the attempt and restores the saved default.

Rationale: Explicit installation during Org-roam Organize mode setup provides
a deterministic lifecycle without deferred `with-eval-after-load' callbacks."
  (org-roam-organize-citar--ensure-mode)
  (org-roam-organize-citar--cite-record-tag)
  (unless (require 'citar nil t)
    (user-error
     "Citar is required by the Org-roam Organize Citar adapter"))
  (unless (require 'citar-org nil t)
    (user-error
     (concat "Citar Org integration is required by the "
             "Org-roam Organize Citar adapter")))
  (let ((result
         (org-roam-organize--check-capabilities
          org-roam-organize-citar--capability-alist)))
    (unless (car result)
      (user-error
       "Citar adapter capability check failed (minimum tested version %s): %s"
       org-roam-organize-citar--minimum-tested-version
       (cdr result))))
  (unless org-roam-organize-citar--installed-p
    (setq org-roam-organize-citar--previous-at-point-function
          (default-value 'citar-at-point-function))
    (condition-case err
        (progn
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
          (setq org-roam-organize-citar--installed-p t))
      (error
       (advice-remove
        'citar-org-insert-citation
        #'org-roam-organize-citar--filter-org-insert-args)
       (advice-remove
        'citar-org-select-key
        #'org-roam-organize-citar--filter-selected-key)
       (set-default 'citar-at-point-function
                    org-roam-organize-citar--previous-at-point-function)
       (setq org-roam-organize-citar--previous-at-point-function nil)
       (signal (car err) (cdr err)))))
  t)

(defun org-roam-organize-citar-teardown ()
  "Remove UUID translation from Citar's Org integration boundaries.

Remove both insertion advice functions installed by
`org-roam-organize-citar-setup'.  Restore the saved default value of
`citar-at-point-function' only when it still names
`org-roam-organize-citar-dwim'; preserve a value changed by the user while the
adapter was active.  Return nil after teardown.  This function intentionally
works while `org-roam-organize-mode' is disabled.

Implementation notes: Advice removal is safe when an advice is already absent.
The installation flag distinguishes a previously nil at-point value from an
adapter that was never installed.

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
    (when (eq (default-value 'citar-at-point-function)
              #'org-roam-organize-citar-dwim)
      (set-default 'citar-at-point-function
                   org-roam-organize-citar--previous-at-point-function))
    (setq org-roam-organize-citar--installed-p nil)
    (setq org-roam-organize-citar--previous-at-point-function nil))
  nil)

(provide 'org-roam-organize-citar)

;;; org-roam-organize-citar.el ends here
