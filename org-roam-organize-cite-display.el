;;; org-roam-organize-cite-display.el --- Citation display for Org-roam Organize -*- lexical-binding: t; -*-

;;; Commentary:

;; This bundled module displays managed literature-node titles over UUID keys
;; in Org Cite citations.  It changes only buffer presentation: source text,
;; Org Element data, and export-time citation identity remain unchanged.

;;; Code:

(require 'subr-x)
(require 'org-roam-organize)

(defvar org-element-citation-prefix-re)
(defvar org-font-lock-extra-keywords)
(defvar org-font-lock-set-keywords-hook)

(defconst org-roam-organize-cite-display--capability-alist
  '((font-lock-ensure . function)
    (font-lock-flush . function)
    (font-lock-refresh-defaults . function)
    (org-cite-get-references . function)
    (org-cite-key-boundaries . function)
    (org-element-citation-parser . function)
    (org-element-citation-prefix-re . variable)
    (org-font-lock-extra-keywords . variable)
    (org-font-lock-set-keywords-hook . variable)
    (org-set-font-lock-defaults . function))
  "The alist describes runtime capabilities required by citation display.

Each entry maps an Org or Font Lock symbol to the capability type accepted by
`org-roam-organize--check-capabilities'.  Setup checks the table only when a
managed citation record exists, so installations that do not use citations
do not depend on these presentation interfaces.")

(defvar-local org-roam-organize-cite-display--title-cache nil
  "The buffer-local mapping from managed citation UUIDs to node titles.

Nil means the mapping has not been queried in the current buffer.  Once
initialized, the value is an `equal'-tested hash table, including when the
query produced no usable titles.  Citation display refresh and teardown reset
the value to nil.")

(defvar-local org-roam-organize-cite-display--overlays nil
  "The overlays owned by citation title display in the current buffer.

The list may temporarily contain deleted overlays after unrelated buffer
operations.  Overlay creation and cleanup prune such entries before retaining
the live overlays owned by this module.")

(defun org-roam-organize-cite-display--make-title-table ()
  "Return a table mapping managed literature UUIDs to node titles.

The result is an `equal'-tested hash table.  Include only level-0 nodes tagged
by the unique `:cite t' registry record and having non-empty string IDs and
titles.  Return an empty table when no citation record is configured or when
the database query fails.  A query failure is reported as a warning instead
of interrupting Font Lock.

Implementation notes: Node selection delegates to
`org-roam-organize--nodes-with-tag', keeping the presentation boundary
identical to the package's other managed-literature operations.

Rationale: Fontification must not turn a temporarily unavailable Org-roam
database into an editing failure, and it must not interpret arbitrary Org-roam
nodes or UUID-shaped keys as managed literature citations."
  (let ((table (make-hash-table :test 'equal))
        (record (org-roam-organize--registry-cite-record)))
    (when record
      (condition-case err
          (dolist (node
                   (org-roam-organize--nodes-with-tag
                    (org-roam-organize--record-tag record)))
            (let ((id (plist-get node :id))
                  (title (plist-get node :title)))
              (when (and (stringp id)
                         (not (string-empty-p id))
                         (stringp title)
                         (not (string-empty-p title)))
                (puthash id title table))))
        (error
         (message
          "[WARNING] Org-roam Organize citation titles are unavailable: %s"
          (error-message-string err)))))
    table))

(defun org-roam-organize-cite-display--title (key)
  "Return the managed literature node title for citation KEY.

Return nil when Org-roam Organize mode is disabled, KEY is not a managed
literature node UUID, or the node has no usable title.  The first lookup in a
buffer lazily initializes `org-roam-organize-cite-display--title-cache'; later
lookups use the same table until refresh or teardown.

Rationale: A single database query per buffer avoids repeating a complete
managed-node query for every citation reference Font Lock encounters."
  (when (and org-roam-organize-mode (stringp key))
    (unless (hash-table-p org-roam-organize-cite-display--title-cache)
      (setq org-roam-organize-cite-display--title-cache
            (org-roam-organize-cite-display--make-title-table)))
    (gethash key org-roam-organize-cite-display--title-cache)))

(defun org-roam-organize-cite-display--delete-overlay (overlay)
  "Delete citation display OVERLAY and release its buffer-local ownership.

Calling this function for a deleted overlay is safe.  Return nil.

Implementation notes: Overlay lifecycle tracks both a package property and a
buffer-local list.  The property supports inspection and tests, while the list
allows cleanup without examining overlays owned by Org, Citar, or other
packages."
  (setq org-roam-organize-cite-display--overlays
        (delq overlay org-roam-organize-cite-display--overlays))
  (delete-overlay overlay)
  nil)

(defun org-roam-organize-cite-display--overlay-modified
    (overlay after _beg _end &optional _length)
  "Remove citation display OVERLAY after its source range is modified.

AFTER is non-nil for the post-change invocation of an overlay modification or
boundary-insertion hook.  BEG, END, and LENGTH are supplied by Emacs and are
not otherwise used.  The pre-change invocation leaves the overlay intact.

Rationale: A stale title must never remain visible after the underlying UUID
or surrounding citation boundary has been edited."
  (when after
    (org-roam-organize-cite-display--delete-overlay overlay)))

(defun org-roam-organize-cite-display--clear-overlays (&optional beg end)
  "Delete owned citation display overlays between BEG and END.

When BEG and END are nil, delete every citation display overlay owned by the
current buffer.  Otherwise delete overlays whose ranges overlap the half-open
interval from BEG to END.  Deleted overlays already present in the ownership
list are pruned.  Return nil.  Buffer text, text properties, and overlays
owned by other components are unchanged.

Implementation notes: The function walks the buffer-local ownership list
instead of `overlays-in', so cleanup is unaffected by buffer narrowing and
does not need to classify third-party overlays."
  (dolist (overlay (copy-sequence
                    org-roam-organize-cite-display--overlays))
    (let ((overlay-buffer (overlay-buffer overlay)))
      (cond
       ((null overlay-buffer)
        (setq org-roam-organize-cite-display--overlays
              (delq overlay org-roam-organize-cite-display--overlays)))
       ((or (and (null beg) (null end))
            (and beg
                 end
                 (< (overlay-start overlay) end)
                 (> (overlay-end overlay) beg)))
        (org-roam-organize-cite-display--delete-overlay overlay)))))
  nil)

(defun org-roam-organize-cite-display--make-overlay (beg end title)
  "Display TITLE over the citation key between BEG and END.

Create and return an overlay without modifying buffer text or its text
properties.  The overlay is marked as owned by Org-roam Organize and removes
itself when its source range or either boundary is edited.

Rationale: A `display' overlay preserves the UUID in Org source and the Org
Element syntax tree while allowing Org's citation faces, keymaps, and
activation processor to remain installed independently."
  (let ((overlay (make-overlay beg end nil nil nil)))
    (overlay-put overlay 'display title)
    (overlay-put overlay 'org-roam-organize-cite-display t)
    (overlay-put overlay 'modification-hooks
                 (list #'org-roam-organize-cite-display--overlay-modified))
    (overlay-put overlay 'insert-in-front-hooks
                 (list #'org-roam-organize-cite-display--overlay-modified))
    (overlay-put overlay 'insert-behind-hooks
                 (list #'org-roam-organize-cite-display--overlay-modified))
    (push overlay org-roam-organize-cite-display--overlays)
    overlay))

(defun org-roam-organize-cite-display--activate (limit)
  "Add managed citation title overlays before LIMIT.

Search forward from point for one Org citation and return non-nil when a
citation prefix is found.  Parse the citation with Org Cite, replace no source
text, and create one display overlay for each managed citation reference with
a usable node title.  Advance point to the parsed citation's end.  Malformed
or incomplete citations remain unchanged and do not interrupt Font Lock.

Implementation notes: The matcher follows `org-cite-activate': it searches
with `org-element-citation-prefix-re', parses with
`org-element-citation-parser', obtains references through
`org-cite-get-references', and uses `org-cite-key-boundaries' for the exact
range including the leading at sign.  Existing owned overlays in the citation
range are deleted first, making repeated fontification idempotent.  Its
match-data handling mirrors `org-cite-activate'.

Rationale: Reusing Org's citation grammar avoids duplicating the rules for
styles, prefixes, suffixes, separators, and citation keys."
  (when (re-search-forward org-element-citation-prefix-re limit t)
    (let* ((citation-beginning (match-beginning 0))
           (citation
            (condition-case nil
                (org-with-point-at citation-beginning
                  (org-element-citation-parser))
              (error nil))))
      (when citation
        (let ((begin (org-element-property :begin citation))
              (end (org-element-property :end citation)))
          (save-match-data
            (org-roam-organize-cite-display--clear-overlays begin end)
            (dolist (reference (org-cite-get-references citation))
              (condition-case nil
                  (when-let* ((key (org-element-property :key reference))
                              (title
                               (org-roam-organize-cite-display--title key))
                              (bounds (org-cite-key-boundaries reference)))
                    (org-roam-organize-cite-display--make-overlay
                     (car bounds) (cdr bounds) title))
                (error nil))))
          (goto-char end)))
      t)))

(defun org-roam-organize-cite-display--font-lock-setup ()
  "Append managed citation title activation to Org Font Lock keywords.

This function is called in each Org buffer by
`org-font-lock-set-keywords-hook'.  It changes only the buffer's
`org-font-lock-extra-keywords' value and safely avoids duplicate entries.

Rationale: An extra Font Lock matcher composes with the selected Org Cite
activation processor instead of replacing the single
`org-cite-activate-processor' setting."
  (add-to-list 'org-font-lock-extra-keywords
               '(org-roam-organize-cite-display--activate)
               t))

(defun org-roam-organize-cite-display--refresh-font-lock ()
  "Rebuild and refresh Org Font Lock in the current buffer.

Return nil after reconstructing Org's Font Lock defaults and restarting
fontification when `font-lock-mode' is enabled.  Require the current buffer to
derive from `org-mode'.  Buffers with Font Lock disabled receive the rebuilt
defaults but remain disabled.

Implementation notes: `org-set-font-lock-defaults' reruns
`org-font-lock-set-keywords-hook' and rebuilds `org-font-lock-keywords'.
`font-lock-refresh-defaults' then recomputes Font Lock state from those
defaults and restarts fontification.

Rationale: `org-restart-font-lock' alone reuses already constructed defaults,
so it cannot add or remove a matcher registered after an Org buffer was
initialized."
  (org-set-font-lock-defaults)
  (when font-lock-mode
    (font-lock-refresh-defaults))
  nil)

(defun org-roam-organize-cite-display--refresh-org-buffers ()
  "Refresh Font Lock defaults in every live Org-derived buffer.

Return nil after visiting existing buffers without changing their current
buffer, point, narrowing, source text, or modified state.  Buffers with Font
Lock disabled remain disabled.

Rationale: `org-roam-organize-mode' is global, and changing
`org-font-lock-set-keywords-hook' alone does not update Org buffers whose
keywords were initialized before the mode lifecycle transition."
  (dolist (buffer (buffer-list))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when (derived-mode-p 'org-mode)
          (org-roam-organize-cite-display--refresh-font-lock)))))
  nil)

(defun org-roam-organize-cite-display--clear ()
  "Clear citation presentation state in the current buffer.

Delete all owned title overlays and reset the buffer-local title cache.
Return nil.  Calling this function repeatedly is safe and does not modify
source text, text properties, or third-party overlays."
  (org-roam-organize-cite-display--clear-overlays)
  (setq org-roam-organize-cite-display--title-cache nil)
  nil)

;;;###autoload
(defun org-roam-organize-cite-display-refresh ()
  "Refresh managed citation title display in the current Org buffer.

Use this command after literature node titles or managed membership change.
Require `org-roam-organize-mode' in an Org-derived buffer.  Clear the local
title cache and owned overlays, rebuild Org Font Lock defaults, and eagerly
fontify the accessible buffer.  The command does not toggle `font-lock-mode'.
Source text and its modified state are unchanged.

Rationale: Database updates do not automatically invalidate presentation
caches in every open buffer; an explicit refresh keeps the first version
independent of Org-roam database update internals."
  (interactive)
  (unless org-roam-organize-mode
    (user-error "Org-roam Organize mode must be enabled"))
  (unless (derived-mode-p 'org-mode)
    (user-error "Citation display refresh requires an Org buffer"))
  (org-roam-organize-cite-display--clear)
  (org-roam-organize-cite-display--refresh-font-lock)
  (font-lock-flush (point-min) (point-max))
  (font-lock-ensure (point-min) (point-max)))

(defun org-roam-organize-cite-display--setup ()
  "Install managed citation title presentation.

Require `org-roam-organize-mode' and a configured `:cite t' registry record.
Check the required Org and Font Lock interfaces, add the global Org keyword
setup hook, and restart existing Org buffers.  Repeated calls are idempotent
and return non-nil after installation.  Signal `user-error' when a required
runtime capability is missing.

Implementation notes: `org-roam-organize--setup-cite-integration' owns this
function's lifecycle and calls the matching teardown function during mode
disable or failed setup rollback.

Rationale: Citation titles are a backend-independent presentation of the
managed literature identity, so their lifecycle follows the core citation
integration rather than an optional interactive backend."
  (unless org-roam-organize-mode
    (user-error "Org-roam Organize mode must be enabled"))
  (unless (org-roam-organize--registry-cite-record)
    (user-error "No :cite t registry record is configured"))
  (let ((result
         (org-roam-organize--check-capabilities
          org-roam-organize-cite-display--capability-alist)))
    (unless (car result)
      (user-error "Citation display capabilities are unavailable:\n%s"
                  (cdr result))))
  (add-hook 'org-font-lock-set-keywords-hook
            #'org-roam-organize-cite-display--font-lock-setup)
  (org-roam-organize-cite-display--refresh-org-buffers)
  t)

(defun org-roam-organize-cite-display--teardown ()
  "Remove managed citation title presentation.

Remove the global Org keyword setup hook, clear owned overlays and title
caches from every live Org-derived buffer, and restart their Font Lock.
Return nil.  Calling this function before setup or more than once is safe.

Implementation notes: Cleanup uses the module's buffer-local ownership list
and therefore leaves Org, Citar, and other packages' overlays untouched."
  (remove-hook 'org-font-lock-set-keywords-hook
               #'org-roam-organize-cite-display--font-lock-setup)
  (dolist (buffer (buffer-list))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when (derived-mode-p 'org-mode)
          (org-roam-organize-cite-display--clear)
          (org-roam-organize-cite-display--refresh-font-lock)))))
  nil)

(provide 'org-roam-organize-cite-display)
;;; org-roam-organize-cite-display.el ends here
