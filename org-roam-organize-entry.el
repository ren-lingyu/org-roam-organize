;;; org-roam-organize-entry.el --- Managed entries for Org-roam Organize -*- lexical-binding: t; -*-

;;; Commentary:

;; This internal module parses and synchronizes generated id-link
;; keyword entries shared by MOC and citation management.

;;; Code:

(require 'cl-lib)
(require 'org-roam-organize-core)

(defun org-roam-organize--id-link-keyword-entry-line
    (keyword id title &optional suffix)
  "Return an Org KEYWORD entry line linking to ID with TITLE.

Implementation notes: `org-link-make-string' constructs the id link so link
descriptions are escaped according to Org syntax.  Optional SUFFIX text is
appended after the link and otherwise left uninterpreted here so specialized
callers can preserve their own keyword metadata."
  (format "#+%s: %s%s\n"
          keyword
          (org-link-make-string (concat "id:" id) title)
          (or suffix "")))

(defun org-roam-organize--element-in-comment-subtree-p (element)
  "Return non-nil if ELEMENT belongs to a COMMENT subtree.

Implementation notes: Org Element nodes have parent links, so the
implementation walks ancestors until it finds a commented headline or reaches
the root."
  (let ((parent (org-element-property :parent element))
        found)
    (while (and parent (not found))
      (when (and (eq (org-element-type parent) 'headline)
                 (org-element-property :commentedp parent))
        (setq found t))
      (setq parent (org-element-property :parent parent)))
    found))

(defun org-roam-organize--element-commented-p (element)
  "Return non-nil if ELEMENT is in COMMENT context.

Implementation notes: a value is considered commented when it is itself a
commented headline or when any ancestor headline is commented.  This keeps
MOC parsing from touching COMMENT subtrees."
  (or (and (eq (org-element-type element) 'headline)
           (org-element-property :commentedp element))
      (org-roam-organize--element-in-comment-subtree-p element)))

(defun org-roam-organize--parse-id-link-keyword-entry-value
    (value &optional suffix-parser)
  "Parse an id-link keyword VALUE.

Return a plist with `:id' and `:title', plus any plist returned by
SUFFIX-PARSER.  Return nil when VALUE does not contain a valid id link at the
beginning.

Implementation notes: VALUE is parsed in a temporary Org buffer so link
syntax is handled by Org Element rather than regular expressions.  Only the
first id link with no non-whitespace prefix is accepted; text after the link
is passed to SUFFIX-PARSER when provided."
  (with-temp-buffer
    (insert value)
    (org-mode)
    (let* ((ast (org-element-parse-buffer))
           link-result)
      (org-element-map ast 'link
        (lambda (link)
          (unless link-result
            (let ((prefix (buffer-substring-no-properties
                           (point-min)
                           (org-element-property :begin link))))
              (when (and (org-roam-organize--blank-string-p prefix)
                         (string= (org-element-property :type link) "id")
                         (org-element-property :contents-begin link)
                         (org-element-property :contents-end link))
                (let* ((description
                        (buffer-substring-no-properties
                         (org-element-property :contents-begin link)
                         (org-element-property :contents-end link)))
                       (suffix
                        (buffer-substring-no-properties
                         (org-element-property :end link)
                         (point-max))))
                  (setq link-result
                        (append
                         (list
                          :id (org-element-property :path link)
                          :title description)
                         (when suffix-parser
                           (funcall suffix-parser suffix))))))))))
      link-result)))

(defun org-roam-organize--parse-id-link-keyword-entries
    (keyword-name &optional suffix-parser)
  "Parse id-link entries for KEYWORD-NAME in the current buffer.

Return a plist containing `:entries' and `:malformed'.  Entries are plists
with `:id', `:title', `:begin', and `:end', plus any data supplied by
SUFFIX-PARSER.

Implementation notes: the current buffer is parsed with Org Element and only
real keyword elements matching KEYWORD-NAME outside COMMENT context are
considered.  Malformed lines are retained as strings for reporting, while
legal entries carry buffer positions so sync can replace or remove them
later."
  (let (entries malformed)
    (org-element-map (org-element-parse-buffer) 'keyword
      (lambda (keyword)
        (when (and (string= (org-element-property :key keyword)
                            keyword-name)
                   (not
                    (org-roam-organize--element-commented-p keyword)))
          (let* ((begin (org-element-property :begin keyword))
                 (end (org-element-property :end keyword))
                 (value (org-element-property :value keyword))
                 (parsed
                  (org-roam-organize--parse-id-link-keyword-entry-value
                   value
                   suffix-parser)))
            (if parsed
                (push (append parsed
                              (list :begin begin
                                    :end end))
                      entries)
              (push (buffer-substring-no-properties
                     begin
                     (save-excursion
                       (goto-char begin)
                       (line-end-position)))
                    malformed))))))
    (list :entries (nreverse entries)
          :malformed (nreverse malformed))))

(defun org-roam-organize--inbox-headline (name)
  "Return the top-level Inbox headline element named NAME in the current buffer.

Implementation notes: this scans headline elements and accepts only the first
non-commented level-1 headline whose raw title equals NAME.  Regex matching
is avoided so source blocks, COMMENT subtrees, and nested headlines do not
become false inboxes."
  (let (inbox)
    (org-element-map (org-element-parse-buffer) 'headline
      (lambda (headline)
        (when (and (not inbox)
                   (= (or (org-element-property :level headline) 0) 1)
                   (string= (org-element-property :raw-value headline)
                            name)
                   (not
                    (org-roam-organize--element-commented-p headline)))
          (setq inbox headline))))
    inbox))

(defun org-roam-organize--first-child-headline-begin (headline)
  "Return the beginning position of HEADLINE's first child headline.

Implementation notes: the child search is constrained to HEADLINE's parsed
element tree.  The returned position lets insertion happen inside the Inbox
section before nested child headings."
  (let ((contents-begin (org-element-property :contents-begin headline))
        (end (org-element-property :end headline))
        child-begin)
    (when contents-begin
      (org-element-map headline 'headline
        (lambda (child)
          (when (and (not child-begin)
                     (> (org-element-property :begin child)
                        (org-element-property :begin headline)))
            (setq child-begin (org-element-property :begin child))))
        nil nil nil)
      (when (and child-begin
                 end
                 (< child-begin end))
        child-begin))))

(defun org-roam-organize--inbox-insertion-point (name)
  "Return the insertion point for new generated entries.

Create the level-1 Inbox headline named NAME when it is missing.

Implementation notes: existing inboxes receive new entries before their first
child headline, preserving manual subsection structure.  Missing inboxes are
appended as a level-1 headline at the end of the file."
  (let ((inbox (org-roam-organize--inbox-headline name)))
    (if inbox
        (let ((child-begin
               (org-roam-organize--first-child-headline-begin inbox))
              (contents-begin (org-element-property :contents-begin inbox))
              (end (org-element-property :end inbox)))
          (goto-char (or child-begin contents-begin end))
          (unless (bolp)
            (insert "\n"))
          (point))
      (goto-char (point-max))
      (unless (or (bobp) (bolp))
        (insert "\n"))
      (insert "* " name "\n")
      (point))))

(defun org-roam-organize--sync-id-link-keyword-entries
    (keyword-name path nodes inbox-name
                  &optional suffix-parser suffix-builder record missing-reason)
  "Sync id-link KEYWORD-NAME entries at PATH from NODES.

Existing legal entries keep their relative position.  Duplicate entries are
all synchronized and reported.  Entries whose ids are no longer in NODES are
removed.  Missing nodes are appended under the Inbox headline.

Implementation notes: NODES are indexed by id in a hash table.  Existing
entries are parsed with Org Element, using SUFFIX-PARSER for
keyword-specific metadata.  Duplicates are detected with a second hash table,
and replacements/removals run from the end of the buffer toward the beginning
so saved positions remain valid.  Missing nodes are appended after existing
edits have completed.  SUFFIX-BUILDER receives an existing parsed entry and
returns text to preserve after the regenerated id link.  MISSING-REASON lets
callers keep domain-specific failure messages while sharing the same sync
implementation."
  (let ((node-table (make-hash-table :test 'equal))
        (seen-table (make-hash-table :test 'equal))
        duplicate-ids removed-ids malformed-lines)
    (dolist (node nodes)
      (puthash (plist-get node :id) node node-table))
    (if (not (and path (file-exists-p path)))
        (list :status 'failed
              :record record
              :reason (or missing-reason "Target file does not exist"))
      (with-current-buffer (find-file-noselect path)
        (let* ((parse-result
                (org-roam-organize--parse-id-link-keyword-entries
                 keyword-name
                 suffix-parser))
               (entries (plist-get parse-result :entries)))
          (setq malformed-lines (plist-get parse-result :malformed))
          (dolist (entry entries)
            (let ((id (plist-get entry :id)))
              (if (gethash id seen-table)
                  (cl-pushnew id duplicate-ids :test #'equal)
                (puthash id t seen-table))))
          (dolist (entry (reverse entries))
            (let* ((id (plist-get entry :id))
                   (node (gethash id node-table)))
              (goto-char (plist-get entry :begin))
              (if node
                  (progn
                    (delete-region (plist-get entry :begin)
                                   (plist-get entry :end))
                    (insert
                     (org-roam-organize--id-link-keyword-entry-line
                      keyword-name
                      id
                      (plist-get node :title)
                      (when suffix-builder
                        (funcall suffix-builder entry)))))
                (push id removed-ids)
                (delete-region (plist-get entry :begin)
                               (plist-get entry :end)))))
          (let (missing-nodes)
            (dolist (node nodes)
              (unless (gethash (plist-get node :id) seen-table)
                (push node missing-nodes)))
            (when missing-nodes
              (org-roam-organize--inbox-insertion-point inbox-name)
              (dolist (node (nreverse missing-nodes))
                (insert
                 (org-roam-organize--id-link-keyword-entry-line
                  keyword-name
                  (plist-get node :id)
                  (plist-get node :title)))))))
        (save-buffer)
        (list :status 'ok
              :record record
              :duplicates (nreverse duplicate-ids)
              :removed (nreverse removed-ids)
              :malformed malformed-lines)))))

(provide 'org-roam-organize-entry)
;;; org-roam-organize-entry.el ends here
