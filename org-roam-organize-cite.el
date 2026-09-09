;;; org-roam-organize-cite.el --- Citation management for Org-roam Organize -*- lexical-binding: t; -*-

;;; Commentary:

;; This internal module implements backend-independent citation discovery,
;; checking, synchronization, export, and optional integration lifecycles.

;;; Code:

(require 'org-roam-organize-core)
(require 'org-roam-organize-entry)

(defvar org-roam-organize-mode)

(declare-function org-roam-organize-cite-citar--setup
                  "org-roam-organize-cite-citar")
(declare-function org-roam-organize-cite-citar--teardown
                  "org-roam-organize-cite-citar")
(declare-function org-roam-organize-cite-biblatex--setup
                  "org-roam-organize-cite-biblatex")
(declare-function org-roam-organize-cite-biblatex--teardown
                  "org-roam-organize-cite-biblatex")
(declare-function org-roam-organize-cite-display--setup
                  "org-roam-organize-cite-display")
(declare-function org-roam-organize-cite-display--teardown
                  "org-roam-organize-cite-display")

(defun org-roam-organize--bibliography-files ()
  "Return bibliography files declared by managed citation nodes.

Read `org-roam-organize--bibliography-property' from level-0 nodes carrying
the configured citation record's tag.  Resolve each property value relative
to its node file, remove duplicate paths, and return the lexically sorted
result.  Return nil when no citation record enables `:bibliography t'.  Each
enabled call queries the Org-roam database; the function does not retain its
result, read or modify Org or bibliography files, or validate property values
or resulting paths.

Implementation notes: One `org-roam-db-query' joins `tags' to level-0 `nodes'
and selects `nodes.properties', which Org-roam returns as an alist.  Path
aggregation remains in the core package and is exposed through Org Cite during
the mode lifecycle.

Rationale: A node property makes bibliography ownership self-describing while
keeping backend-specific global customization outside the core data model."
  (let ((record (org-roam-organize--registry-cite-record)))
    (when (and record
               (org-roam-organize--record-bibliography-p record))
      (let* ((tag (org-roam-organize--record-tag record))
             (rows
              (org-roam-db-query
               (vector :select (vector 'n:file 'n:properties)
                       :from '(as tags t)
                       :join '(as nodes n)
                       :on '(and (= n:level 0) (= n:id t:node_id))
                       :where '(= t:tag $s1))
               tag)))
        (sort
         (delete-dups
          (delq
           nil
           (mapcar
            (lambda (row)
              (when-let* ((value
                           (cdr
                            (assoc org-roam-organize--bibliography-property
                                   (nth 1 row)))))
                (expand-file-name value
                                  (file-name-directory (nth 0 row)))))
            rows)))
         #'string<)))))

(defun org-roam-organize--filter-bibliography-files (files)
  "Append enabled managed citation-node bibliographies to FILES.

When `org-roam-organize-mode' is enabled in an Org-derived buffer and the
citation record sets `:bibliography t', append the paths returned by
`org-roam-organize--bibliography-files' to FILES and remove duplicates while
preserving first occurrence order.  Otherwise return FILES unchanged.
Existing Org Cite bibliography files therefore take precedence.  The function
does not validate, read, or modify any referenced file.

Implementation notes: This function is installed as `:filter-return' advice
on `org-cite-list-bibliography-files' for the mode lifecycle.  Bibliography
aggregation remains independent of the optional citation backend.

Rationale: Org Cite is the shared bibliography-discovery boundary for export
processors and consumers such as Citar, so extending it keeps the metadata
available without backend-specific dispatch changes."
  (if (and org-roam-organize-mode
           (derived-mode-p 'org-mode))
      (delete-dups
       (append files
               (org-roam-organize--bibliography-files)))
    files))

(defun org-roam-organize--setup-cite-integration ()
  "Install the configured core citation integrations.

When a citation record exists, install backend-independent managed UUID title
display in Org buffers.  Always register the managed UUID export filter.  When
the citation record sets `:bibliography t', also register the
bibliography-discovery advice and bundled BibLaTeX final-output compatibility
filter.  Repeated calls are idempotent.  Return non-nil after installation.
The registry is read when this function is called; restart
`org-roam-organize-mode' after changing it.

Implementation notes: The integrations are global and guard their behavior
with `org-roam-organize-mode'.  Buffer presentation and BibLaTeX-specific
behavior are isolated in `org-roam-organize-cite-display' and
`org-roam-organize-cite-biblatex'.  The matching teardown function removes all
installed integrations during mode disable and failed setup rollback.

Rationale: Bibliography discovery remains backend-independent, while the
presentation and version-sensitive LaTeX implementation details stay outside
the core source file."
  (when (org-roam-organize--registry-cite-record)
    (require 'org-roam-organize-cite-display)
    (org-roam-organize-cite-display--setup))
  (add-hook 'org-export-filter-parse-tree-functions
            #'org-roam-organize--cite-export-filter)
  (when (org-roam-organize--registry-cite-bibliography-p)
    (require 'org-roam-organize-cite-biblatex)
    (org-roam-organize-cite-biblatex--setup)
    (advice-add 'org-cite-list-bibliography-files
                :filter-return
                #'org-roam-organize--filter-bibliography-files))
  t)

(defun org-roam-organize--teardown-cite-integration ()
  "Remove the core citation display and export integrations.

Remove managed UUID title presentation and export filtering, plus any optional
bibliography-discovery advice and bundled BibLaTeX compatibility filter.
Return nil.  Calling this function when any integration is absent is safe."
  (when (fboundp 'org-roam-organize-cite-display--teardown)
    (org-roam-organize-cite-display--teardown))
  (remove-hook 'org-export-filter-parse-tree-functions
               #'org-roam-organize--cite-export-filter)
  (advice-remove 'org-cite-list-bibliography-files
                 #'org-roam-organize--filter-bibliography-files)
  (when (fboundp 'org-roam-organize-cite-biblatex--teardown)
    (org-roam-organize-cite-biblatex--teardown))
  nil)

(defun org-roam-organize--registry-cite-records ()
  "Return registry records marked with `:cite t'.

Implementation notes: malformed registry entries are ignored.  This helper is
used by the citation sync command to enforce command-time existence and
uniqueness without making citation support mandatory for setup validation."
  (seq-filter #'org-roam-organize--record-cite-p
              (seq-filter #'org-roam-organize--plistp
                          org-roam-organize-registry)))

(defun org-roam-organize--cite-citing-node-data (ref-node-ids)
  "Return citing-node data for citation reference node ids REF-NODE-IDS.

The return value is a plist with `:alist'.  `:alist' maps a reference node id
to a list of citing node plists containing `:id' and `:title'.

Implementation notes: UUID citation mode treats `citations.cite_key' as the
managed literature node UUID, so the query joins Org-roam `refs' and
`citations' on `refs.node_id = citations.cite_key' while requiring
`refs.type = \"cite\"'.  Only level-0 citing nodes are selected.  Duplicate
citation occurrences from the same citing node are collapsed by a
per-reference hash table."
  (let* ((rows
          (when ref-node-ids
            (org-roam-db-query
             (vector :select (vector 'r:node_id 'r:ref 'c:node_id 'n:title)
                     :from '(as refs r)
                     :join '(as citations c)
                     :on '(= r:node_id c:cite_key)
                     :join '(as nodes n)
                     :on '(and (= n:level 0) (= n:id c:node_id))
                     :where '(and (= r:type "cite")
                                  (in r:node_id $v1)))
             (vconcat ref-node-ids))))
         (ref-to-citing-table (make-hash-table :test 'equal))
         (ref-to-citing-list (make-hash-table :test 'equal))
         alist)
    (dolist (row rows)
      (let ((ref-id (nth 0 row))
            (citing-id (nth 2 row))
            (citing-title (nth 3 row)))
        (let ((citing-table
               (or (gethash ref-id ref-to-citing-table)
                   (let ((table (make-hash-table :test 'equal)))
                     (puthash ref-id table ref-to-citing-table)
                     table))))
          (unless (gethash citing-id citing-table)
            (puthash citing-id
                     (list :id citing-id
                           :title citing-title)
                     citing-table)
            (puthash ref-id
                     (cons (list :id citing-id
                                 :title citing-title)
                           (gethash ref-id ref-to-citing-list))
                     ref-to-citing-list)))))
    (maphash
     (lambda (ref-id citing-list)
       (push (cons ref-id (nreverse citing-list)) alist))
     ref-to-citing-list)
    (list :alist (nreverse alist))))

(defun org-roam-organize--cite-identity-map-data-from-rows
    (rows &optional preserve-duplicates)
  "Return bidirectional citation identity maps built from ROWS.

Each element of ROWS must contain a managed node UUID followed by an external
citekey.  Return a plist containing `:uuid-to-citekeys' and
`:citekey-to-uuids' hash tables.  Each table value is a candidate list in
first-occurrence row order.  By default, remove duplicate identity pairs; when
PRESERVE-DUPLICATES is non-nil, retain every row so callers can diagnose
duplicate database declarations.  The function does not modify ROWS or access
the database.

Implementation notes: Both directions retain candidate lists instead of
assuming a bijection.  Duplicate preservation is symmetric so both indexes
continue to describe the same database snapshot.  Citation boundaries can
therefore apply strict, tolerant, plural, or diagnostic lookup policies.

Rationale: Mapping acquisition is backend-independent, while deciding whether
missing or ambiguous identities are errors belongs to insertion, action,
activation, notes, export, and consistency-check callers."
  (let ((uuid-to-citekeys (make-hash-table :test 'equal))
        (citekey-to-uuids (make-hash-table :test 'equal)))
    (dolist (row rows)
      (let ((uuid (nth 0 row))
            (citekey (nth 1 row)))
        (when (or preserve-duplicates
                  (not (member citekey (gethash uuid uuid-to-citekeys))))
          (puthash uuid
                   (cons citekey (gethash uuid uuid-to-citekeys))
                   uuid-to-citekeys))
        (when (or preserve-duplicates
                  (not (member uuid (gethash citekey citekey-to-uuids))))
          (puthash citekey
                   (cons uuid (gethash citekey citekey-to-uuids))
                   citekey-to-uuids))))
    (maphash
     (lambda (uuid citekeys)
       (puthash uuid (nreverse citekeys) uuid-to-citekeys))
     uuid-to-citekeys)
    (maphash
     (lambda (citekey uuids)
       (puthash citekey (nreverse uuids) citekey-to-uuids))
     citekey-to-uuids)
    (list :uuid-to-citekeys uuid-to-citekeys
          :citekey-to-uuids citekey-to-uuids)))

(defun org-roam-organize--cite-managed-identity-map-data
    (tag selector &optional keys)
  "Return managed citation identity mapping data for TAG.

SELECTOR must be `all', `uuid', or `citekey'.  With `all', include every
level-0 node carrying TAG and ignore KEYS.  With `uuid' or `citekey', restrict
the result to KEYS in that identity namespace.  An empty KEYS value for a
restricted selector returns empty maps without querying the database.  Signal
an error for any other SELECTOR.  The function does not modify buffers, files,
or KEYS.

Implementation notes: One `org-roam-db-query' joins cite `refs', TAG's
managed level-0 `nodes', and their `tags'.  The query vector is constructed
with `vector'; only its `:where' expression and argument count vary by
SELECTOR.  `org-roam-organize--cite-identity-map-data-from-rows' builds both
lookup directions from the resulting `(UUID CITEKEY)' rows.

Rationale: Consumers need different query scopes but must share the same
managed-node boundary, deduplication, and bidirectional identity model."
  (let* ((where
          (pcase selector
            ('all
             '(and (= r:type "cite")
                   (= t:tag $s1)))
            ('uuid
             '(and (= r:type "cite")
                   (= t:tag $s1)
                   (in r:node_id $v2)))
            ('citekey
             '(and (= r:type "cite")
                   (= t:tag $s1)
                   (in r:ref $v2)))
            (_
             (error "Unknown citation identity selector: %S" selector))))
         (query
          (vector :select (vector 'r:node_id 'r:ref)
                  :from '(as refs r)
                  :join '(as tags t)
                  :on '(= t:node_id r:node_id)
                  :join '(as nodes n)
                  :on '(and (= n:id r:node_id) (= n:level 0))
                  :where where))
         (rows
          (cond
           ((eq selector 'all)
            (org-roam-db-query query tag))
           ((null keys)
            nil)
           (t
            (org-roam-db-query query tag (vconcat keys))))))
    (org-roam-organize--cite-identity-map-data-from-rows rows)))

(defun org-roam-organize--cite-reference-map-data (ref-nodes)
  "Return cite reference mapping data for REF-NODES.

The return value is a plist containing `:uuid-to-citekey',
`:citekey-to-uuids', `:missing', `:multiple', and `:duplicate-citekeys'.
`:uuid-to-citekey' maps managed literature node UUIDs to their external
bibliography citekeys.  `:citekey-to-uuids' maps each external citekey to the
managed UUID list that declares it.  `:missing' contains reference nodes with
no `refs.type = \"cite\"' row.  `:multiple' contains reference nodes extended
with a `:refs' list when more than one cite ref row is attached to that node.
`:duplicate-citekeys' reports external citekeys used by more than one managed
node.  Callers decide whether that diagnostic is blocking for their operation.

Implementation notes: the function queries Org-roam's `refs' table once for
all managed reference node ids and then builds hash tables in memory.  Missing
and multiple cite refs are blocking because they make UUID citation mapping
ambiguous.  Duplicate external citekeys are reported separately so global
consistency checks can require a bijection without preventing UUID-based
citation operations from applying a narrower policy."
  (let* ((ref-node-ids (mapcar (lambda (node)
                                 (plist-get node :id))
                               ref-nodes))
         (rows
          (when ref-node-ids
            (org-roam-db-query
             (vector :select (vector 'r:node_id 'r:ref)
                     :from '(as refs r)
                     :where '(and (= r:type "cite")
                                  (in r:node_id $v1)))
             (vconcat ref-node-ids))))
         (identity-map-data
          (org-roam-organize--cite-identity-map-data-from-rows rows t))
         (node-ref-table
          (plist-get identity-map-data :uuid-to-citekeys))
         (uuid-to-citekey (make-hash-table :test 'equal))
         (citekey-to-uuids (make-hash-table :test 'equal))
         missing
         multiple
         duplicate-citekeys)
    (dolist (node ref-nodes)
      (let* ((node-id (plist-get node :id))
             (refs (gethash node-id node-ref-table)))
        (cond
         ((null refs)
          (push node missing))
         ((> (length refs) 1)
          (push (append node (list :refs refs)) multiple))
         (t
          (let ((citekey (car refs)))
            (puthash node-id citekey uuid-to-citekey)
            (puthash citekey
                     (cons node-id (gethash citekey citekey-to-uuids))
                     citekey-to-uuids))))))
    (maphash
     (lambda (citekey uuids)
       (when (> (length uuids) 1)
         (push (list :citekey citekey
                     :uuids (reverse uuids))
               duplicate-citekeys)))
     citekey-to-uuids)
    (list :missing (nreverse missing)
          :multiple (nreverse multiple)
          :duplicate-citekeys (nreverse duplicate-citekeys)
          :uuid-to-citekey uuid-to-citekey
          :citekey-to-uuids citekey-to-uuids)))

(defun org-roam-organize--cite-reference-refs-valid-p (result)
  "Return non-nil when cite reference refs in RESULT are valid.

Implementation notes: RESULT is the plist returned by
`org-roam-organize--cite-reference-map-data'.  Valid means that no
managed reference node is missing a `refs.type = \"cite\"' row and none has
more than one such row."
  (and (null (plist-get result :missing))
       (null (plist-get result :multiple))))

(defun org-roam-organize--cite-reference-map-bijective-p (map-data)
  "Return non-nil when MAP-DATA describes a bijective citation mapping.

MAP-DATA must be a plist returned by
`org-roam-organize--cite-reference-map-data' or
`org-roam-organize--cite-global-reference-map-data'.  Return non-nil when
every managed reference node has exactly one citekey and every declared
citekey belongs to exactly one managed node.  This function does not access
the database or modify MAP-DATA.

Implementation notes: UUID-to-citekey totality and uniqueness are delegated
to `org-roam-organize--cite-reference-refs-valid-p'.  Citekey-to-UUID
uniqueness is represented by an empty `:duplicate-citekeys' diagnostic list.

Rationale: Global consistency checks require a true bijection, while export
and citation synchronization can continue using the weaker UUID-to-citekey
validation appropriate to their direction of lookup."
  (and (org-roam-organize--cite-reference-refs-valid-p map-data)
       (null (plist-get map-data :duplicate-citekeys))))

(defun org-roam-organize--cite-global-reference-map-data ()
  "Return global cite reference mapping data, or nil when cite is unconfigured.

Implementation notes: the function requires at most one `:cite t' registry
record, loads all level-0 nodes for that record's tag, and delegates ref table
loading to `org-roam-organize--cite-reference-map-data'.  The returned plist
therefore contains both the managed literature node list and the mapping
diagnostics derived from Org-roam's DB tables.  Citation sync, global cite
checks, and export conversion can share this loader while keeping their own
policy decisions."
  (let ((records (org-roam-organize--registry-cite-records)))
    (cond
     ((not records)
      nil)
     ((> (length records) 1)
      (user-error "Multiple :cite t registry records are configured"))
     (t
      (let* ((record (car records))
             (tag (org-roam-organize--record-tag record))
             (ref-nodes
              (and (stringp tag)
                   (org-roam-organize--nodes-with-tag tag)))
             (map-data
              (org-roam-organize--cite-reference-map-data
               ref-nodes)))
        (plist-put map-data :nodes ref-nodes))))))

(defun org-roam-organize--cite-reference-keys-in-parse-tree (parse-tree)
  "Return unique citation reference keys from PARSE-TREE.

Implementation notes: the function walks Org Element `citation-reference'
nodes and collects their `:key' properties in parse order.  A hash table is
used to avoid duplicate DB work when the same key appears more than once in
the exported document."
  (let ((seen (make-hash-table :test 'equal))
        keys)
    (org-element-map parse-tree 'citation-reference
      (lambda (reference)
        (let ((key (org-element-property :key reference)))
          (when (and (stringp key)
                     (not (gethash key seen)))
            (puthash key t seen)
            (push key keys)))))
    (nreverse keys)))

(defun org-roam-organize--cite-empty-reference-map-data ()
  "Return an empty cite reference mapping data plist.

Implementation notes: export conversion uses this value when the current
parse tree does not reference any managed literature node.  Keeping the same
plist shape as `org-roam-organize--cite-reference-map-data' lets callers use
the same hash-table lookup path without special branching."
  (list :missing nil
        :multiple nil
        :duplicate-citekeys nil
        :uuid-to-citekey (make-hash-table :test 'equal)
        :citekey-to-uuids (make-hash-table :test 'equal)
        :nodes nil))

(defun org-roam-organize--cite-export-reference-map-data-or-error (keys)
  "Return valid cite reference mapping data for managed citation KEYS.

Signal a user error when any managed literature node referenced by KEYS has
missing or multiple cite refs.  Return nil when no `:cite t' record is
configured.

Implementation notes: this export-specific policy intentionally validates
only the intersection of the current export's citation keys and the managed
literature node UUID set.  It still reuses
`org-roam-organize--cite-reference-map-data' and
`org-roam-organize--cite-reference-refs-valid-p' for table loading and
blocking validation.  Citation keys that do not match managed literature node
UUIDs are ignored so ordinary external citekeys remain exportable."
  (if (not keys)
      (org-roam-organize--cite-empty-reference-map-data)
    (let ((records (org-roam-organize--registry-cite-records)))
      (cond
       ((not records)
        nil)
       ((> (length records) 1)
        (user-error "Multiple :cite t registry records are configured"))
       (t
        (let* ((record (car records))
               (tag (org-roam-organize--record-tag record))
               (key-table (make-hash-table :test 'equal))
               selected-nodes)
          (dolist (key keys)
            (puthash key t key-table))
          (dolist (node (and (stringp tag)
                             (org-roam-organize--nodes-with-tag tag)))
            (when (gethash (plist-get node :id) key-table)
              (push node selected-nodes)))
          (let ((map-data
                 (if selected-nodes
                     (org-roam-organize--cite-reference-map-data
                      (nreverse selected-nodes))
                   (org-roam-organize--cite-empty-reference-map-data))))
            (unless (org-roam-organize--cite-reference-refs-valid-p map-data)
              (user-error
               "Cite reference validation failed for exported citations: %s missing cite refs, %s multiple cite refs"
               (length (plist-get map-data :missing))
               (length (plist-get map-data :multiple))))
            map-data)))))))

(defun org-roam-organize--cite-report-reference-map-data (map-data)
  "Return cite reference diagnostics for MAP-DATA.

Return a plist with `:valid-p' and `:lines'.  `:valid-p' is non-nil when
blocking validation passed.  `:lines' contains human-readable diagnostics.

Implementation notes: MAP-DATA is produced by
`org-roam-organize--cite-reference-map-data' or
`org-roam-organize--cite-global-reference-map-data'.  The reporting policy is
shared by `org-roam-organize-cite-check' and `org-roam-organize-cite-sync' for
missing and multiple cite refs.  Duplicate external citekeys are emitted as
separate diagnostic lines so each caller can decide whether they are blocking.
The function builds report lines instead of calling `message' so callers can
display a single final report."
  (let ((missing (plist-get map-data :missing))
        (multiple (plist-get map-data :multiple))
        (duplicate-citekeys (plist-get map-data :duplicate-citekeys))
        lines)
    (dolist (entry duplicate-citekeys)
      (push
       (format
        "[WARNING] External citekey belongs to multiple literature nodes: %s (%s)"
        (plist-get entry :citekey)
        (mapconcat #'identity
                   (plist-get entry :uuids)
                   ", "))
       lines))
    (if (not (org-roam-organize--cite-reference-refs-valid-p map-data))
        (progn
          (push
           (format
            "[WARNING] Cite reference validation failed: %s missing cite refs, %s multiple cite refs."
            (length missing)
            (length multiple))
           lines)
          (dolist (node missing)
            (push
             (format
              "[WARNING] Cite reference node has no cite ref: %s (%s)"
              (plist-get node :title)
              (plist-get node :id))
             lines))
          (dolist (node multiple)
            (push
             (format
              "[WARNING] Cite reference node has multiple cite refs: %s (%s): %s"
              (plist-get node :title)
              (plist-get node :id)
              (mapconcat #'identity
                         (plist-get node :refs)
                         ", "))
             lines))
          (list :valid-p nil :lines (nreverse lines)))
      (list :valid-p t :lines (nreverse lines)))))

(defun org-roam-organize--cite-export-filter (parse-tree _backend _info)
  "Replace managed UUID citation keys in PARSE-TREE before export.

Return the modified PARSE-TREE.  Only citation references whose `:key'
matches a managed literature node UUID are rewritten; other citation keys are
left unchanged.

Implementation notes: Org export parse-tree filters receive the complete Org
Element tree before backend rendering.  This function first collects citation
keys from the current parse tree, validates and loads cite refs only for
managed literature UUIDs that appear in that key set, then walks
`citation-reference' elements and mutates only the `:key' property with
`org-element-put-property'.  The source buffer is not edited.  The function
keeps an explicit `org-roam-organize-mode' guard because export hook variables
are global."
  (when org-roam-organize-mode
    (let* ((keys
            (org-roam-organize--cite-reference-keys-in-parse-tree
             parse-tree))
           (map-data
            (org-roam-organize--cite-export-reference-map-data-or-error
             keys))
           (uuid-to-citekey
            (plist-get map-data :uuid-to-citekey)))
      (when uuid-to-citekey
        (org-element-map parse-tree 'citation-reference
          (lambda (reference)
            (let* ((key (org-element-property :key reference))
                   (citekey (and (stringp key)
                                 (gethash key uuid-to-citekey))))
              (when citekey
                (org-element-put-property reference :key citekey))))))))
  parse-tree)

(defun org-roam-organize--cite-sync-citing-node-entries (record path nodes)
  "Sync citing-node entries for citation RECORD at PATH from NODES.

Implementation notes: this cite-specific wrapper delegates the shared
id-link-keyword synchronization work to
`org-roam-organize--sync-id-link-keyword-entries'.  It supplies the
`#+ROAM_CITING_NODE' keyword and the record's inbox headline name.  Citation
entries do not currently use suffix metadata."
  (org-roam-organize--sync-id-link-keyword-entries
   org-roam-organize--cite-citing-node-keyword
   path
   nodes
   (org-roam-organize--record-inbox record)
   nil
   nil
   record
   "Reference file does not exist"))

(defun org-roam-organize--setup-cite-backend (backend)
  "Install the optional citation adapter selected by BACKEND.

BACKEND installs the Citar adapter when it is `citar'.  A nil value selects no
adapter.  Any other value is ignored with a warning.  Signal `user-error' when
`org-roam-organize-mode' is disabled or when the selected Citar adapter cannot
be loaded or validated.  Return the installed backend symbol, or nil when no
adapter is installed.  Failure does not itself disable Org-roam Organize mode;
the mode lifecycle decides whether an adapter error is fatal.

Implementation notes: The recognized backend maps to a separate adapter
feature and setup function.  The active backend is recorded only after setup
succeeds so mode teardown does not claim ownership of a partial installation.
Unsupported values never load optional packages or claim active ownership.

Rationale: Adapter installation belongs to the mode lifecycle because advice
and third-party customization changes must have a matching teardown boundary.
Keeping failure policy in the caller lets optional integration degrade without
blocking core behavior."
  (unless org-roam-organize-mode
    (user-error "Org-roam Organize mode must be enabled"))
  (pcase backend
    ('nil
     (setq org-roam-organize--active-cite-backend nil))
    ('citar
     (unless (require 'org-roam-organize-cite-citar nil t)
       (user-error
        "Citar backend is configured, but its adapter or Citar is unavailable"))
     (org-roam-organize-cite-citar--setup)
     (setq org-roam-organize--active-cite-backend 'citar))
    (_
     (setq org-roam-organize--active-cite-backend nil)
     (message
      "[WARNING] Citation backend is not supported and was ignored: %S"
      backend)
     nil)))

(defun org-roam-organize--teardown-cite-backend ()
  "Remove the citation adapter installed by Org-roam Organize mode.

Return nil after clearing `org-roam-organize--active-cite-backend'.  This
function is valid while the mode is being disabled and therefore does not
require `org-roam-organize-mode' to be non-nil.

Implementation notes: Teardown dispatches on the recorded active backend
rather than the current customization value, which may have changed since mode
setup.

Rationale: Advice and third-party variable changes must be removed by the
component that installed them."
  (pcase org-roam-organize--active-cite-backend
    ('citar
     (when (featurep 'org-roam-organize-cite-citar)
       (org-roam-organize-cite-citar--teardown))))
  (setq org-roam-organize--active-cite-backend nil))
;; 文献引用节点条目同步
;;;###autoload
(defun org-roam-organize-cite-check ()
  "Check global managed citation reference consistency.

Implementation notes: the command refreshes the Org-roam database, loads the
single `:cite t' registry record through
`org-roam-organize--cite-global-reference-map-data', and collects the same
mapping diagnostics used by `org-roam-organize-cite-sync'.  It does not modify
Org files.  Missing or multiple cite refs and duplicate external citekeys are
all blocking validation failures because this command requires a bijection.
Detailed diagnostics are displayed in the report buffer when present; clean
runs only produce a summary message."
  (interactive)
  (if org-roam-organize-mode
      (let ((records (org-roam-organize--registry-cite-records)))
        (cond
         ((not records)
          (message "[WARNING] No :cite t registry record is configured."))
         ((> (length records) 1)
          (message "[WARNING] Multiple :cite t registry records are configured."))
         (t
          (org-roam-db)
          (let* ((map-data
                  (org-roam-organize--cite-global-reference-map-data))
                 (node-count (length (plist-get map-data :nodes)))
                 (duplicate-citekey-count
                  (length (plist-get map-data :duplicate-citekeys)))
                 (report
                  (org-roam-organize--cite-report-reference-map-data
                   map-data))
                 (bijective-p
                  (org-roam-organize--cite-reference-map-bijective-p
                   map-data))
                 (summary
                  (format
                   "[INFO] Check cite references: %s checked, %s missing cite refs, %s multiple cite refs, %s duplicate cite keys, status %s."
                   node-count
                   (length (plist-get map-data :missing))
                   (length (plist-get map-data :multiple))
                   duplicate-citekey-count
                   (if bijective-p "passed" "failed"))))
            (if (plist-get report :lines)
                (progn
                  (org-roam-organize--display-report
                   "Org-roam Organize Cite Check"
                   (append (plist-get report :lines) (list summary)))
                  (message "%s"
                           (org-roam-organize--report-notice
                            (if bijective-p 'warning 'error)
                            summary)))
              (message "%s" summary))))))
    (message "[WARNING] This function requires org-roam-organize-mode to be enabled (current value: %s)" org-roam-organize-mode)))

;; 文献引用节点条目同步
;;;###autoload
(defun org-roam-organize-cite-sync ()
  "Sync citing-node entries for managed citation reference nodes.

Implementation notes: the command requires exactly one registry record marked
with `:cite t'.  It refreshes the Org-roam database, reads every level-0 node
with that record's tag, validates that each reference node has exactly one
`refs.type = \"cite\"' row, reports duplicate external citekeys as
non-blocking data quality warnings through the shared cite reference reporter,
computes citing-node relationships from `refs' and `citations', and
synchronizes `#+ROAM_CITING_NODE' keyword entries in each reference node's
configured Inbox headline.  The sync is intentionally global so stale entries
can be removed from reference nodes that no longer have incoming citations.
Detailed citation and per-node sync diagnostics are displayed in the report
buffer when present; clean runs only produce a summary message."
  (interactive)
  (if org-roam-organize-mode
      (let ((records (org-roam-organize--registry-cite-records)))
        (cond
         ((not records)
          (message "[WARNING] No :cite t registry record is configured."))
         ((> (length records) 1)
          (message "[WARNING] Multiple :cite t registry records are configured."))
         (t
          (let ((record (car records))
                (synced-count 0)
                (failed-count 0)
                (duplicate-count 0)
                (removed-count 0)
                (malformed-count 0)
                (duplicate-citekey-count 0)
                cite-report-lines
                sync-report-lines)
            (org-roam-db)
            (let* ((tag (org-roam-organize--record-tag record))
                   (ref-nodes
                    (and (stringp tag)
                         (org-roam-organize--nodes-with-tag-and-file tag)))
                   (ref-node-ids (mapcar (lambda (node)
                                           (plist-get node :id))
                                         ref-nodes))
                   (map-data
                    (org-roam-organize--cite-reference-map-data
                     ref-nodes))
                   (report
                    (org-roam-organize--cite-report-reference-map-data
                     map-data))
                   (cite-data
                    (when (plist-get report :valid-p)
                      (org-roam-organize--cite-citing-node-data ref-node-ids)))
                   (citing-alist (plist-get cite-data :alist)))
              (setq cite-report-lines (plist-get report :lines))
              (setq duplicate-citekey-count
                    (length (plist-get map-data :duplicate-citekeys)))
              (if (not (plist-get report :valid-p))
                  (progn
                    (setq failed-count
                          (+ (length (plist-get map-data :missing))
                             (length (plist-get map-data :multiple)))))
                (dolist (ref-node ref-nodes)
                  (let* ((path (plist-get ref-node :file))
                         (citing-nodes
                          (or (cdr (assoc (plist-get ref-node :id)
                                          citing-alist))
                              nil))
                         (result
                          (org-roam-organize--cite-sync-citing-node-entries
                           record
                           path
                           citing-nodes)))
                    (cond
                     ((or (not result)
                          (eq (plist-get result :status) 'failed))
                      (setq failed-count (1+ failed-count))
                      (push
                       (format
                        "[WARNING] Cannot sync citing-node entries for node: %s (%s)"
                        ref-node
                        (plist-get result :reason))
                       sync-report-lines))
                     (t
                      (setq synced-count (1+ synced-count))
                      (setq duplicate-count
                            (+ duplicate-count
                               (length (plist-get result :duplicates))))
                      (setq removed-count
                            (+ removed-count
                               (length (plist-get result :removed))))
                      (setq malformed-count
                            (+ malformed-count
                               (length (plist-get result :malformed))))))))))
            (let ((summary
                   (format
                    "[INFO] Sync citing-node entries: %s synced, %s failed, %s duplicate ids, %s removed entries, %s malformed entries, %s duplicate cite keys."
                    synced-count failed-count duplicate-count removed-count malformed-count duplicate-citekey-count)))
              (if (or cite-report-lines sync-report-lines)
                  (progn
                    (org-roam-organize--display-report
                     "Org-roam Organize Cite Sync"
                     (append cite-report-lines
                             (nreverse sync-report-lines)
                             (list summary)))
                    (message "%s"
                             (org-roam-organize--report-notice
                              (if (> failed-count 0) 'error 'warning)
                              summary)))
                (message "%s" summary)))))))
    (message "[WARNING] This function is not valid, since org-roam-organize-mode = %s. " org-roam-organize-mode)))


(provide 'org-roam-organize-cite)
;;; org-roam-organize-cite.el ends here
