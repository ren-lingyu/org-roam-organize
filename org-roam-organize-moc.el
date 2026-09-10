;;; org-roam-organize-moc.el --- MOC management for Org-roam Organize -*- lexical-binding: t; package-lint-main-file: "org-roam-organize.el"; -*-

;;; Commentary:

;; This internal module parses, creates, and synchronizes managed MOC files.

;;; Code:

(require 'org-roam-organize-core)
(require 'org-roam-organize-capture)
(require 'org-roam-organize-entry)

(defvar org-roam-organize-mode)

(defun org-roam-organize--moc-node-id-by-path (path)
  "Return the level-0 Org-roam node id for absolute file PATH.

Implementation notes: the query looks up the `nodes' table by exact absolute
file path and requires level 0 so headline nodes do not masquerade as MOC
file nodes.  The SQL form is built with `vector' syntax for consistency with
dynamic EmacSQL query construction."
  (caar
   (org-roam-db-query
    (vector :select (vector 'n:id)
            :from '(as nodes n)
            :where '(and (= n:level 0) (= n:file $s1)))
    path)))

(defun org-roam-organize--registry-tag-id-alist ()
  "Return an alist of managed tag to MOC node id from registry records.

Implementation notes: each registry record is resolved to its MOC path, then
looked up in the Org-roam database.  The result cons keeps successful
TAG . ID pairs in the car and unresolved records in the cdr so callers can
distinguish partial failure from an empty registry."
  (let (output missing-records)
    (dolist (record org-roam-organize-registry)
      (let* ((tag (org-roam-organize--record-tag record))
             (path (org-roam-organize--record-absolute-moc-path record))
             (id (when path
                   (org-roam-organize--moc-node-id-by-path path))))
        (if (and tag id)
            (push (cons tag id) output)
          (push record missing-records))))
    (cons (nreverse output) (nreverse missing-records))))

(defun org-roam-organize--moc-node-entry-line (id title &optional delete)
  "Return a MOC node entry line for ID, TITLE, and DELETE flag.

Implementation notes: this is the MOC-specific wrapper around
`org-roam-organize--id-link-keyword-entry-line'.  It fixes the keyword name
to `org-roam-organize--moc-node-keyword' and serializes the existing
`:delete t' marker when requested."
  (org-roam-organize--id-link-keyword-entry-line
   org-roam-organize--moc-node-keyword
   id
   title
   (when delete " :delete t")))

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
      (error nil))))

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
     (list :delete
           (org-roam-organize--moc-node-entry-delete-p suffix)))))

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
     (list :delete
           (org-roam-organize--moc-node-entry-delete-p suffix)))))

(defun org-roam-organize--moc-managed-property-put (property value)
  "Set top-level MOC PROPERTY to VALUE in the current buffer.

Implementation notes: the function works only at the file top.  It creates a
property drawer if necessary, updates an existing property line inside the
drawer when found, or inserts a new property before `:END:'."
  (let ((property (upcase property))
        (value (format "%s" value)))
    (save-excursion
      (goto-char (point-min))
      (unless (looking-at-p ":PROPERTIES:")
        (insert ":PROPERTIES:\n:END:\n"))
      (goto-char (point-min))
      (let ((drawer-end
             (save-excursion
               (when (re-search-forward "^:END:[ \t]*$" nil t)
                 (line-beginning-position)))))
        (if (not drawer-end)
            (progn
              (goto-char (point-min))
              (insert ":PROPERTIES:\n:END:\n")
              (org-roam-organize--moc-managed-property-put property value))
          (if (re-search-forward
               (format "^:%s:[ \t]*.*$" (regexp-quote property))
               drawer-end t)
              (replace-match (format ":%s: %s" property value) t t)
            (goto-char drawer-end)
            (insert (format ":%s: %s\n" property value))))))))

(defun org-roam-organize--moc-update-managed-information (record nodes)
  "Update managed information in RECORD's MOC file for NODES.

Implementation notes: derived metadata is written after a successful sync.
The MOC file is opened non-interactively, the managed tag and node count
properties are updated through the drawer helper, then the buffer is saved."
  (let ((path (org-roam-organize--record-absolute-moc-path record))
        (tag (org-roam-organize--record-tag record)))
    (when (and path tag (file-exists-p path))
      (with-current-buffer (find-file-noselect path)
        (org-roam-organize--moc-managed-property-put
         org-roam-organize-moc-managed-tag-property
         tag)
        (org-roam-organize--moc-managed-property-put
         org-roam-organize-moc-managed-node-count-property
         (length nodes))
        (save-buffer)))))

(defun org-roam-organize--moc-sync-node-entries (record nodes)
  "Sync MOC node entries for RECORD from NODES.

Existing legal entries keep their relative position.  Duplicate entries are
all synchronized and reported.  Entries whose ids are no longer in NODES are
removed.  Missing nodes are appended under the Inbox headline.

Implementation notes: this MOC-specific wrapper delegates the shared
id-link-keyword synchronization work to
`org-roam-organize--sync-id-link-keyword-entries'.  It supplies the
`#+ROAM_NODE' keyword, the record's MOC file path, the record's inbox
headline name, and MOC suffix handlers that preserve the existing
`:delete t' marker."
  (org-roam-organize--sync-id-link-keyword-entries
   org-roam-organize--moc-node-keyword
   (org-roam-organize--record-absolute-moc-path record)
   nodes
   (org-roam-organize--record-inbox record)
   (lambda (suffix)
     (list :delete
           (org-roam-organize--moc-node-entry-delete-p suffix)))
   (lambda (entry)
     (when (plist-get entry :delete)
       " :delete t"))
   record
   "MOC file does not exist"))

;; ==============================
;; 可调用功能函数
;; ==============================

;; 打开顶层 MOC
;;;###autoload
(defun org-roam-organize-moc-open-index ()
  "Open the top-level Map of Contents file using its file path.

Implementation notes: the top-level MOC is the single `:moc t' registry
record.  Its path is resolved through the registry helpers; the command only
opens the file when the resolved path exists and otherwise reports the
configuration or filesystem problem."
  (interactive)
  (if org-roam-organize-mode
      (let ((file_path
             (org-roam-organize--record-absolute-moc-path
              (org-roam-organize--registry-moc-record))))
        (cond
         ((not file_path)
          (message "Top MOC file path is not defined. Please check your configuration."))
         ((not (file-exists-p file_path))
          (message "Top MOC file not found at path: %s" file_path))
         (t
          (find-file file_path)
          ;; Optional enhancements (kept commented as in original)
          ;; (display-line-numbers-mode 1)
          ;; (font-lock-mode 1)
          ;; (font-lock-fontify-buffer)
          (message "[INFO] Opened Top MOC: %s" (file-name-nondirectory file_path)))))
    (message "[WARNING] This function requires org-roam-organize-mode to be enabled (current value: %s)" org-roam-organize-mode)))

;; 创建缺失的 MOC 对应的 org-roam node
;;;###autoload
(defun org-roam-organize-moc-create ()
  "Create missing MOC files declared in `org-roam-organize-registry'.

Implementation notes: every registry record gets a derived MOC path and
capture template.  Existing files are skipped, malformed records are counted
as failed, and missing files are created through the same provider request
protocol used by ordinary managed node creation.  The provider is the
internal `org-roam-organize--moc-node-provider', and the capture still uses a
single immediate-finish template generated from the registry."
  (interactive)
  (if org-roam-organize-mode
      (let ((debug-on-error t)
            (created-count 0)
            (skipped-count 0)
            (failed-count 0))
        (dolist (record org-roam-organize-registry)
          (let* ((path (org-roam-organize--record-absolute-moc-path record))
                 (template (org-roam-organize--record-moc-capture-template record))
                 (tag (org-roam-organize--record-tag record))
                 (request (org-roam-organize--moc-node-provider record)))
            (cond
             ((not (and path
                        template
                        tag
                        (org-roam-organize--node-request-valid-p request)))
              (setq failed-count (1+ failed-count))
              (message "[WARNING] Cannot create MOC for registry record: %s" record))
             ((file-exists-p path)
              (setq skipped-count (1+ skipped-count))
              (message "[INFO] MOC already exists, skipped: %s" path))
             (t
              (org-roam-organize--capture-node
               (plist-get request :title)
               template
               (plist-get request :info)
               '(:immediate-finish t))
              (setq created-count (1+ created-count))))))
        (message "[INFO] Create missing MOCs: %s created, %s skipped, %s failed."
                 created-count skipped-count failed-count))
    (message "[WARNING] This function requires org-roam-organize-mode to be enabled (current value: %s)" org-roam-organize-mode)))

;; 同步 MOC
;;;###autoload
(defun org-roam-organize-moc-sync ()
  "Sync managed MOC files from Org-roam node tags.

Implementation notes: the command refreshes access to the Org-roam database,
then walks registry records.  For each tag, matching level-0 nodes are loaded
from the DB, node entries are synchronized in the corresponding MOC file, and
derived managed properties are updated only after a successful entry sync.
Per-record failure diagnostics are collected and displayed in the report buffer;
clean runs only produce a summary message."
  (interactive)
  (if org-roam-organize-mode
      (let ((synced-count 0)
            (failed-count 0)
            (duplicate-count 0)
            (removed-count 0)
            (malformed-count 0)
            report-lines)
        (org-roam-db)
        (dolist (record org-roam-organize-registry)
          (let* ((tag (org-roam-organize--record-tag record))
                 (nodes (and (stringp tag)
                             (org-roam-organize--nodes-with-tag tag)))
                 (result (when (stringp tag)
                           (org-roam-organize--moc-sync-node-entries
                            record
                            (or nodes nil)))))
            (cond
             ((not (and (stringp tag) result))
              (setq failed-count (1+ failed-count))
              (push
               (format "[WARNING] Cannot sync MOC for registry record: %s"
                       record)
               report-lines))
             ((eq (plist-get result :status) 'failed)
              (setq failed-count (1+ failed-count))
              (push
               (format "[WARNING] Cannot sync MOC for registry record: %s (%s)"
                       record
                       (plist-get result :reason))
               report-lines))
             (t
              (org-roam-organize--moc-update-managed-information record nodes)
              (setq synced-count (1+ synced-count))
              (setq duplicate-count
                    (+ duplicate-count
                       (length (plist-get result :duplicates))))
              (setq removed-count
                    (+ removed-count
                       (length (plist-get result :removed))))
              (setq malformed-count
                    (+ malformed-count
                       (length (plist-get result :malformed))))))))
        (let ((summary
               (format
                "[INFO] Sync MOCs: %s synced, %s failed, %s duplicate ids, %s removed entries, %s malformed entries."
                synced-count failed-count duplicate-count removed-count malformed-count)))
          (if report-lines
              (progn
                (org-roam-organize--display-report
                 "Org-roam Organize MOC Sync"
                 (append (nreverse report-lines) (list summary)))
                (message "%s"
                         (org-roam-organize--report-notice
                          'warning
                          summary)))
            (message "%s" summary))))
    (message "[WARNING] This function is not valid, since org-roam-organize-mode = %s. " org-roam-organize-mode)))


(provide 'org-roam-organize-moc)
;;; org-roam-organize-moc.el ends here
