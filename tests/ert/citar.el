;;; org-roam-organize-citar-test.el --- Tests for the Citar adapter -*- lexical-binding: t; -*-

;;; Commentary:

;; ERT tests for Org-roam Organize's optional Citar adapter.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'rx)
(require 'org-roam-organize-citar)

(defconst org-roam-organize-citar-test--uuid-a
  "11111111-1111-1111-1111-111111111111"
  "A UUID used by Citar adapter tests.")

(defconst org-roam-organize-citar-test--uuid-b
  "22222222-2222-2222-2222-222222222222"
  "A second UUID used by Citar adapter tests.")

(defconst org-roam-organize-citar-test--uuid-c
  "33333333-3333-3333-3333-333333333333"
  "A UUID used for an unmanaged database distractor.")

(defconst org-roam-organize-citar-test--uuid-d
  "44444444-4444-4444-4444-444444444444"
  "A UUID used for nested database distractors.")

(defconst org-roam-organize-citar-test--uuid-e
  "55555555-5555-5555-5555-555555555555"
  "A UUID used for a newly created managed citation node.")

(defmacro org-roam-organize-citar-test--with-adapter-context (&rest body)
  "Evaluate BODY with a valid, enabled citation adapter context.

The context enables `org-roam-organize-mode' dynamically and configures one
managed citation registry record tagged `ref'.  It does not install the Citar
adapter or access the Org-roam database unless BODY does so."
  (declare (indent 0) (debug t))
  `(let ((org-roam-organize-mode t)
         (org-roam-organize-registry
          '((:name "literature" :tag "ref" :cite t :backend citar))))
     ,@body))

(defmacro org-roam-organize-citar-test--with-database (&rest body)
  "Evaluate BODY with managed literature nodes in a temporary database.

Create a temporary Org-roam root containing two level-0 nodes tagged `ref'.
Each node has one cite ref and uses the UUID constants defined by this test
suite.  Also create a level-0 cite node with the wrong tag and a tagged nested
cite node so tests can verify the managed query boundary.  Synchronize a
temporary SQLite database before evaluating BODY."
  (declare (indent 0) (debug t))
  `(let* ((root (file-name-as-directory
                 (make-temp-file "org-roam-organize-citar-test-" t)))
          (literature-directory (expand-file-name "literature" root))
          (org-roam-directory root)
          (org-roam-organize-directory root)
          (org-roam-db-location (expand-file-name ".org-roam.db" root))
          (org-id-locations-file
           (expand-file-name ".org-id-locations" root))
          (org-roam-db-update-on-save nil))
     (make-directory literature-directory t)
     (write-region
      (format
       (concat ":PROPERTIES:\n"
               ":ID: %s\n"
               ":ROAM_REFS: @key-a\n"
               ":END:\n"
               "#+TITLE: Reference A\n"
               "#+FILETAGS: :ref:\n")
       org-roam-organize-citar-test--uuid-a)
      nil
      (expand-file-name "reference-a.org" literature-directory)
      nil
      'silent)
     (write-region
      (format
       (concat ":PROPERTIES:\n"
               ":ID: %s\n"
               ":ROAM_REFS: @key-b\n"
               ":END:\n"
               "#+TITLE: Reference B\n"
               "#+FILETAGS: :ref:\n")
       org-roam-organize-citar-test--uuid-b)
      nil
      (expand-file-name "reference-b.org" literature-directory)
      nil
      'silent)
     (write-region
      (format
       (concat ":PROPERTIES:\n"
               ":ID: %s\n"
               ":ROAM_REFS: @wrong-tag\n"
               ":END:\n"
               "#+TITLE: Unmanaged Reference\n"
               "#+FILETAGS: :other:\n")
       org-roam-organize-citar-test--uuid-c)
      nil
      (expand-file-name "wrong-tag.org" literature-directory)
      nil
      'silent)
     (write-region
      (format
       (concat "#+TITLE: Nested Reference\n"
               "#+FILETAGS: :ref:\n"
               "* Nested node\n"
               ":PROPERTIES:\n"
               ":ID: %s\n"
               ":ROAM_REFS: @nested-key\n"
               ":END:\n")
       org-roam-organize-citar-test--uuid-d)
      nil
      (expand-file-name "nested.org" literature-directory)
      nil
      'silent)
     (org-roam-db-sync)
     ,@body))

(defmacro org-roam-organize-citar-test--should-user-error (regexp form)
  "Assert that FORM signals `user-error' with a message matching REGEXP.

Evaluate FORM once.  Return non-nil when ERT observes the expected error type
and its formatted message matches REGEXP; otherwise signal a test failure."
  (declare (indent 1) (debug (form form)))
  `(let ((error-data (should-error ,form :type 'user-error)))
     (should
      (string-match-p ,regexp (error-message-string error-data)))))

(ert-deftest org-roam-organize-citar-test-requires-organize-mode ()
  (let ((org-roam-organize-mode nil))
    (should-error
     (org-roam-organize-citar--citekeys-to-uuids '("key-a"))
     :type 'user-error)))

(ert-deftest org-roam-organize-citar-test-requires-one-valid-cite-record ()
  (let ((org-roam-organize-mode t)
        (org-roam-organize-registry nil))
    (org-roam-organize-citar-test--should-user-error
        (rx "No :cite t registry record")
      (org-roam-organize-citar--cite-record-tag)))
  (let ((org-roam-organize-mode t)
        (org-roam-organize-registry
         '((:name "literature" :tag nil :cite t))))
    (org-roam-organize-citar-test--should-user-error (rx "no valid tag")
      (org-roam-organize-citar--cite-record-tag))))

(ert-deftest org-roam-organize-citar-test-maps-citekeys-to-uuids-in-order ()
  (org-roam-organize-citar-test--with-adapter-context
    (let (query-arguments)
      (cl-letf (((symbol-function 'org-roam-db-query)
                 (lambda (_query &rest arguments)
                   (setq query-arguments arguments)
                   `(("key-b" ,org-roam-organize-citar-test--uuid-b)
                     ("key-a" ,org-roam-organize-citar-test--uuid-a)))))
        (should
         (equal
          (org-roam-organize-citar--citekeys-to-uuids
           '("key-a" "key-b" "key-a"))
          (list org-roam-organize-citar-test--uuid-a
                org-roam-organize-citar-test--uuid-b
                org-roam-organize-citar-test--uuid-a)))
        (should
         (equal query-arguments
                (list "ref" ["key-a" "key-b" "key-a"])))))))

