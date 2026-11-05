;;; org-roam-organize-moc.el --- MOC management for Org-roam Organize -*- lexical-binding: t; package-lint-main-file: "org-roam-organize.el"; -*-

;;; Commentary:

;; This module manages one MOC file with independent CUSTOM_ID regions.

;;; Code:

(require 'org-roam-organize-core)
(require 'org-roam-organize-capture)
(require 'org-roam-organize-entry)

(defvar org-roam-organize-mode)

(defun org-roam-organize--moc-node-entry-line
    (id title &optional delete)
  "Return a MOC node entry line for ID, TITLE, and DELETE flag.

Implementation notes: this is the MOC-specific wrapper around
`org-roam-organize--id-link-keyword-entry-line'.  It fixes the keyword name
to `org-roam-organize--moc-node-keyword' and serializes the existing
`:delete t' marker when requested."
  (org-roam-organize--id-link-keyword-entry-line
   org-roam-organize--moc-node-keyword id title
   (when delete
     " :delete t")))

(defun org-roam-organize--moc-node-entry-delete-p (suffix)
  "Return non-nil if MOC node entry SUFFIX contains `:delete t'.

Implementation notes: the suffix is read as Lisp data into a plist-like list,
then queried with `plist-get'.  Read errors are caught and treated as a
non-delete marker so malformed suffixes do not break MOC parsing."
  (when (stringp suffix)
    (condition-case nil
        (let ((start 0)
              values)
          (while (< start (length suffix))
            (let ((result (read-from-string suffix start)))
              (push (car result) values)
              (setq start (cdr result))))
          (eq (plist-get (nreverse values) :delete) t))
      (error
       nil))))

(defun org-roam-organize--moc-parse-node-entry-value (value)
  "Parse a MOC node entry keyword VALUE.

Return a plist with `:id', `:title', and `:delete', or nil when VALUE does
not contain a valid id link at the beginning.

Implementation notes: this MOC-specific wrapper delegates id-link parsing to
`org-roam-organize--parse-id-link-keyword-entry-value' and only adds parsing
of the MOC `:delete t' suffix."
  (org-roam-organize--parse-id-link-keyword-entry-value
   value
   (lambda (suffix)
     (list
      :delete (org-roam-organize--moc-node-entry-delete-p suffix)))))

(defun org-roam-organize--moc-parse-node-entries ()
  "Parse MOC node entries in the current buffer.

Return a plist containing `:entries' and `:malformed'.  Entries are plists
with `:id', `:title', `:delete', `:begin', and `:end'.

Implementation notes: this MOC-specific wrapper parses real
`#+ROAM_NODE' keyword elements by delegating to
`org-roam-organize--parse-id-link-keyword-entries' and adding MOC delete
suffix parsing."
  (org-roam-organize--parse-id-link-keyword-entries
   org-roam-organize--moc-node-keyword
   (lambda (suffix)
     (list
      :delete (org-roam-organize--moc-node-entry-delete-p suffix)))))

(defun org-roam-organize--moc-records ()
  "Return registry records owning management regions, in registry order."
  (seq-remove
   #'org-roam-organize--record-moc-p org-roam-organize-registry))

(defun org-roam-organize--moc-check-configuration ()
  "Reject invalid registry and root configuration before touching a MOC."
  (unless org-roam-organize-mode
    (user-error "Enable org-roam-organize-mode first"))
  (dolist (result
           (list
            (org-roam-organize--validate-registry)
            (org-roam-organize--check-root-directory)))
    (unless (car result)
      (user-error "%s" (cdr result)))))

(defun org-roam-organize--moc-discover (&optional creating)
  "Resolve the unique MOC by tag and enforce all explicit declarations.

Return (:status ok :id ID :file PATH), or (:status missing :file TARGET)
when CREATING permits a new file.  Conflicts never fall back to another
query.  The default creation target does not constrain an existing MOC."
  (let* ((record (org-roam-organize--registry-moc-record))
         (id (org-roam-organize--record-moc-id record))
         (explicit
          (org-roam-organize--record-moc-explicit-path record))
         (target (org-roam-organize--record-absolute-moc-path record))
         (seen (make-hash-table :test 'equal))
         nodes)
    (org-roam-db)
    (dolist (node
             (org-roam-organize--nodes-with-tag-and-file
              (org-roam-organize--record-tag record)))
      (let* ((key (plist-get node :id))
             (prior (gethash key seen)))
        (when (and prior
                   (not
                    (equal
                     (plist-get prior :file) (plist-get node :file))))
          (user-error "Conflicting MOC database paths for ID %s" key))
        (unless prior
          (puthash key node seen)
          (push node nodes))))
    (when (> (length nodes) 1)
      (user-error
       "Multiple MOC nodes have the MOC tag; migrate old map-tag files and sync the DB"))
    (if nodes
        (let* ((node (car nodes))
               (actual-id (plist-get node :id))
               (file (plist-get node :file)))
          (unless (and (org-roam-organize--moc-id-p actual-id)
                       (stringp file)
                       (file-name-absolute-p file)
                       (string-suffix-p ".org" file)
                       (file-in-directory-p
                        file org-roam-organize-directory)
                       (file-regular-p file))
            (user-error
             "MOC node has an invalid ID or unsafe/missing file"))
          (when (and id (not (equal id actual-id)))
            (user-error
             "MOC tag node does not match declared :moc-id"))
          (when (and explicit
                     (not
                      (equal
                       (file-truename file) (file-truename target))))
            (user-error
             "MOC tag node does not match declared :moc-path"))
          (list :status 'ok :id actual-id :file file))
      (when (and id
                 (org-roam-db-query
                  [:select [id] :from nodes :where (= id $s1)] id))
        (user-error
         "Declared :moc-id is already used by another node"))
      (when (and target (file-exists-p target))
        (user-error
         "MOC target exists without a matching tagged node; migrate or sync the DB"))
      (unless creating
        (user-error
         "MOC is missing; run org-roam-organize-moc-create"))
      (list :status 'missing :file target))))

(defun org-roam-organize--moc-check-file (tree identity)
  "Check TREE's actual file-level ID and tag against resolved IDENTITY."
  (let (id
        tags)
    (org-element-map
     tree '(node-property keyword)
     (lambda (element)
       (unless (org-element-lineage element '(headline))
         (pcase (org-element-type element)
           ('node-property
            (when (equal (org-element-property :key element) "ID")
              (when id
                (user-error "Multiple file-level MOC IDs"))
              (setq id (org-element-property :value element))))
           ('keyword
            (when (equal
                   (org-element-property :key element) "FILETAGS")
              (setq tags
                    (append
                     tags
                     (split-string (org-element-property
                                    :value element)
                                   ":" t "[ \t]+")))))))))
    (unless (and (equal id (plist-get identity :id))
                 (member
                  (org-roam-organize--record-tag
                   (org-roam-organize--registry-moc-record))
                  tags))
      (user-error
       "MOC file ID/tag disagrees with the DB; sync the DB or migrate the file"))))

(defun org-roam-organize--moc-regions (tree)
  "Validate managed CUSTOM_ID headlines in TREE and return their layout.

The result contains :regions (tag/headline alist), :missing records and
:level.  All matches, including commented ones, participate in conflicts.
Existing regions may have different parents but must have the same level.
A missing region with a same-title, unclaimed CUSTOM_ID is ambiguous, not
automatically adopted.  Ordinary titles without CUSTOM_ID and manual children
of known management regions do not establish another region's identity."
  (let ((wanted (make-hash-table :test 'equal))
        (found (make-hash-table :test 'equal))
        (unclaimed-titles (make-hash-table :test 'equal))
        regions
        missing
        level)
    (dolist (record (org-roam-organize--moc-records))
      (puthash (org-roam-organize--record-tag record) record wanted))
    (org-element-map
     tree 'headline
     (lambda (headline)
       (let ((tag (org-element-property :CUSTOM_ID headline)))
         (when (and tag
                    (not (gethash tag wanted))
                    (not
                     (org-roam-organize--element-commented-p
                      headline)))
           (let ((title (org-element-property :raw-value headline))
                 (parent (org-element-lineage headline '(headline)))
                 managed-parent)
             (while (and parent (not managed-parent))
               (setq
                managed-parent
                (gethash
                 (org-element-property :CUSTOM_ID parent) wanted)
                parent (org-element-lineage parent '(headline))))
             (unless managed-parent
               (puthash
                title
                (cons tag (gethash title unclaimed-titles))
                unclaimed-titles))))
         (when (gethash tag wanted)
           (unless (equal
                    (org-element-property :raw-value headline)
                    (org-roam-organize--record-moc-title
                     (gethash tag wanted)))
             (user-error
              "Managed headline title does not match record for CUSTOM_ID %s"
              tag))
           (when (gethash tag found)
             (user-error "Duplicate managed CUSTOM_ID: %s" tag))
           (when (org-roam-organize--element-commented-p headline)
             (user-error "Managed CUSTOM_ID %s is inside COMMENT"
                         tag))
           (let ((current (org-element-property :level headline)))
             (when (and level (/= level current))
               (user-error
                "Managed CUSTOM_ID headlines must have the same level, without nesting"))
             (setq level current))
           (puthash tag headline found)))))
    (dolist (record (org-roam-organize--moc-records))
      (let* ((tag (org-roam-organize--record-tag record))
             (headline (gethash tag found)))
        (if headline
            (push (cons tag headline) regions)
          (let ((conflicts
                 (gethash
                  (org-roam-organize--record-moc-title record)
                  unclaimed-titles)))
            (when conflicts
              (user-error
               "Possible MOC region identity conflict for %s: same-title headline has unregistered CUSTOM_ID %S; resolve manually"
               (org-roam-organize--record-name record) conflicts)))
          (push record missing))))
    (list
     :regions (nreverse regions)
     :missing (nreverse missing)
     :level (or level 1))))

(defun org-roam-organize--moc-region-text (record level)
  "Return a new management headline for RECORD at LEVEL."
  (format "%s %s\n:PROPERTIES:\n:CUSTOM_ID: %s\n:END:\n"
          (make-string level ?*)
          (org-roam-organize--record-moc-title record)
          (org-roam-organize--record-tag record)))

(defun org-roam-organize--moc-check-new-region-titles
    (records &optional file-head)
  "Preflight RECORDS' new titles in the target file's Org syntax.

FILE-HEAD supplies the new capture's keyword context.  Otherwise retain the
current Org buffer's effective TODO keywords.  Reject before editing or
creating directories, even when file-local keywords differ from defaults."
  (let ((prologue
         (or file-head
             (concat
              "#+TODO: "
              (mapconcat #'identity org-todo-keywords-1 " ") "\n"))))
    (dolist (record records)
      (unless (org-roam-organize--moc-headline-title-p
               (org-roam-organize--record-moc-title record) prologue)
        (user-error
         "Management title for %s is not a plain headline in the MOC file's Org syntax"
         (org-roam-organize--record-name record))))))

(defun org-roam-organize--moc-save (tick)
  "Save and refresh the DB once if buffer text changed since TICK."
  (when (/= tick (buffer-chars-modified-tick))
    (let ((org-roam-db-update-on-save nil))
      (save-buffer)
      (org-roam-db-update-file buffer-file-name))
    t))

(defun org-roam-organize--moc-create-regions (tree layout)
  "Add missing management headlines from validated LAYOUT and TREE.

Level 1 appends at EOF.  Deeper regions use the MOC record's level-1 Inbox,
before its first child, creating only that level-1 container when absent."
  (let ((missing (plist-get layout :missing))
        (level (plist-get layout :level))
        (tick (buffer-chars-modified-tick)))
    (when missing
      (org-roam-organize--moc-check-new-region-titles missing)
      (let ((name
             (org-roam-organize--record-inbox
              (org-roam-organize--registry-moc-record)))
            inbox)
        (when (> level 1)
          (org-element-map
           tree 'headline
           (lambda (headline)
             (when (and (= (org-element-property :level headline) 1)
                        (equal
                         (org-element-property
                          :raw-value headline)
                         name)
                        (not
                         (org-roam-organize--element-commented-p
                          headline)))
               (when inbox
                 (user-error
                  "Multiple level-1 MOC Inbox headlines named %s"
                  name))
               (setq inbox headline))))
          (unless (or inbox
                      (org-roam-organize--moc-headline-title-p
                       name
                       (concat
                        "#+TODO: "
                        (mapconcat #'identity org-todo-keywords-1 " ")
                        "\n")))
            (user-error
             "MOC :inbox must be a plain Org headline title before creating it")))
        (atomic-change-group
          (goto-char
           (if inbox
               (or (org-roam-organize--first-child-headline-begin
                    inbox)
                   (org-element-property :end inbox))
             (point-max)))
          (unless (bolp)
            (insert "\n"))
          (when (and (> level 1) (not inbox))
            (insert "* " name "\n"))
          (dolist (record missing)
            (insert
             (org-roam-organize--moc-region-text record level))))))
    (org-roam-organize--moc-save tick)
    (length missing)))

(defun org-roam-organize--moc-region-inbox (headline record)
  "Return RECORD's unique active direct-child Inbox under HEADLINE, or nil.

Reject multiple matches even when no members need insertion.  Deeper names,
COMMENT subtrees and other management regions do not participate."
  (let ((level (1+ (org-element-property :level headline)))
        inbox)
    (org-element-map
     headline 'headline
     (lambda (child)
       (when (and (= (org-element-property :level child) level)
                  (equal
                   (org-element-property :raw-value child)
                   (org-roam-organize--record-inbox record))
                  (not
                   (org-roam-organize--element-commented-p child)))
         (when inbox
           (user-error
            "Multiple direct-child Inboxes named %s in MOC region %s"
            (org-roam-organize--record-inbox record)
            (org-roam-organize--record-tag record)))
         (setq inbox child))))
    inbox))

(defun org-roam-organize--moc-region-insertion (headline record inbox)
  "Plan insertion under HEADLINE for RECORD using validated INBOX or nil.

Return (:position MARKER :prefix TEXT).  The marker advances at edit
boundaries; callers must clear it even on error."
  (let ((level (1+ (org-element-property :level headline))))
    (list
     :position
     (copy-marker
      (if inbox
          (or (org-roam-organize--first-child-headline-begin inbox)
              (org-element-property :end inbox))
        (org-element-property :end headline))
      t)
     :prefix
     (unless inbox
       (concat
        (make-string level ?*)
        " "
        (org-roam-organize--record-inbox record)
        "\n")))))

(defun org-roam-organize--moc-sync-buffer (layout file)
  "Sync regions using validated LAYOUT for MOC FILE.

Prepare every plan and marker before editing; apply existing edits in global
reverse position order.  Return per-record results and a :saved flag."
  (let ((tick (buffer-chars-modified-tick))
        edits
        insertions
        results
        markers)
    (unwind-protect
        (progn
          (dolist (record (org-roam-organize--moc-records))
            (let* ((tag (org-roam-organize--record-tag record))
                   (headline
                    (cdr (assoc tag (plist-get layout :regions)))))
              (if (not headline)
                  (push
                   (list
                    :record record
                    :status 'failed
                    :reason "Management CUSTOM_ID is missing; run moc-create")
                   results)
                (let*
                    ((inbox
                      (org-roam-organize--moc-region-inbox
                       headline record))
                     (nodes
                      (seq-remove
                       (lambda (node)
                         (equal (plist-get node :file) file))
                       (org-roam-organize--nodes-with-tag-and-file
                        tag)))
                     (parsed
                      (org-roam-organize--parse-id-link-keyword-entries-in-tree
                       headline org-roam-organize--moc-node-keyword
                       (lambda (suffix)
                         (list
                          :delete
                          (org-roam-organize--moc-node-entry-delete-p
                           suffix)))))
                     (plan
                      (org-roam-organize--plan-id-link-keyword-entries
                       (plist-get parsed :entries) nodes)))
                  (dolist (edit (plist-get plan :edits))
                    (let* ((entry (car edit))
                           (node (cdr edit))
                           (text
                            (and
                             node
                             (org-roam-organize--moc-node-entry-line
                              (plist-get entry :id)
                              (plist-get node :title)
                              (plist-get entry :delete)))))
                      (unless (and text
                                   (equal
                                    text
                                    (buffer-substring-no-properties
                                     (plist-get entry :begin)
                                     (plist-get entry :end))))
                        (push edit edits))))
                  (when (plist-get plan :missing)
                    (let ((insertion
                           (org-roam-organize--moc-region-insertion
                            headline record inbox)))
                      (push (plist-get insertion :position) markers)
                      (push (append
                             insertion
                             (list :nodes (plist-get plan :missing)))
                            insertions)))
                  (push (list
                         :record record
                         :status 'ok
                         :duplicates (plist-get plan :duplicates)
                         :removed (plist-get plan :removed)
                         :malformed (plist-get parsed :malformed))
                        results)))))
          (atomic-change-group
            (org-roam-organize--apply-id-link-keyword-entry-plan
             org-roam-organize--moc-node-keyword
             (list
              :edits
              (sort edits
                    (lambda (a b)
                      (> (plist-get (car a) :begin)
                         (plist-get (car b) :begin)))))
             (lambda (entry)
               (when (plist-get entry :delete)
                 " :delete t")))
            (dolist (insertion (nreverse insertions))
              (goto-char (plist-get insertion :position))
              (unless (bolp)
                (insert "\n"))
              (when (plist-get insertion :prefix)
                (insert (plist-get insertion :prefix)))
              (org-roam-organize--insert-id-link-keyword-entries
               org-roam-organize--moc-node-keyword
               (plist-get insertion :nodes)
               (point))))
          (list
           :results (nreverse results)
           :saved (org-roam-organize--moc-save tick)))
      (dolist (marker markers)
        (set-marker marker nil)))))

(defun org-roam-organize--moc-report (label operation)
  "Run OPERATION and report errors through the shared report buffer for LABEL."
  (condition-case err
      (progn
        (org-roam-organize--moc-check-configuration)
        (funcall operation))
    (error
     (let ((reason (error-message-string err)))
       (org-roam-organize--display-report label (list reason))
       (message "%s"
                (org-roam-organize--report-notice 'warning reason))
       (list :status 'failed :reason reason)))))

;;;###autoload
(defun org-roam-organize-moc-open-index ()
  "Open the unique tagged MOC after checking its ID, path and structure."
  (interactive)
  (org-roam-organize--moc-report
   "Org-roam Organize MOC Open"
   (lambda ()
     (let* ((identity (org-roam-organize--moc-discover))
            (file (plist-get identity :file)))
       (with-current-buffer (find-file-noselect file)
         (org-with-wide-buffer
          (let ((tree (org-element-parse-buffer)))
            (org-roam-organize--moc-check-file tree identity)
            (org-roam-organize--moc-regions tree))))
       (find-file file)))))

;;;###autoload
(defun org-roam-organize-moc-create ()
  "Create the unique MOC file and missing CUSTOM_ID management headlines.

Existing contents are never replaced.  Member entries are added by sync."
  (interactive)
  (org-roam-organize--moc-report
   "Org-roam Organize MOC Create"
   (lambda ()
     (let* ((identity (org-roam-organize--moc-discover t))
            (file (plist-get identity :file))
            (record (org-roam-organize--registry-moc-record)))
       (if (eq (plist-get identity :status) 'ok)
           (with-current-buffer (find-file-noselect file)
             (org-with-wide-buffer
              (let* ((tree (org-element-parse-buffer))
                     (layout (org-roam-organize--moc-regions tree)))
                (org-roam-organize--moc-check-file tree identity)
                (let ((count
                       (org-roam-organize--moc-create-regions
                        tree layout)))
                  (message
                   "[INFO] MOC: %s management headlines created."
                   count)
                  (list :status 'ok :created count)))))
         (let*
             ((template
               (org-roam-organize--record-moc-capture-template
                record))
              (request (org-roam-organize--moc-node-provider record))
              (file-head
               (nth 2 (plist-get (nthcdr 4 template) :target)))
              ;; Protect structural file metadata during native capture expansion.
              ;; Choose a marker absent from the original head to avoid collisions.
              (percent-marker
               (let ((marker "__ORGANIZE_LITERAL_PERCENT__"))
                 (while (string-match-p
                         (regexp-quote marker) file-head)
                   (setq marker (concat marker "_")))
                 marker))
              (title-marker (concat percent-marker "_TITLE"))
              (capture-head
               (let ((capture-record
                      (plist-put
                       (copy-sequence record)
                       :moc-title title-marker)))
                 (replace-regexp-in-string
                  "^#\\+FILETAGS:.*$"
                  (lambda (line)
                    (replace-regexp-in-string "%" percent-marker line
                                              t t))
                  (org-roam-organize--record-moc-head capture-record)
                  t t)))
              (body
               (mapconcat (lambda (item)
                            (org-roam-organize--moc-region-text
                             item 1))
                          (org-roam-organize--moc-records)
                          "\n"))
              (org-roam-db-update-on-save nil)
              (org-capture-prepare-finalize-hook
               (cons
                (lambda ()
                  (unless (org-roam-organize--capture-aborted-p)
                    (save-restriction
                      (widen)
                      (save-excursion
                        (goto-char (point-min))
                        (unless (re-search-forward (concat
                                                    "^#\\+TITLE: "
                                                    (regexp-quote
                                                     title-marker)
                                                    "$")
                                                   nil t)
                          (user-error
                           "MOC capture lost its literal file-title marker"))
                        (replace-match (concat
                                        "#+TITLE: "
                                        (plist-get request :title))
                                       t t)
                        (goto-char (point-min))
                        (while (re-search-forward "^#\\+FILETAGS:.*$"
                                                  nil t)
                          (replace-match
                           (save-match-data
                             (replace-regexp-in-string
                              (regexp-quote percent-marker)
                              "%"
                              (match-string-no-properties 0)
                              t
                              t))
                           t t)))
                      (goto-char (point-max))
                      (unless (bolp)
                        (insert "\n"))
                      ;; Literal metadata must not expand %t or ${field}.
                      (insert body))))
                org-capture-prepare-finalize-hook))
              finalized)
           (org-roam-organize--moc-check-new-region-titles
            (org-roam-organize--moc-records)
            file-head)
           (setf (nth 2 (plist-get (nthcdr 4 template) :target))
                 capture-head)
           ;; The fixed target is safe and absent after discovery preflight.
           ;; Org capture otherwise visits a read-only buffer for missing parents.
           (make-directory (file-name-directory file) t)
           ;; Insert literal regions before the one capture finalization/save.
           (org-roam-organize--capture-node
            (plist-get request :title)
            template
            nil
            (list :immediate-finish t)
            nil
            (lambda () (setq finalized t))
            (org-roam-organize--record-moc-id record))
           (unless finalized
             (user-error "MOC capture did not finalize successfully"))
           (org-roam-db-update-file file)
           (message
            "[INFO] Created one MOC file with %s management headlines."
            (length (org-roam-organize--moc-records)))
           (list
            :status 'ok
            :created (length (org-roam-organize--moc-records)))))))))

;;;###autoload
(defun org-roam-organize-moc-sync ()
  "Sync level-0 members in the unique MOC's independent CUSTOM_ID regions.

Validate the complete structure before editing, parse the MOC document once,
then save and update the DB at most once.  Missing regions are reported; sync
never creates them.  Cite retains its separate file synchronization wrapper."
  (interactive)
  (org-roam-organize--moc-report
   "Org-roam Organize MOC Sync"
   (lambda ()
     (let* ((identity (org-roam-organize--moc-discover))
            (file (plist-get identity :file))
            (batch
             (with-current-buffer (find-file-noselect file)
               (org-with-wide-buffer
                (let* ((tree (org-element-parse-buffer))
                       (layout (org-roam-organize--moc-regions tree)))
                  (org-roam-organize--moc-check-file tree identity)
                  (org-roam-organize--moc-sync-buffer layout file)))))
            (results (plist-get batch :results))
            (failed 0)
            (duplicates 0)
            (removed 0)
            (malformed 0)
            lines)
       (dolist (result results)
         (let ((name
                (org-roam-organize--record-name
                 (plist-get result :record))))
           (if (eq (plist-get result :status) 'failed)
               (progn
                 (setq failed (1+ failed))
                 (push (format "%s: %s"
                               name
                               (plist-get result :reason))
                       lines))
             (dolist (key '(:duplicates :removed :malformed))
               (when (plist-get result key)
                 (push (format "%s %s: %S"
                               name
                               key
                               (plist-get result key))
                       lines)))))
         (setq
          duplicates (+ duplicates (length (plist-get result :duplicates)))
          removed (+ removed (length (plist-get result :removed)))
          malformed (+ malformed (length (plist-get result :malformed)))))
       (let
           ((summary
             (format
              "[INFO] MOC sync: %s records synced, %s failed, %s duplicate ids, %s removed entries, %s malformed entries, %s files saved."
              (- (length results) failed)
              failed
              duplicates
              removed
              malformed
              (if (plist-get batch :saved)
                  1
                0))))
         (when lines
           (org-roam-organize--display-report
            "Org-roam Organize MOC Sync"
            (append (nreverse lines) (list summary))))
         (message "%s"
                  (if lines
                      (org-roam-organize--report-notice
                       'warning summary)
                    summary)))
       (append
        (list
         :status
         (if (> failed 0)
             'partial
           'ok))
        batch)))))

(provide 'org-roam-organize-moc)
;;; org-roam-organize-moc.el ends here
