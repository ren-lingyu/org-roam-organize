;;; org-roam-organize-capture.el --- Managed capture for Org-roam Organize -*- lexical-binding: t; -*-

;;; Commentary:

;; This internal module builds managed capture templates and creates nodes.

;;; Code:

(require 'cl-lib)
(require 'org-roam-organize-core)

(defvar org-roam-organize-mode)

(defun org-roam-organize--registry-node-records ()
  "Return records that can create managed non-MOC nodes.

Implementation notes: records marked as MOC are excluded, and only records
with a string `:directory' are offered.  This keeps interactive node creation
limited to records that can produce a concrete path template."
  (seq-filter
   (lambda (record)
     (and (not (org-roam-organize--record-moc-p record))
          (stringp (org-roam-organize--record-directory record))))
   (seq-filter #'org-roam-organize--plistp
               org-roam-organize-registry)))

(defun org-roam-organize--read-node-record ()
  "Read and return a registry record for managed node creation.

Implementation notes: selectable records are converted to a display alist
using their name and tag.  `completing-read' returns the display string, which
is mapped back to the original registry plist."
  (let* ((records (org-roam-organize--registry-node-records))
         (alist
          (mapcar
           (lambda (record)
             (cons (format "%s (%s)"
                           (org-roam-organize--record-name record)
                           (org-roam-organize--record-tag record))
                   record))
           records)))
    (when alist
      (let ((choice (completing-read "Node kind: " alist nil t)))
        (cdr (assoc choice alist))))))

(defun org-roam-organize--empty-directory-p (directory)
  "Return non-nil if DIRECTORY is an empty directory.

Implementation notes: the check delegates existence/type handling to
`file-directory-p' and uses `directory-files-no-dot-files-regexp' so `.' and
`..' do not count as contents."
  (and (file-directory-p directory)
       (null (directory-files directory nil directory-files-no-dot-files-regexp))))

(defun org-roam-organize--capture-delete-directory (directory aborted)
  "Clean capture-created DIRECTORY.

If DIRECTORY is empty, delete it automatically.  If ABORTED is non-nil and
DIRECTORY is non-empty, ask before deleting it recursively in interactive
sessions.

Implementation notes: DIRECTORY is always expected to be the managed node
bundle root, not the final target file's parent.  Recursive deletion is
guarded by `yes-or-no-p' and is never attempted in noninteractive sessions."
  (when (and (stringp directory)
             (org-roam-organize--path-inside-root-p
              (file-relative-name directory org-roam-organize-directory))
             (file-directory-p directory))
    (cond
     ((org-roam-organize--empty-directory-p directory)
      (delete-directory directory))
     ((and aborted
           (not noninteractive)
           (yes-or-no-p
            (format "Delete non-empty aborted capture bundle %s? " directory)))
      (delete-directory directory t)))))

(defun org-roam-organize--capture-target-file ()
  "Return the active Org-roam capture file target, or nil.

Implementation notes: the function mirrors Org-roam's file-like target
variants and resolves each target path through
`org-roam-capture--target-truepath'.  Non-file targets return nil because
there is no parent directory to prepare."
  (pcase (org-roam-capture--get-target)
    (`(file ,path)
     (org-roam-capture--target-truepath path))
    (`(file+head ,path ,_head)
     (org-roam-capture--target-truepath path))
    (`(file+olp ,path ,_olp)
     (org-roam-capture--target-truepath path))
    (`(file+head+olp ,path ,_head ,_olp)
     (org-roam-capture--target-truepath path))
    (`(file+datetree ,path ,_tree-type)
     (org-roam-capture--target-truepath path))
    (_ nil)))