(ert-deftest org-roam-organize-citar-test-database-integration ()
  (org-roam-organize-citar-test--with-adapter-context
    (org-roam-organize-citar-test--with-database
      (should
       (equal
        (org-roam-organize-citar--citekeys-to-uuids
         '("key-b" "key-a" "key-b"))
        (list org-roam-organize-citar-test--uuid-b
              org-roam-organize-citar-test--uuid-a
              org-roam-organize-citar-test--uuid-b)))
      (should
       (equal
        (org-roam-organize-citar--uuids-to-citekeys
         (list org-roam-organize-citar-test--uuid-a
               "ordinary-key"
               org-roam-organize-citar-test--uuid-b))
        '("key-a" "ordinary-key" "key-b")))
      (require 'citar)
      (require 'citar-org)
      (org-roam-organize-citar-teardown)
      (unwind-protect
          (progn
            (org-roam-organize-citar-setup)
            (with-temp-buffer
              (org-mode)
              (citar-org-insert-citation '("key-a" "key-b"))
              (should
               (string-match-p
                (rx-to-string
                 `(seq "@" ,org-roam-organize-citar-test--uuid-a))
                (buffer-string)))
              (should
               (string-match-p
                (rx-to-string
                 `(seq "@" ,org-roam-organize-citar-test--uuid-b))
                (buffer-string)))
              (should-not (string-match-p (rx (or "key-a" "key-b"))
                                          (buffer-string))))
            (let (action-keys)
              (cl-letf (((symbol-function 'citar-run-default-action)
                         (lambda (keys)
                           (setq action-keys keys))))
                (with-temp-buffer
                  (org-mode)
                  (insert
                   (format "[cite:@%s]"
                           org-roam-organize-citar-test--uuid-a))
                  (goto-char (point-min))
                  (search-forward org-roam-organize-citar-test--uuid-a)
                  (org-roam-organize-citar-dwim))
                (should (equal action-keys '("key-a"))))))
        (org-roam-organize-citar-teardown)))))

(ert-deftest org-roam-organize-citar-test-notes-config-uses-managed-callbacks ()
  (should (eq org-roam-organize-citar--notes-source
              'org-roam-organize-citar))
  (should
   (equal org-roam-organize-citar--notes-config
          '(:name "Org-roam Organize Notes"
            :category org-roam-node
            :items org-roam-organize-citar--get-notes
            :hasitems org-roam-organize-citar--has-notes
            :open org-roam-organize-citar--open-note
            :create org-roam-organize-citar--create-note))))

(ert-deftest org-roam-organize-citar-test-citar-create-note-dispatches-callback ()
  (org-roam-organize-citar-test--with-adapter-context
    (require 'citar)
    (require 'citar-org)
    (org-roam-organize-citar-teardown)
    (let ((entry '(("title" . "Dispatched Reference")))
          received-citekey
          received-entry)
      (unwind-protect
          (progn
            (org-roam-organize-citar-setup)
            (cl-letf (((symbol-function
                        'org-roam-organize-citar--create-note)
                       (lambda (citekey callback-entry)
                         (setq received-citekey citekey
                               received-entry callback-entry)
                         'created)))
              (should (eq (citar-create-note "dispatch-key" entry)
                          'created)))
            (should (equal received-citekey "dispatch-key"))
            (should (eq received-entry entry)))
        (org-roam-organize-citar-teardown)))))

(ert-deftest org-roam-organize-citar-test-get-notes-filters-managed-database-nodes ()
  (org-roam-organize-citar-test--with-adapter-context
    (org-roam-organize-citar-test--with-database
      (let ((notes (org-roam-organize-citar--get-notes)))
        (should (= (hash-table-count notes) 2))
        (should
         (equal (gethash "key-a" notes)
                (list org-roam-organize-citar-test--uuid-a)))
        (should
         (equal (gethash "key-b" notes)
                (list org-roam-organize-citar-test--uuid-b)))
        (should-not (gethash "wrong-tag" notes))
        (should-not (gethash "nested-key" notes)))
      (let ((notes
             (org-roam-organize-citar--get-notes
              '("key-b" "wrong-tag" "nested-key" "missing"))))
        (should (= (hash-table-count notes) 1))
        (should
         (equal (gethash "key-b" notes)
                (list org-roam-organize-citar-test--uuid-b)))))))

(ert-deftest org-roam-organize-citar-test-get-notes-preserves-ambiguous-nodes ()
  (org-roam-organize-citar-test--with-adapter-context
    (cl-letf (((symbol-function 'org-roam-db-query)
               (lambda (&rest _arguments)
                 `(("key-a" ,org-roam-organize-citar-test--uuid-a)
                   ("key-a" ,org-roam-organize-citar-test--uuid-a)
                   ("key-a" ,org-roam-organize-citar-test--uuid-b)))))
      (let ((notes (org-roam-organize-citar--get-notes '("key-a"))))
        (should
         (equal (gethash "key-a" notes)
                (list org-roam-organize-citar-test--uuid-a
                      org-roam-organize-citar-test--uuid-b)))))))

(ert-deftest org-roam-organize-citar-test-has-notes-uses-one-database-snapshot ()
  (org-roam-organize-citar-test--with-adapter-context
    (org-roam-organize-citar-test--with-database
      (let ((predicate (org-roam-organize-citar--has-notes)))
        (should predicate)
        (should (funcall predicate "key-a"))
        (should (funcall predicate "key-b"))
        (should-not (funcall predicate "missing"))))))

(ert-deftest org-roam-organize-citar-test-has-notes-returns-nil-when-empty ()
  (org-roam-organize-citar-test--with-adapter-context
    (cl-letf (((symbol-function 'org-roam-db-query)
               (lambda (&rest _arguments) nil)))
      (should-not (org-roam-organize-citar--has-notes)))))

(ert-deftest org-roam-organize-citar-test-open-note-visits-node-by-uuid ()
  (org-roam-organize-citar-test--with-adapter-context
    (org-roam-organize-citar-test--with-database
      (let (visited-node)
        (cl-letf (((symbol-function 'org-roam-node-visit)
                   (lambda (node &rest _arguments)
                     (setq visited-node node)
                     'visited)))
          (should
           (eq (org-roam-organize-citar--open-note
                org-roam-organize-citar-test--uuid-a)
               'visited))
          (should
           (equal (org-roam-node-id visited-node)
                  org-roam-organize-citar-test--uuid-a))
          (should
           (equal (file-truename (org-roam-node-file visited-node))
                  (file-truename
                   (expand-file-name
                    "literature/reference-a.org"
                    org-roam-directory)))))))))

(ert-deftest org-roam-organize-citar-test-open-note-rejects-missing-node ()
  (org-roam-organize-citar-test--with-adapter-context
    (cl-letf (((symbol-function 'org-roam-node-from-id)
               (lambda (_uuid) nil)))
      (org-roam-organize-citar-test--should-user-error
          (rx "No Org-roam node for Citar note ID")
        (org-roam-organize-citar--open-note
         org-roam-organize-citar-test--uuid-a)))))

(ert-deftest org-roam-organize-citar-test-entry-title-uses-title-or-citekey ()
  (let (requested-fields requested-entry)
    (cl-letf (((symbol-function 'citar-get-field-with-value)
               (lambda (fields entry)
                 (setq requested-fields fields
                       requested-entry entry)
                 '("title" . "Reference Title"))))
      (let ((entry '(("title" . "Reference Title"))))
        (should
         (equal (org-roam-organize-citar--entry-title "key-a" entry)
                "Reference Title"))
        (should (equal requested-fields '("title")))
        (should (eq requested-entry entry)))))
  (cl-letf (((symbol-function 'citar-get-field-with-value)
             (lambda (&rest _arguments)
               '("title" . "  "))))
    (should
     (equal (org-roam-organize-citar--entry-title "key-a" '(entry))
            "key-a")))
  (should
   (equal (org-roam-organize-citar--entry-title "key-a" nil)
          "key-a")))

(ert-deftest org-roam-organize-citar-test-create-note-delegates-managed-capture ()
  (org-roam-organize-citar-test--with-adapter-context
    (let* ((record (car org-roam-organize-registry))
           (template '("n" "literature node" plain "%?"))
           (notes (make-hash-table :test 'equal))
           captured-arguments
           stored-citekey)
      (cl-letf (((symbol-function 'org-roam-organize-citar--cite-record)
                 (lambda () record))
                ((symbol-function 'org-roam-organize-citar--get-notes)
                 (lambda (citekeys)
                   (should (equal citekeys '("new-key")))
                   notes))
                ((symbol-function
                  'org-roam-organize--record-node-capture-template)
                 (lambda (selected-record)
                   (should (eq selected-record record))
                   template))
                ((symbol-function 'citar-get-field-with-value)
                 (lambda (fields entry)
                   (should (equal fields '("title")))
                   (should (equal entry '(("title" . "New Reference"))))
                   '("title" . "New Reference")))
                ((symbol-function 'org-roam-organize--capture-node)
                 (lambda (&rest arguments)
                   (setq captured-arguments arguments)
                   'capturing))
                ((symbol-function 'org-roam-organize-citar--store-cite-ref)
                 (lambda (citekey)
                   (setq stored-citekey citekey))))
        (should
         (eq (org-roam-organize-citar--create-note
              "new-key"
              '(("title" . "New Reference")))
             'capturing))
        (should (equal (nth 0 captured-arguments) "New Reference"))
        (should (eq (nth 1 captured-arguments) template))
        (should-not (nth 2 captured-arguments))
        (should (equal (nth 3 captured-arguments) '(:finalize find-file)))
        (should (eq (nth 4 captured-arguments) record))
        (should (functionp (nth 5 captured-arguments)))
        (should-not stored-citekey)
        (funcall (nth 5 captured-arguments))
        (should (equal stored-citekey "new-key"))))))

(ert-deftest org-roam-organize-citar-test-create-note-rejects-existing-nodes ()
  (org-roam-organize-citar-test--with-adapter-context
    (let ((notes (make-hash-table :test 'equal))
          capture-called)
      (puthash "key-a"
               (list org-roam-organize-citar-test--uuid-a)
               notes)
      (cl-letf (((symbol-function 'org-roam-organize-citar--get-notes)
                 (lambda (_citekeys) notes))
                ((symbol-function 'org-roam-organize--capture-node)
                 (lambda (&rest _arguments)
                   (setq capture-called t))))
        (org-roam-organize-citar-test--should-user-error
            (rx "already exists for citekey key-a")
          (org-roam-organize-citar--create-note "key-a" nil))
        (should-not capture-called)
        (puthash "key-a"
                 (list org-roam-organize-citar-test--uuid-a
                       org-roam-organize-citar-test--uuid-b)
                 notes)
        (org-roam-organize-citar-test--should-user-error
            (rx "Multiple managed literature nodes already exist"
                (* anychar)
                "key-a")
          (org-roam-organize-citar--create-note "key-a" nil))
        (should-not capture-called)))))

(ert-deftest org-roam-organize-citar-test-create-note-rejects-invalid-template ()
  (org-roam-organize-citar-test--with-adapter-context
    (let ((notes (make-hash-table :test 'equal)))
      (cl-letf (((symbol-function 'org-roam-organize-citar--get-notes)
                 (lambda (_citekeys) notes))
                ((symbol-function
                  'org-roam-organize--record-node-capture-template)
                 (lambda (_record) nil)))
        (org-roam-organize-citar-test--should-user-error
            (rx "Cannot create a managed node for citation record")
          (org-roam-organize-citar--create-note "new-key" nil))))))

(ert-deftest org-roam-organize-citar-test-create-note-finalize-persists-cite-ref ()
  (org-roam-organize-citar-test--with-adapter-context
    (org-roam-organize-citar-test--with-database
      (let* ((file (expand-file-name
                    "literature/new-reference.org"
                    org-roam-directory))
             (buffer nil)
             (notes (make-hash-table :test 'equal))
             (template '("n" "literature node" plain "%?")))
        (write-region
         (format
          (concat ":PROPERTIES:\n"
                  ":ID: %s\n"
                  ":END:\n"
                  "#+TITLE: New Reference\n"
                  "#+FILETAGS: :ref:\n")
          org-roam-organize-citar-test--uuid-e)
         nil file nil 'silent)
        (org-roam-db-update-file file)
        (setq buffer (find-file-noselect file))
        (unwind-protect
            (cl-letf (((symbol-function
                        'org-roam-organize-citar--get-notes)
                       (lambda (_citekeys) notes))
                      ((symbol-function
                        'org-roam-organize--record-node-capture-template)
                       (lambda (_record) template))
                      ((symbol-function 'citar-get-field-with-value)
                       (lambda (&rest _arguments)
                         '("title" . "New Reference")))
                      ((symbol-function 'org-roam-organize--capture-node)
                       (lambda (_title _template _info _props _record
                                success-function)
                         (with-current-buffer buffer
                           (org-mode)
                           (goto-char (point-min))
                           (funcall success-function))
                         'created)))
              (should
               (eq (org-roam-organize-citar--create-note
                    "new-key" '(("title" . "New Reference")))
                   'created))
              (should
               (equal
                (org-roam-organize-citar--citekeys-to-uuids '("new-key"))
                (list org-roam-organize-citar-test--uuid-e)))
              (with-temp-buffer
                (insert-file-contents file)
                (should
                 (string-match-p
                  (rx ":ROAM_REFS:" (* nonl) "@new-key")
                  (buffer-string)))))
          (when (buffer-live-p buffer)
            (kill-buffer buffer)))))))

(ert-deftest org-roam-organize-citar-test-create-note-rejects-empty-citekey ()
  (org-roam-organize-citar-test--with-adapter-context
    (org-roam-organize-citar-test--should-user-error
        (rx "Citar citekey cannot be empty")
      (org-roam-organize-citar--create-note "  " nil))))

(ert-deftest org-roam-organize-citar-test-store-cite-ref-saves-and-updates-database ()
  (org-roam-organize-citar-test--with-adapter-context
    (org-roam-organize-citar-test--with-database
      (let* ((file (expand-file-name
                    "literature/reference-a.org"
                    org-roam-directory))
             (buffer (find-file-noselect file)))
        (unwind-protect
            (with-current-buffer buffer
              (org-mode)
              (goto-char (point-min))
              (org-roam-organize-citar--store-cite-ref "key-extra")
              (should-not (buffer-modified-p))
              (should
               (member
                "key-extra"
                (mapcar
                 #'car
                 (org-roam-db-query
                  [:select ref :from refs :where (= node-id $s1)]
                  org-roam-organize-citar-test--uuid-a))))
              (with-temp-buffer
                (insert-file-contents file)
                (should
                 (string-match-p
                  (rx ":ROAM_REFS:" (* nonl) "@key-extra")
                  (buffer-string)))))
          (when (buffer-live-p buffer)
            (kill-buffer buffer)))))))

(ert-deftest org-roam-organize-citar-test-rejects-missing-citekey-mapping ()
  (org-roam-organize-citar-test--with-adapter-context
    (cl-letf (((symbol-function 'org-roam-db-query)
               (lambda (&rest _arguments) nil)))
      (org-roam-organize-citar-test--should-user-error
          (rx "No managed literature node for citekey")
        (org-roam-organize-citar--citekeys-to-uuids '("missing"))))))

(ert-deftest org-roam-organize-citar-test-rejects-ambiguous-citekey-mapping ()
  (org-roam-organize-citar-test--with-adapter-context
    (cl-letf (((symbol-function 'org-roam-db-query)
               (lambda (&rest _arguments)
                 `(("key-a" ,org-roam-organize-citar-test--uuid-a)
                   ("key-a" ,org-roam-organize-citar-test--uuid-b)))))
      (org-roam-organize-citar-test--should-user-error
          (rx "Citekey mapping is ambiguous")
        (org-roam-organize-citar--citekeys-to-uuids '("key-a"))))))

(ert-deftest org-roam-organize-citar-test-maps-uuids-and-preserves-ordinary-keys ()
  (org-roam-organize-citar-test--with-adapter-context
    (cl-letf (((symbol-function 'org-roam-db-query)
               (lambda (&rest _arguments)
                 `((,org-roam-organize-citar-test--uuid-b "key-b")
                   (,org-roam-organize-citar-test--uuid-a "key-a")))))
      (should
       (equal
        (org-roam-organize-citar--uuids-to-citekeys
         (list org-roam-organize-citar-test--uuid-a
               "ordinary-key"
               org-roam-organize-citar-test--uuid-b))
        '("key-a" "ordinary-key" "key-b"))))))

(ert-deftest org-roam-organize-citar-test-rejects-unmapped-uuid ()
  (org-roam-organize-citar-test--with-adapter-context
    (cl-letf (((symbol-function 'org-roam-db-query)
               (lambda (&rest _arguments) nil)))
      (org-roam-organize-citar-test--should-user-error
          (rx "No external citekey for managed UUID")
        (org-roam-organize-citar--uuids-to-citekeys
         (list org-roam-organize-citar-test--uuid-a))))))

(ert-deftest org-roam-organize-citar-test-rejects-ambiguous-uuid-mapping ()
  (org-roam-organize-citar-test--with-adapter-context
    (cl-letf (((symbol-function 'org-roam-db-query)
               (lambda (&rest _arguments)
                 `((,org-roam-organize-citar-test--uuid-a "key-a")
                   (,org-roam-organize-citar-test--uuid-a "key-b")))))
      (org-roam-organize-citar-test--should-user-error
          (rx "UUID mapping is ambiguous")
        (org-roam-organize-citar--uuids-to-citekeys
         (list org-roam-organize-citar-test--uuid-a))))))

(ert-deftest org-roam-organize-citar-test-filter-insert-args-preserves-tail ()
  (org-roam-organize-citar-test--with-adapter-context
    (cl-letf (((symbol-function
                'org-roam-organize-citar--citekeys-to-uuids)
               (lambda (citekeys)
                 (should (equal citekeys '("key-a")))
                 (list org-roam-organize-citar-test--uuid-a))))
      (should
       (equal
        (org-roam-organize-citar--filter-org-insert-args
         '(("key-a") prefix suffix))
        (list (list org-roam-organize-citar-test--uuid-a)
              'prefix
              'suffix))))))

(ert-deftest org-roam-organize-citar-test-filter-selected-key-preserves-shape ()
  (org-roam-organize-citar-test--with-adapter-context
    (cl-letf (((symbol-function
                'org-roam-organize-citar--citekeys-to-uuids)
               (lambda (citekeys)
                 (mapcar
                  (lambda (citekey)
                    (if (equal citekey "key-a")
                        org-roam-organize-citar-test--uuid-a
                      org-roam-organize-citar-test--uuid-b))
                  citekeys))))
      (should-not (org-roam-organize-citar--filter-selected-key nil))
      (should
       (equal (org-roam-organize-citar--filter-selected-key "key-a")
              org-roam-organize-citar-test--uuid-a))
      (should
       (equal (org-roam-organize-citar--filter-selected-key
               '("key-a" "key-b"))
              (list org-roam-organize-citar-test--uuid-a
                    org-roam-organize-citar-test--uuid-b)))
      (org-roam-organize-citar-test--should-user-error
          (rx "Unexpected Citar Org selection result")
        (org-roam-organize-citar--filter-selected-key 1)))))

(ert-deftest org-roam-organize-citar-test-dwim-translates-before-action ()
  (org-roam-organize-citar-test--with-adapter-context
    (let (action-keys citation-called)
      (cl-letf (((symbol-function 'citar-key-at-point)
                 (lambda () org-roam-organize-citar-test--uuid-a))
                ((symbol-function 'citar-citation-at-point)
                 (lambda ()
                   (setq citation-called t)
                   nil))
                ((symbol-function
                  'org-roam-organize-citar--uuids-to-citekeys)
                 (lambda (keys)
                   (should
                    (equal keys
                           (list org-roam-organize-citar-test--uuid-a)))
                   '("key-a")))
                ((symbol-function 'citar-run-default-action)
                 (lambda (keys)
                   (setq action-keys keys))))
        (org-roam-organize-citar-dwim)
        (should (equal action-keys '("key-a")))
        (should-not citation-called)))))

(ert-deftest org-roam-organize-citar-test-dwim-rejects-missing-citation ()
  (org-roam-organize-citar-test--with-adapter-context
    (cl-letf (((symbol-function 'citar-key-at-point) (lambda () nil))
              ((symbol-function 'citar-citation-at-point) (lambda () nil)))
      (org-roam-organize-citar-test--should-user-error
          (rx "No citation keys found")
        (org-roam-organize-citar-dwim)))))

(ert-deftest org-roam-organize-citar-test-runtime-capabilities-exist ()
  (org-roam-organize-citar-test--with-adapter-context
    (require 'citar)
    (require 'citar-org)
    (let ((result
           (org-roam-organize--check-capabilities
            org-roam-organize-citar--capability-alist)))
      (ert-info ((cdr result))
        (should (car result))))))

(ert-deftest org-roam-organize-citar-test-mode-degrades-on-source-collision ()
  (let* ((root (file-name-as-directory
                (make-temp-file "org-roam-organize-citar-test-" t)))
         (default-directory temporary-file-directory)
         (org-roam-directory root)
         (org-roam-organize-directory root)
         (org-roam-organize-registry
          '((:name "maps"
             :tag "map"
             :moc t
             :basic t
             :directory "moc")
            (:name "literature"
             :tag "ref"
             :cite t
             :backend citar
             :basic t
             :directory "literature")))
         (org-roam-organize--active-cite-backend nil)
         (org-export-filter-parse-tree-functions nil)
         (org-roam-organize-mode nil)
         (foreign-config '(:name "Foreign Notes"))
         messages)
    (make-directory (expand-file-name "moc" root) t)
    (make-directory (expand-file-name "literature" root) t)
    (require 'citar)
    (require 'citar-org)
    (org-roam-organize-citar-teardown)
    (unwind-protect
        (progn
          (push (cons org-roam-organize-citar--notes-source foreign-config)
                citar-notes-sources)
          (cl-letf (((symbol-function 'message)
                     (lambda (format-string &rest arguments)
                       (push (apply #'format format-string arguments)
                             messages))))
            (org-roam-organize-mode 1)
            (should org-roam-organize-mode)
            (should-not org-roam-organize--active-cite-backend)
            (should-not org-roam-organize-citar--installed-p)
            (should
             (equal
              (cdr (assq org-roam-organize-citar--notes-source
                         citar-notes-sources))
              foreign-config))
            (should
             (memq #'org-roam-organize--cite-export-filter
                   org-export-filter-parse-tree-functions))
            (should-not
             (advice-member-p
              #'org-roam-organize-citar--filter-org-insert-args
              'citar-org-insert-citation))
            (should-not
             (advice-member-p
              #'org-roam-organize-citar--filter-selected-key
              'citar-org-select-key))
            (should
             (seq-some
              (lambda (message-text)
                (string-match-p
                 (rx "[WARNING] Citation backend was not installed: "
                     "Citar notes source is already registered")
                 message-text))
              messages))))
      (org-roam-organize-mode -1)
      (org-roam-organize-citar-teardown)
      (setq citar-notes-sources
            (assq-delete-all org-roam-organize-citar--notes-source
                             citar-notes-sources)))))

(ert-deftest org-roam-organize-citar-test-setup-and-teardown-own-global-state ()
  (org-roam-organize-citar-test--with-adapter-context
    (require 'citar)
    (require 'citar-org)
    (org-roam-organize-citar-teardown)
    (let ((previous-at-point (default-value 'citar-at-point-function))
          (previous-notes-source citar-notes-source))
      (unwind-protect
          (progn
            (should (org-roam-organize-citar-setup))
            (should (org-roam-organize-citar-setup))
            (should org-roam-organize-citar--installed-p)
            (should
             (advice-member-p
              #'org-roam-organize-citar--filter-org-insert-args
              'citar-org-insert-citation))
            (should
             (advice-member-p
              #'org-roam-organize-citar--filter-selected-key
              'citar-org-select-key))
            (should
             (eq (default-value 'citar-at-point-function)
                 #'org-roam-organize-citar-dwim))
            (should
             (eq citar-notes-source
                 org-roam-organize-citar--notes-source))
            (should
             (equal
              (cdr (assq org-roam-organize-citar--notes-source
                         citar-notes-sources))
              org-roam-organize-citar--notes-config)))
        (org-roam-organize-citar-teardown))
      (should-not org-roam-organize-citar--installed-p)
      (should-not
       (advice-member-p
        #'org-roam-organize-citar--filter-org-insert-args
        'citar-org-insert-citation))
      (should-not
       (advice-member-p
        #'org-roam-organize-citar--filter-selected-key
        'citar-org-select-key))
      (should
       (eq (default-value 'citar-at-point-function)
           previous-at-point))
      (should (eq citar-notes-source previous-notes-source))
      (should-not
       (assq org-roam-organize-citar--notes-source
             citar-notes-sources)))))

(ert-deftest org-roam-organize-citar-test-teardown-preserves-later-user-value ()
  (org-roam-organize-citar-test--with-adapter-context
    (require 'citar)
    (require 'citar-org)
    (org-roam-organize-citar-teardown)
    (let ((previous-at-point (default-value 'citar-at-point-function))
          (previous-notes-source citar-notes-source)
          (user-at-point (lambda () 'user-value))
          (user-notes-source 'user-notes))
      (unwind-protect
          (progn
            (org-roam-organize-citar-setup)
            (set-default 'citar-at-point-function user-at-point)
            (setq citar-notes-source user-notes-source)
            (org-roam-organize-citar-teardown)
            (should
             (eq (default-value 'citar-at-point-function)
                 user-at-point))
            (should (eq citar-notes-source user-notes-source))
            (should-not
             (assq org-roam-organize-citar--notes-source
                   citar-notes-sources)))
        (org-roam-organize-citar-teardown)
        (set-default 'citar-at-point-function previous-at-point)
        (setq citar-notes-source previous-notes-source)))))

(ert-deftest org-roam-organize-citar-test-teardown-preserves-replaced-source ()
  (org-roam-organize-citar-test--with-adapter-context
    (require 'citar)
    (require 'citar-org)
    (org-roam-organize-citar-teardown)
    (let ((previous-at-point (default-value 'citar-at-point-function))
          (previous-notes-source citar-notes-source)
          (foreign-config '(:name "Replacement Notes")))
      (unwind-protect
          (progn
            (org-roam-organize-citar-setup)
            (setcdr (assq org-roam-organize-citar--notes-source
                          citar-notes-sources)
                    foreign-config)
            (org-roam-organize-citar-teardown)
            (should-not org-roam-organize-citar--installed-p)
            (should
             (eq citar-notes-source
                 org-roam-organize-citar--notes-source))
            (should
             (equal
              (cdr (assq org-roam-organize-citar--notes-source
                         citar-notes-sources))
              foreign-config)))
        (org-roam-organize-citar-teardown)
        (setq citar-notes-sources
              (assq-delete-all org-roam-organize-citar--notes-source
                               citar-notes-sources))
        (set-default 'citar-at-point-function previous-at-point)
        (setq citar-notes-source previous-notes-source)))))

(ert-deftest org-roam-organize-citar-test-setup-rejects-notes-source-collision ()
  (org-roam-organize-citar-test--with-adapter-context
    (require 'citar)
    (require 'citar-org)
    (org-roam-organize-citar-teardown)
    (let ((previous-notes-source citar-notes-source)
          (foreign-config '(:name "Foreign Notes")))
      (unwind-protect
          (progn
            (push (cons org-roam-organize-citar--notes-source
                        foreign-config)
                  citar-notes-sources)
            (org-roam-organize-citar-test--should-user-error
                (rx "Citar notes source is already registered")
              (org-roam-organize-citar-setup))
            (should-not org-roam-organize-citar--installed-p)
            (should (eq citar-notes-source previous-notes-source))
            (should
             (equal
              (cdr (assq org-roam-organize-citar--notes-source
                         citar-notes-sources))
              foreign-config)))
        (setq citar-notes-sources
              (assq-delete-all
               org-roam-organize-citar--notes-source
               citar-notes-sources))))))

(ert-deftest org-roam-organize-citar-test-setup-rolls-back-notes-source-on-error ()
  (org-roam-organize-citar-test--with-adapter-context
    (require 'citar)
    (require 'citar-org)
    (org-roam-organize-citar-teardown)
    (let ((previous-at-point (default-value 'citar-at-point-function))
          (previous-notes-source citar-notes-source))
      (cl-letf (((symbol-function 'advice-add)
                 (lambda (&rest _arguments)
                   (error "Test advice installation failure"))))
        (should-error (org-roam-organize-citar-setup)))
      (should-not org-roam-organize-citar--installed-p)
      (should (eq citar-notes-source previous-notes-source))
      (should
       (eq (default-value 'citar-at-point-function)
           previous-at-point))
      (should-not
       (assq org-roam-organize-citar--notes-source
             citar-notes-sources))
      (should-not org-roam-organize-citar--previous-notes-source)
      (should-not org-roam-organize-citar--previous-at-point-function))))

(ert-deftest org-roam-organize-citar-test-restores-other-notes-source ()
  (org-roam-organize-citar-test--with-adapter-context
    (require 'citar)
    (require 'citar-org)
    (org-roam-organize-citar-teardown)
    (let ((citar-notes-source 'citar-org-roam)
          (citar-notes-sources
           (cons '(citar-org-roam :name "Org-Roam Notes")
                 citar-notes-sources)))
      (unwind-protect
          (progn
            (org-roam-organize-citar-setup)
            (should
             (eq citar-notes-source
                 org-roam-organize-citar--notes-source))
            (org-roam-organize-citar-teardown)
            (should (eq citar-notes-source 'citar-org-roam))
            (should (assq 'citar-org-roam citar-notes-sources))
            (should-not
             (assq org-roam-organize-citar--notes-source
                   citar-notes-sources)))
        (org-roam-organize-citar-teardown)))))

(ert-deftest org-roam-organize-citar-test-capability-failure-leaves-uninstalled ()
  (org-roam-organize-citar-test--with-adapter-context
    (require 'citar)
    (require 'citar-org)
    (org-roam-organize-citar-teardown)
    (let ((previous-at-point (default-value 'citar-at-point-function))
          (previous-notes-source citar-notes-source))
      (cl-letf (((symbol-function 'org-roam-organize--check-capabilities)
                 (lambda (_capabilities)
                   (cons nil "missing test capability"))))
        (org-roam-organize-citar-test--should-user-error
            (rx "capability check failed")
          (org-roam-organize-citar-setup)))
      (should-not org-roam-organize-citar--installed-p)
      (should
       (eq (default-value 'citar-at-point-function)
           previous-at-point))
      (should (eq citar-notes-source previous-notes-source))
      (should-not
       (assq org-roam-organize-citar--notes-source
             citar-notes-sources)))))

(provide 'org-roam-organize-citar-test)
;;; org-roam-organize-citar-test.el ends here
