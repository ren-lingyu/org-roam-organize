;;; org-roam-organize-entry.el --- Managed entries for Org-roam Organize -*- lexical-binding: t; package-lint-main-file: "org-roam-organize.el"; -*-

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
      (org-element-map
       ast 'link
       (lambda (link)
         (unless link-result
           (let ((prefix
                  (buffer-substring-no-properties
                   (point-min) (org-element-property :begin link))))
             (when (and (org-roam-organize--blank-string-p prefix)
                        (string=
                         (org-element-property :type link) "id")
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

(defun org-roam-organize--parse-id-link-keyword-entries-in-tree
    (tree keyword-name &optional suffix-parser)
  "Parse KEYWORD-NAME id-link entries under Org element TREE.

Return a plist containing `:entries' and `:malformed'.  Entries are plists
with `:id', `:title', `:begin', and `:end', plus any data supplied by
SUFFIX-PARSER.

Only real keywords outside COMMENT context are considered.  Malformed lines
are retained as strings for reporting, while legal entries carry buffer
positions for later reconciliation.  TREE may be a complete document or a
headline subtree from a single Org Element parse."
  (let (entries
        malformed)
    (org-element-map
     tree 'keyword
     (lambda (keyword)
       (when (and (string=
                   (org-element-property :key keyword) keyword-name)
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
               (push
                (append parsed (list :begin begin :end end)) entries)
             (push (buffer-substring-no-properties
                    begin
                    (save-excursion
                      (goto-char begin)
                      (line-end-position)))
                   malformed))))))
    (list
     :entries (nreverse entries)
     :malformed (nreverse malformed))))

(defun org-roam-organize--parse-id-link-keyword-entries
    (keyword-name &optional suffix-parser)
  "Parse KEYWORD-NAME id-link entries in the current buffer."
  (org-roam-organize--parse-id-link-keyword-entries-in-tree
   (org-element-parse-buffer) keyword-name
   suffix-parser))

(defun org-roam-organize--inbox-headline (name)
  "Return the top-level Inbox headline element named NAME in the current buffer.

Implementation notes: this scans headline elements and accepts only the first
non-commented level-1 headline whose raw title equals NAME.  Regex matching
is avoided so source blocks, COMMENT subtrees, and nested headlines do not
become false inboxes."
  (let (inbox)
    (org-element-map
     (org-element-parse-buffer) 'headline
     (lambda (headline)
       (when (and (not inbox)
                  (= (or (org-element-property :level headline) 0) 1)
                  (string=
                   (org-element-property :raw-value headline) name)
                  (not
                   (org-roam-organize--element-commented-p headline)))
         (setq inbox headline))))
    inbox))

(defun org-roam-organize--first-child-headline-begin (headline)
  "Return the beginning position of HEADLINE's first child headline.

Implementation notes: the child search is constrained to HEADLINE's parsed
element tree.  The returned position lets insertion happen inside the Inbox
section before nested child headings."
  (let ((contents-begin
         (org-element-property :contents-begin headline))
        (end (org-element-property :end headline))
        child-begin)
    (when contents-begin
      (org-element-map
       headline 'headline
       (lambda (child)
         (when (and (not child-begin)
                    (> (org-element-property :begin child)
                       (org-element-property :begin headline)))
           (setq child-begin (org-element-property :begin child))))
       nil nil nil)
      (when (and child-begin end (< child-begin end))
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
              (contents-begin
               (org-element-property :contents-begin inbox))
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

(defun org-roam-organize--plan-id-link-keyword-entries (entries nodes)
  "Plan reconciliation of parsed ENTRIES against NODES.

Return a plist with `:edits', `:missing', `:duplicates', and `:removed'.
Each edit is a cons (ENTRY . NODE), where a nil NODE means deletion.  Edits
are ordered from the end of the buffer toward the beginning so applying them
preserves the original positions.  Missing nodes retain NODES order; duplicate
and removal reporting preserves the existing synchronization semantics.  This
function neither reads nor changes the buffer."
  (let ((node-table (make-hash-table :test 'equal))
        (seen-table (make-hash-table :test 'equal))
        edits
        missing-nodes
        duplicate-ids
        removed-ids)
    (dolist (node nodes)
      (puthash (plist-get node :id) node node-table))
    (dolist (entry entries)
      (let ((id (plist-get entry :id)))
        (if (gethash id seen-table)
            (cl-pushnew id duplicate-ids :test #'equal)
          (puthash id t seen-table))))
    (dolist (entry (reverse entries))
      (let* ((id (plist-get entry :id))
             (node (gethash id node-table)))
        (unless node
          (push id removed-ids))
        (push (cons entry node) edits)))
    (dolist (node nodes)
      (unless (gethash (plist-get node :id) seen-table)
        (push node missing-nodes)))
    (list
     :edits (nreverse edits)
     :missing (nreverse missing-nodes)
     :duplicates (nreverse duplicate-ids)
     :removed (nreverse removed-ids))))

(defun org-roam-organize--apply-id-link-keyword-entry-plan
    (keyword-name plan &optional suffix-builder)
  "Apply PLAN's existing-entry edits for KEYWORD-NAME in the current buffer.

SUFFIX-BUILDER receives the existing entry after its old text is deleted.
The caller owns parsing, insertion of missing nodes, and file lifecycle.
This function neither parses the buffer nor chooses an insertion region."
  (dolist (edit (plist-get plan :edits))
    (let* ((entry (car edit))
           (node (cdr edit))
           (begin (plist-get entry :begin))
           (end (plist-get entry :end)))
      (goto-char begin)
      (if node
          (progn
            (delete-region begin end)
            (insert
             (org-roam-organize--id-link-keyword-entry-line
              keyword-name
              (plist-get entry :id)
              (plist-get node :title)
              (when suffix-builder
                (funcall suffix-builder entry)))))
        (delete-region begin end)))))

(defun org-roam-organize--insert-id-link-keyword-entries
    (keyword-name nodes position)
  "Insert KEYWORD-NAME entries for NODES at POSITION in the current buffer.

POSITION is a buffer position or marker chosen by the caller.  NODES retain
their input order.  A position retained across preceding entry edits should
use a marker with insertion type t so replacements at that boundary remain
before the new entries.  This function does not parse, locate headlines, or
save."
  (goto-char position)
  (dolist (node nodes)
    (insert
     (org-roam-organize--id-link-keyword-entry-line
      keyword-name (plist-get node :id) (plist-get node :title)))))

(defun org-roam-organize--sync-id-link-keyword-entries-in-buffer
    (keyword-name
     nodes inbox-name &optional suffix-parser suffix-builder)
  "Sync KEYWORD-NAME entries from NODES in the current buffer.

Parse entries, plan reconciliation, and apply changes without saving the file.
This compatibility wrapper retains the global Inbox policy: after existing
entries are edited, locate or create the Inbox for missing nodes.  That lookup
may parse the modified buffer again.  Region-aware callers can instead reuse
the tree parser, planner, edit helper, and explicit-position insertion helper.
Return a plist with duplicate ids, removed ids, and malformed entry lines."
  (let* ((parse-result
          (org-roam-organize--parse-id-link-keyword-entries
           keyword-name
           suffix-parser))
         (plan
          (org-roam-organize--plan-id-link-keyword-entries
           (plist-get parse-result :entries) nodes)))
    (org-roam-organize--apply-id-link-keyword-entry-plan
     keyword-name plan
     suffix-builder)
    (when (plist-get plan :missing)
      (org-roam-organize--insert-id-link-keyword-entries
       keyword-name
       (plist-get plan :missing)
       (org-roam-organize--inbox-insertion-point inbox-name)))
    (list
     :duplicates (plist-get plan :duplicates)
     :removed (plist-get plan :removed)
     :malformed (plist-get parse-result :malformed))))

(defun org-roam-organize--sync-id-link-keyword-entries
    (keyword-name
     path
     nodes
     inbox-name
     &optional
     suffix-parser
     suffix-builder
     record
     missing-reason)
  "Sync id-link KEYWORD-NAME entries at PATH from NODES.

Existing legal entries keep their relative position.  Duplicate entries are
all synchronized and reported.  Entries whose ids are no longer in NODES are
removed.  Missing nodes are appended under the Inbox headline.

Implementation notes: the file wrapper retains the missing-file diagnostics
and save behavior.  The buffer-local synchronizer separates parsing,
reconciliation, and edits from file opening and saving.  SUFFIX-PARSER and
SUFFIX-BUILDER retain their keyword-specific meanings."
  (if (not (and path (file-exists-p path)))
      (list
       :status 'failed
       :record record
       :reason (or missing-reason "Target file does not exist"))
    (with-current-buffer (find-file-noselect path)
      (let
          ((result
            (org-roam-organize--sync-id-link-keyword-entries-in-buffer
             keyword-name nodes inbox-name
             suffix-parser suffix-builder)))
        (save-buffer)
        (append (list :status 'ok :record record) result)))))

(provide 'org-roam-organize-entry)
;;; org-roam-organize-entry.el ends here