(defun org-roam-organize--capture-target-bundle-directory (record target-file)
  "Return RECORD's expanded bundle directory for TARGET-FILE.

Implementation notes: TARGET-FILE must be an expanded Org file target inside
RECORD's absolute directory with at least one bundle-id component below that
directory.  The returned directory is `<directory>/<id>/'.  This function
does not require the path inside the bundle to be flat."
  (let* ((base-directory (org-roam-organize--record-absolute-directory record))
         (target (and (stringp target-file)
                      (expand-file-name target-file)))
         (base (and base-directory
                    (file-name-as-directory
                     (expand-file-name base-directory)))))
    (when (and target
               base
               (string-suffix-p ".org" target)
               (org-roam-organize--absolute-path-inside-directory-p
                target
                base))
      (let* ((relative (file-relative-name target base))
             (components (split-string relative "/" t))
             (bundle-id (car components))
             (bundle-directory
              (and bundle-id
                   (expand-file-name
                    (file-name-as-directory bundle-id)
                    base))))
        (when (and (>= (length components) 2)
                   (not (org-roam-organize--blank-string-p bundle-id))
                   (not (member bundle-id '("." "..")))
                   bundle-directory
                   (not (file-symlink-p bundle-directory))
                   (org-roam-organize--absolute-path-inside-directory-p
                    target
                    bundle-directory))
          bundle-directory)))))

(defun org-roam-organize--capture-create-target-directory (record)
  "Create target parent directory for active managed node capture RECORD.

Return nil so `org-roam-capture-preface-hook' continues with Org-roam's
normal target setup when no directory is created.

Implementation notes: this hook runs after Org-roam has enough capture state
to expand `${id}', `${slug}', and provider `:info' placeholders.  It returns
the managed bundle root so the caller can clean that root later."
  (let* ((file (org-roam-organize--capture-target-file))
         (bundle-directory
          (org-roam-organize--capture-target-bundle-directory record file))
         (target-directory (and file (file-name-directory file))))
    (unless bundle-directory
      (user-error "Managed node capture target escaped its bundle: %s" file))
    (unless (file-directory-p bundle-directory)
      (make-directory bundle-directory t))
    (when (and target-directory
               (org-roam-organize--absolute-path-inside-directory-p
                target-directory
                bundle-directory)
               (not (file-directory-p target-directory)))
      (make-directory target-directory t))
    bundle-directory))

(defun org-roam-organize--capture-aborted-p ()
  "Return non-nil when the current Org capture is being aborted.

Implementation notes: Org binds `org-note-abort' while running capture
finalization hooks.  `bound-and-true-p' keeps this helper safe outside that
dynamic context."
  (bound-and-true-p org-note-abort))

