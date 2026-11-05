;;; ert.el --- Managed citation export tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Real Org Cite exports against temporary Org-roam metadata and bibliography.

;;; Code:
(require 'ert)
(require 'cl-lib)
(require 'ox-ascii)
(require 'ox-latex)
(require 'oc-basic)
(require 'oc-biblatex)
(require 'org-roam-organize)

(defconst org-roam-organize-cite-export-test--ids
  '("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
    "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
    "ffffffff-ffff-4fff-8fff-ffffffffffff")
  "Fixture identities: first, shared, uncited, missing, multiple, no bibliography.")

(defun org-roam-organize-cite-export-test--node
    (root index refs bibliography)
  "Write fixture INDEX under ROOT using REFS and BIBLIOGRAPHY."
  (let ((file (expand-file-name (format "%s/ref.org" index) root)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file
      (insert
       (format ":PROPERTIES:\n:ID: %s\n"
               (nth index org-roam-organize-cite-export-test--ids)))
      (when refs
        (insert ":ROAM_REFS: " refs "\n"))
      (when bibliography
        (insert ":BIBLIOGRAPHY: " bibliography "\n"))
      (insert
       (format ":END:\n#+title: Reference %s\n#+filetags: :ref:\n"
               index)))))

(defun org-roam-organize-cite-export-test--bib (file)
  "Write bibliography fixture FILE."
  (make-directory (file-name-directory file) t)
  (with-temp-file file
    (dolist (key '("key-a" "key-b" "key-c" "ordinary" "new-key"))
      (insert
       (format
        "@article{%s,\n author={Example, Alice},\n title={Title %s},\n year={2026}\n}\n"
        key key)))))

(defmacro org-roam-organize-cite-export-test--with-database
    (&rest body)
  "Run BODY with isolated metadata, files and installed integrations."
  (declare (indent 0) (debug t))
  `(let* ((root (make-temp-file "organize-cite-export-" t))
          (default-directory (file-name-as-directory root))
          (org-roam-directory default-directory)
          (org-roam-organize-directory default-directory)
          (org-roam-db-location (expand-file-name "roam.db" root))
          (org-id-locations-file (expand-file-name "ids" root))
          (org-roam-db-update-on-save nil)
          (org-roam-organize-mode t)
          (org-roam-organize-registry
           (copy-tree
            '((:name
               "maps"
               :tag "map"
               :moc t
               :basic t
               :directory "moc"
               :template
               ((keywords . ((filetags . ("map"))))))
              (:name
               "literature"
               :tag "ref"
               :cite t
               :bibliography t))))
          (org-cite-global-bibliography nil)
          (org-export-use-babel nil)
          (org-export-filter-parse-tree-functions nil)
          (org-export-filter-final-output-functions nil)
          (shared (expand-file-name "0/reference.bib" root))
          (uncited (expand-file-name "2/uncited.bib" root))
          (explicit (expand-file-name "explicit.bib" root)))
     (unwind-protect
         (progn
           (org-roam-organize-cite-export-test--node
            root 0 "@key-a" "reference.bib")
           (org-roam-organize-cite-export-test--node
            root 1 "@key-b" "../0/reference.bib")
           (org-roam-organize-cite-export-test--node
            root 2 "@key-c" "uncited.bib")
           (org-roam-organize-cite-export-test--node root 3 nil nil)
           (org-roam-organize-cite-export-test--node
            root 4 "@key-a @key-b" nil)
           (org-roam-organize-cite-export-test--node
            root 5 "@ordinary" nil)
           (mapc
            #'org-roam-organize-cite-export-test--bib
            (list shared uncited explicit))
           (org-roam-db-sync)
           (org-roam-organize--setup-cite-integration)
           ,@body)
       (org-roam-organize--teardown-cite-integration)
       (when-let* ((db
                    (gethash
                     org-roam-directory org-roam-db--connection)))
         (emacsql-close db)
         (remhash org-roam-directory org-roam-db--connection))
       (delete-directory root t))))

(defun org-roam-organize-cite-export-test--citation (&rest indices)
  "Return a citation containing fixture INDICES."
  (concat
   "[cite:"
   (mapconcat (lambda (index)
                (concat
                 "@"
                 (nth index org-roam-organize-cite-export-test--ids)))
              indices
              ";")
   "]"))

(defun org-roam-organize-cite-export-test--environment (text)
  "Export TEXT and return the transformed citation keys and bibliography."
  (let (observed)
    (let ((org-export-filter-parse-tree-functions
           (list
            (lambda (tree _backend info)
              (org-roam-organize--cite-export-filter tree nil info)
              (setq
               observed
               (list
                (org-roam-organize--cite-reference-keys-in-parse-tree
                 tree)
                (copy-sequence (plist-get info :bibliography))))
              tree))))
      (org-export-string-as text 'ascii))
    observed))

(ert-deftest
    org-roam-organize-cite-export-test-native-standard-equivalence
    ()
  (org-roam-organize-cite-export-test--with-database
    (dolist (backend '(ascii latex))
      (dolist (print '(nil t))
        (dolist (body-only '(nil t))
          (let* ((processor
                  (if (eq backend 'latex)
                      "biblatex"
                    "basic"))
                 (header
                  (format "#+title: Equivalent\n#+cite_export: %s\n"
                          processor))
                 (tail
                  (if print
                      "\n#+print_bibliography:\n"
                    ""))
                 (managed
                  (org-export-string-as
                   (concat
                    header
                    "\n"
                    (org-roam-organize-cite-export-test--citation 0)
                    tail)
                   backend body-only))
                 (standard
                  (let ((org-roam-organize-mode nil))
                    (org-export-string-as
                     (concat
                      header
                      "#+bibliography: "
                      shared
                      "\n\n[cite:@key-a]"
                      tail)
                     backend body-only))))
            ;; Both documents use the same bibliography and citation semantics.
            (should (equal managed standard))
            (when (eq backend 'latex)
              (should (string-search "\\autocite{key-a}" managed))
              (should
               (eq
                (not (null print))
                (not
                 (null
                  (string-search "\\printbibliography" managed))))))
            (when (and (eq backend 'latex) (not body-only))
              (should
               (string-search "\\usepackage{biblatex}" managed))
              (should
               (string-search
                (format "\\addbibresource{%s}"
                        shared)
                managed)))))))))

(ert-deftest
    org-roam-organize-cite-export-test-scoped-paths-and-mixed-keys
    ()
  (org-roam-organize-cite-export-test--with-database
    (let ((result
           (org-roam-organize-cite-export-test--environment
            (concat
             (org-roam-organize-cite-export-test--citation 0 1 0)
             " [cite:@ordinary]"))))
      (should (equal (car result) '("key-a" "key-b" "ordinary")))
      (should (equal (cadr result) (list shared))))
    (should
     (equal
      (cadr
       (org-roam-organize-cite-export-test--environment
        (org-roam-organize-cite-export-test--citation 0 2)))
      (sort (list shared uncited) #'string<)))
    (should
     (equal
      (cadr
       (org-roam-organize-cite-export-test--environment
        (org-roam-organize-cite-export-test--citation 2)))
      (list uncited)))
    (should-not
     (cadr
      (org-roam-organize-cite-export-test--environment
       "No citations.")))))

(ert-deftest
    org-roam-organize-cite-export-test-preserves-native-bibliographies
    ()
  (org-roam-organize-cite-export-test--with-database
    (let ((org-cite-global-bibliography (list explicit)))
      ;; An explicitly declared managed file survives even without its UUID.
      (should
       (equal
        (cadr
         (org-roam-organize-cite-export-test--environment
          (concat
           "#+bibliography: "
           uncited
           "\n\n"
           (org-roam-organize-cite-export-test--citation 0))))
        (list uncited explicit shared)))
      (should
       (equal
        (cadr
         (org-roam-organize-cite-export-test--environment
          (concat "#+bibliography: " uncited "\n\nNo citations.")))
        (list uncited explicit)))
      ;; Missing node metadata can use a standard bibliography.
      (should
       (equal
        (cadr
         (org-roam-organize-cite-export-test--environment
          (org-roam-organize-cite-export-test--citation 5)))
        (list explicit))))))

(ert-deftest
    org-roam-organize-cite-export-test-opt-out-keeps-uuid-conversion
    ()
  (org-roam-organize-cite-export-test--with-database
    (org-roam-organize--teardown-cite-integration)
    (dolist (option '(nil missing))
      (setf (plist-get
             (cadr org-roam-organize-registry)
             :bibliography)
            nil)
      (when (eq option 'missing)
        (setf (cdr org-roam-organize-registry)
              '((:name "literature" :tag "ref" :cite t))))
      (org-roam-organize--setup-cite-integration)
      (let ((org-cite-global-bibliography (list explicit)))
        (should
         (equal
          (org-roam-organize-cite-export-test--environment
           (org-roam-organize-cite-export-test--citation 0))
          (list '("key-a") (list explicit))))
        (let ((output
               (org-export-string-as
                (concat
                 "#+cite_export: basic\n"
                 (org-roam-organize-cite-export-test--citation 0)
                 "\n#+print_bibliography:\n")
                'ascii)))
          (should (string-search "Title key-a" output))))
      (org-roam-organize--teardown-cite-integration))))

(ert-deftest
    org-roam-organize-cite-export-test-preprocessing-and-exclusions
    ()
  (org-roam-organize-cite-export-test--with-database
    (should
     (equal
      (cadr
       (org-roam-organize-cite-export-test--environment
        (concat
         "* Exported\n"
         (org-roam-organize-cite-export-test--citation 0)
         "\n* Hidden :noexport:\n"
         (org-roam-organize-cite-export-test--citation 2 3))))
      (list shared)))
    (with-temp-file (expand-file-name "included.org" root)
      (insert (org-roam-organize-cite-export-test--citation 2)))
    (should
     (equal
      (cadr
       (org-roam-organize-cite-export-test--environment
        "#+include: included.org\n"))
      (list uncited)))
    (should
     (equal
      (cadr
       (org-roam-organize-cite-export-test--environment
        (concat
         "#+macro: reference "
         (org-roam-organize-cite-export-test--citation 0)
         "\n\n{{{reference}}}\n")))
      (list shared)))))

(ert-deftest
    org-roam-organize-cite-export-test-errors-restore-discovery
    ()
  (org-roam-organize-cite-export-test--with-database
    (cl-labels
     ((discovery
       ()
       (with-temp-buffer
         (org-mode)
         (should
          (equal
           (org-cite-list-bibliography-files)
           (sort (list shared uncited) #'string<)))
         (should-not org-roam-organize--cite-export-in-progress))))
     (discovery)
     (org-roam-organize-cite-export-test--environment
      (org-roam-organize-cite-export-test--citation 0))
     (discovery)
     (dolist (index '(3 4))
       (should-error
        (org-roam-organize-cite-export-test--environment
         (org-roam-organize-cite-export-test--citation index))
        :type 'user-error)
       (discovery))
     (let ((org-export-before-parsing-functions
            (list (lambda (_backend) (error "Export failure")))))
       (should-error (org-export-string-as "Text" 'ascii)))
     (discovery))))

(ert-deftest
    org-roam-organize-cite-export-test-source-and-current-mapping
    ()
  (org-roam-organize-cite-export-test--with-database
    (with-temp-buffer
      (org-mode)
      (insert
       (concat
        "#+cite_export: biblatex\n"
        (org-roam-organize-cite-export-test--citation 0)))
      (set-buffer-modified-p nil)
      (let ((source (buffer-string)))
        (should
         (string-search "\\autocite{key-a}" (org-export-as 'latex)))
        (should (equal source (buffer-string)))
        (should-not (buffer-modified-p))
        (org-roam-organize-cite-export-test--node
         root 0 "@new-key" "reference.bib")
        (org-roam-db-sync)
        (should
         (string-search "\\autocite{new-key}" (org-export-as 'latex)))
        (should (equal source (buffer-string)))
        (should-not (buffer-modified-p))))))

(ert-deftest
    org-roam-organize-cite-export-test-native-acquisition-and-lifecycle
    ()
  (org-roam-organize-cite-export-test--with-database
    (org-roam-organize--setup-cite-integration)
    (let ((native (symbol-function 'org-cite-store-bibliography))
          observed)
      (cl-letf (((symbol-function 'org-cite-store-bibliography)
                 (lambda (info)
                   (funcall native info)
                   (setq observed
                         (copy-sequence
                          (plist-get info :bibliography))))))
        (org-roam-organize-cite-export-test--environment
         (org-roam-organize-cite-export-test--citation 0)))
      (should-not observed))
    (should
     (= 1
        (cl-count
         #'org-roam-organize--cite-export-filter
         org-export-filter-parse-tree-functions)))
    (org-roam-organize--teardown-cite-integration)
    (should-not
     (advice-member-p
      #'org-roam-organize--cite-around-export 'org-export-as))
    (should-not
     (advice-member-p
      #'org-roam-organize--filter-bibliography-files
      'org-cite-list-bibliography-files))
    (with-temp-buffer
      (org-mode)
      (should-not (org-cite-list-bibliography-files)))))

;;; ert.el ends here