(defun org-roam-organize--capture-node
    (title template &optional info props managed-record on-success)
  "Capture an Org-roam node with TITLE and TEMPLATE.

INFO and PROPS are passed through to `org-roam-capture-'.  When MANAGED-RECORD
is non-nil, create the expanded target's parent directory during Org-roam's
capture preface phase and clean the managed bundle root after capture.  When
ON-SUCCESS is non-nil, it must be a function of no arguments; call it once in
the capture buffer after successful finalization, but not when capture is
aborted.  Signal `user-error' before starting capture when ON-SUCCESS is
neither nil nor a function.

Implementation notes: this helper centralizes the capture call boundary used
by managed ordinary nodes and MOC nodes.  Ordinary nodes pass their registry
record so the bundle root can be computed after Org-roam expands capture
placeholders.  An `org-capture-after-finalize-hook' closure owns both
ON-SUCCESS dispatch and managed-directory cleanup.  It removes itself before
invoking caller code and uses `unwind-protect' so callback errors do not skip
cleanup scheduling.

Rationale: integrations may need to commit buffer-local metadata only after a
capture succeeds.  Keeping that transaction boundary here avoids treating an
interactive `org-roam-capture-' return as proof of successful finalization."
  (let ((key (car-safe template)))
    (unless (and (stringp title)
                 (not (org-roam-organize--blank-string-p title)))
      (user-error "Node title cannot be empty"))
    (unless (and template key)
      (user-error "Cannot capture node without a valid template"))
    (unless (or (null on-success) (functionp on-success))
      (user-error "Capture success callback must be a function"))
    (let ((node (org-roam-node-create :title title)))
      (let (created-directory finalize-hook)
        (cl-labels
            ((finalize ()
               (remove-hook 'org-capture-after-finalize-hook finalize-hook)
               (let ((aborted (org-roam-organize--capture-aborted-p)))
                 (unwind-protect
                     (when (and on-success (not aborted))
                       (funcall on-success))
                   (when created-directory
                     (run-at-time
                      0 nil
                      #'org-roam-organize--capture-delete-directory
                      created-directory
                      aborted)))))
             (create-parent-directory ()
               (setq created-directory
                     (org-roam-organize--capture-create-target-directory
                      managed-record))
               nil))
          (setq finalize-hook #'finalize)
          (when (or managed-record on-success)
            (add-hook 'org-capture-after-finalize-hook finalize-hook t))
          (let ((org-roam-capture-preface-hook
                 (if managed-record
                     (cons #'create-parent-directory
                           org-roam-capture-preface-hook)
                   org-roam-capture-preface-hook)))
            (condition-case err
                (org-roam-capture- :node node
                                   :keys key
                                   :info info
                                   :props props
                                   :templates (list template))
              (error
               (remove-hook 'org-capture-after-finalize-hook finalize-hook)
               (when created-directory
                 (org-roam-organize--capture-delete-directory
                  created-directory
                  t))
               (signal (car err) (cdr err))))))))))

(defun org-roam-organize--moc-node-provider (record)
  "Return RECORD's MOC node creation request.

The return value is nil when RECORD cannot produce a MOC title, otherwise a
plist with `:title' and optional `:info'.

Implementation notes: MOC creation uses the same provider request protocol as
ordinary managed node creation, but the provider is selected internally by the
MOC creation command instead of being read from the registry.  The title is
derived from `org-roam-organize--record-moc-title'.  The capture info keeps
the existing `:moc_managed_tag' field so templates that still reference it
continue to receive the same dynamic value."
  (let ((title (org-roam-organize--record-moc-title record))
        (tag (org-roam-organize--record-tag record)))
    (when (stringp title)
      (list :title title
            :info `(:moc_managed_tag ,tag)))))

(defun org-roam-organize--record-node-capture-template (record)
  "Return a managed node capture template for RECORD.

Implementation notes: this builds a one-template Org-roam capture list using
the registry-derived node path template and file head.  It does not register
the template globally; callers pass it directly to `org-roam-capture-'."
  (let ((path (org-roam-organize--record-node-path-template record))
        (head (org-roam-organize--record-node-head record)))
    (when (and (stringp path) (stringp head))
      (list org-roam-organize--node-capture-key
            (format "%s node" (org-roam-organize--record-name record))
            'plain
            "%?"
            :target
            (list 'file+head path head)
            :unnarrowed t))))

(defun org-roam-organize--record-moc-capture-template (record)
  "Return a MOC capture template for RECORD.

Implementation notes: MOC creation uses the same capture protocol as normal
node creation, but targets a fixed absolute MOC path instead of the managed
node relative path template."
  (let ((path (org-roam-organize--record-absolute-moc-path record))
        (head (org-roam-organize--record-moc-head record)))
    (when (and (stringp path) (stringp head))
      (list org-roam-organize--moc-capture-key
            "map of contents"
            'plain
            "%?"
            :target
            (list 'file+head path head)
            :unnarrowed t))))

;; 创建目录
;;;###autoload
(defun org-roam-organize-create-directories ()
  "Create the root and basic registry directories when missing.

Implementation notes: the directory list is built from
`org-roam-organize-directory' plus absolute directories derived from
`:basic t' registry records.  Existing directories and nil entries are
skipped; missing directories are created recursively."
  (interactive)
  (let ((dir_list
         (cons
          org-roam-organize-directory
          (mapcar #'org-roam-organize--record-absolute-directory
                  (org-roam-organize--registry-basic-records)))))
    (dolist (dir dir_list)
      (unless (or (not dir) (file-exists-p dir))
        (make-directory dir t)))))

;; 创建受管理的普通 org-roam node
;;;###autoload
(defun org-roam-organize-node-create ()
  "Create a managed Org-roam node using `org-roam-organize-registry'.

The selected registry record must define a relative `:directory'.  The
created node uses the standard path layout
<directory>/${id}/${path} under `org-roam-organize-directory'.
If the record declares `:provider', that provider supplies the node title and
optional capture info; otherwise the built-in default provider reads a title.
Org-roam Organize creates the expanded target parent directory during
Org-roam's capture preface phase and cleans the managed bundle root after
capture.

Implementation notes: the command reads a registry record, obtains its
provider with `org-roam-organize--record-provider', calls the provider to get
a node creation request, builds a temporary one-entry capture template, and
delegates the capture call to `org-roam-organize--capture-node'.  That helper
installs a preface hook to compute the expanded bundle root and create the
target parent directory after Org-roam has assigned capture placeholders, plus
an after-finalize hook to clean only that bundle root."
  (interactive)
  (if org-roam-organize-mode
      (let ((record (org-roam-organize--read-node-record)))
        (if (not record)
            (message "[WARNING] No registry record can create managed nodes.")
          (let* ((provider (org-roam-organize--record-provider record))
                 (request (when (functionp provider)
                            (funcall provider record)))
                 (template (org-roam-organize--record-node-capture-template record))
                 (key (car-safe template)))
            (cond
             ((not (functionp provider))
              (message "[WARNING] Invalid node provider for registry record: %s" record))
             ((null request)
              (message "[INFO] Node creation canceled."))
             ((not (org-roam-organize--node-request-valid-p request))
              (message "[WARNING] Invalid node creation request: %s" request))
             ((not (and template key))
              (message "[WARNING] Cannot create node for registry record: %s" record))
             (t
              (org-roam-organize--capture-node
               (plist-get request :title)
               template
               (plist-get request :info)
               nil
               record))))))
    (message "[WARNING] This function requires org-roam-organize-mode to be enabled (current value: %s)" org-roam-organize-mode)))


(provide 'org-roam-organize-capture)
;;; org-roam-organize-capture.el ends here
