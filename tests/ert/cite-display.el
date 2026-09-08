;;; org-roam-organize-cite-display-test.el --- Citation display tests -*- lexical-binding: t; -*-

;;; Commentary:

;; ERT tests for managed literature UUID presentation in Org buffers.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'org)
(require 'org-element)
(require 'oc)
(require 'org-roam-organize)
(require 'org-roam-organize-cite-display)

(defun org-roam-organize-cite-display-test--overlays ()
  "Return live citation display overlays in the current buffer."
  (seq-filter
   (lambda (overlay)
     (and (overlay-buffer overlay)
          (overlay-get overlay 'org-roam-organize-cite-display)))
   org-roam-organize-cite-display--overlays))

(defmacro org-roam-organize-cite-display-test--with-buffer
    (contents nodes &rest body)
  "Evaluate BODY in an Org buffer containing CONTENTS and managed NODES.

NODES is the value returned by a stubbed
`org-roam-organize--nodes-with-tag'.  BODY runs with Org-roam Organize mode
logically enabled and citation display installed in the current buffer."
  (declare (indent 2) (debug (form form body)))
  `(with-temp-buffer
     (insert ,contents)
     (org-mode)
     (let ((org-roam-organize-mode t)
           (org-roam-organize-registry
            '((:name "literature" :tag "ref" :cite t))))
       (cl-letf (((symbol-function 'org-roam-organize--nodes-with-tag)
                  (lambda (tag)
                    (should (equal tag "ref"))
                    ,nodes)))
         (add-hook 'org-font-lock-set-keywords-hook
                   #'org-roam-organize-cite-display--font-lock-setup
                   nil
                   t)
         (org-roam-organize-cite-display--refresh-font-lock)
         (font-lock-ensure (point-min) (point-max))
         ,@body))))

(ert-deftest org-roam-organize-cite-display-test-displays-managed-title-only ()
  (org-roam-organize-cite-display-test--with-buffer
      "[cite:@ref-a; @plain-key]"
      '((:id "ref-a" :title "Reference A"))
    (let ((overlays (org-roam-organize-cite-display-test--overlays)))
      (should (= (length overlays) 1))
      (let ((overlay (car overlays)))
        (should (equal (overlay-get overlay 'display) "Reference A"))
        (should
         (equal
          (buffer-substring-no-properties
           (overlay-start overlay) (overlay-end overlay))
          "@ref-a"))))
    (should (equal (buffer-string) "[cite:@ref-a; @plain-key]"))))

(ert-deftest org-roam-organize-cite-display-test-preserves-source-and-ast ()
  (org-roam-organize-cite-display-test--with-buffer
      "[cite/t:see @ref-a, p. 10]"
      '((:id "ref-a" :title "Reference A"))
    (set-buffer-modified-p nil)
    (font-lock-flush (point-min) (point-max))
    (font-lock-ensure (point-min) (point-max))
    (should-not (buffer-modified-p))
    (should (equal (buffer-string) "[cite/t:see @ref-a, p. 10]"))
    (goto-char (1+ (point-min)))
    (let* ((citation (org-element-context))
           (reference (car (org-cite-get-references citation))))
      (should (eq (org-element-type citation) 'citation))
      (should (equal (org-element-property :key reference) "ref-a")))
    (let ((overlay (car (org-roam-organize-cite-display-test--overlays))))
      (should
       (equal
        (buffer-substring-no-properties
         (overlay-start overlay) (overlay-end overlay))
        "@ref-a")))))

(ert-deftest org-roam-organize-cite-display-test-displays-multiple-references ()
  (org-roam-organize-cite-display-test--with-buffer
      "[cite:@ref-a; @ref-b]"
      '((:id "ref-a" :title "Reference A")
        (:id "ref-b" :title "Reference B"))
    (let ((display-values
           (sort
            (mapcar
             (lambda (overlay) (overlay-get overlay 'display))
             (org-roam-organize-cite-display-test--overlays))
            #'string<)))
      (should (equal display-values '("Reference A" "Reference B"))))))

(ert-deftest org-roam-organize-cite-display-test-skips-missing-title ()
  (org-roam-organize-cite-display-test--with-buffer
      "[cite:@missing; @untitled]"
      '((:id "untitled" :title nil))
    (should-not (org-roam-organize-cite-display-test--overlays))))

(ert-deftest org-roam-organize-cite-display-test-refontification-is-idempotent ()
  (org-roam-organize-cite-display-test--with-buffer
      "[cite:@ref-a]"
      '((:id "ref-a" :title "Reference A"))
    (should (= (length (org-roam-organize-cite-display-test--overlays)) 1))
    (font-lock-flush (point-min) (point-max))
    (font-lock-ensure (point-min) (point-max))
    (should (= (length (org-roam-organize-cite-display-test--overlays)) 1))))

(ert-deftest org-roam-organize-cite-display-test-edit-removes-stale-overlay ()
  (org-roam-organize-cite-display-test--with-buffer
      "[cite:@ref-a]"
      '((:id "ref-a" :title "Reference A"))
    (let ((overlay (car (org-roam-organize-cite-display-test--overlays))))
      (goto-char (1+ (overlay-start overlay)))
      (delete-char 1)
      (should-not (overlay-buffer overlay))
      (should-not (org-roam-organize-cite-display-test--overlays)))))

(ert-deftest org-roam-organize-cite-display-test-cache-and-refresh ()
  (with-temp-buffer
    (insert "[cite:@ref-a]")
    (org-mode)
    (let ((org-roam-organize-mode t)
          (org-roam-organize-registry
           '((:name "literature" :tag "ref" :cite t)))
          (title "First Title")
          (query-count 0))
      (cl-letf (((symbol-function 'org-roam-organize--nodes-with-tag)
                 (lambda (_tag)
                   (setq query-count (1+ query-count))
                   (list (list :id "ref-a" :title title)))))
        (add-hook 'org-font-lock-set-keywords-hook
                  #'org-roam-organize-cite-display--font-lock-setup
                  nil
                  t)
        (org-roam-organize-cite-display--refresh-font-lock)
        (font-lock-ensure (point-min) (point-max))
        (should (= query-count 1))
        (font-lock-flush (point-min) (point-max))
        (font-lock-ensure (point-min) (point-max))
        (should (= query-count 1))
        (setq title "Second Title")
        (let ((font-lock-mode t))
          (cl-letf (((symbol-function
                      'org-roam-organize-cite-display--refresh-font-lock)
                     #'ignore))
            (org-roam-organize-cite-display-refresh)))
        (should (= query-count 2))
        (should
         (equal
          (overlay-get
           (car (org-roam-organize-cite-display-test--overlays))
           'display)
          "Second Title"))))))

(ert-deftest org-roam-organize-cite-display-test-refresh-preserves-narrowing ()
  (let ((source
         (concat
          "[cite:@ref-a]\n\n"
          "[cite:@ref-b]\n\n"
          "[cite:@ref-c]")))
    (org-roam-organize-cite-display-test--with-buffer
        source
        '((:id "ref-a" :title "Reference A")
          (:id "ref-b" :title "Reference B")
          (:id "ref-c" :title "Reference C"))
      (should (= (length
                  (org-roam-organize-cite-display-test--overlays))
                 3))
      (goto-char (point-min))
      (search-forward "[cite:@ref-b]")
      (let* ((narrow-end (point))
             (narrow-beginning
              (- narrow-end (length "[cite:@ref-b]"))))
        (narrow-to-region narrow-beginning narrow-end)
        (let ((saved-point-min (point-min))
              (saved-point-max (point-max)))
          (let ((font-lock-mode t))
            (cl-letf (((symbol-function
                        'org-roam-organize-cite-display--refresh-font-lock)
                       #'ignore))
              (org-roam-organize-cite-display-refresh)))
          (should (buffer-narrowed-p))
          (should (= (point-min) saved-point-min))
          (should (= (point-max) saved-point-max)))
        (widen))
      (should (= (length
                  (org-roam-organize-cite-display-test--overlays))
                 3))
      (should (equal (buffer-string) source)))))

(ert-deftest org-roam-organize-cite-display-test-major-mode-change-cleans-overlay ()
  (org-roam-organize-cite-display-test--with-buffer
      "[cite:@ref-a]"
      '((:id "ref-a" :title "Reference A"))
    (let ((overlay (car (org-roam-organize-cite-display-test--overlays))))
      (should (overlay-buffer overlay))
      (should
       (memq #'org-roam-organize-cite-display--clear
             change-major-mode-hook))
      (fundamental-mode)
      (should-not (overlay-buffer overlay))
      (should (equal (buffer-string) "[cite:@ref-a]")))))

(ert-deftest org-roam-organize-cite-display-test-setup-and-teardown-lifecycle ()
  (let ((org-roam-organize-mode t)
        (org-roam-organize-registry
         '((:name "literature" :tag "ref" :cite t))))
    (with-temp-buffer
      (insert "[cite:@ref-a]")
      (org-mode)
      (cl-letf (((symbol-function 'org-roam-organize--nodes-with-tag)
                 (lambda (_tag)
                   '((:id "ref-a" :title "Reference A")))))
        (unwind-protect
            (progn
              (should (org-roam-organize-cite-display--setup))
              (font-lock-ensure (point-min) (point-max))
              (should
               (= (length
                   (org-roam-organize-cite-display-test--overlays))
                  1))
              (should
               (memq #'org-roam-organize-cite-display--clear
                     change-major-mode-hook))
              (setq org-roam-organize-mode nil)
              (should-not (org-roam-organize-cite-display--teardown))
              (should-not
               (org-roam-organize-cite-display-test--overlays))
              (should-not org-roam-organize-cite-display--title-cache)
              (should-not
               (memq #'org-roam-organize-cite-display--clear
                     change-major-mode-hook)))
          (org-roam-organize-cite-display--teardown))))))

(ert-deftest org-roam-organize-cite-display-test-refresh-preserves-font-lock-state ()
  (let (defaults-called refresh-called)
    (cl-letf (((symbol-function 'org-set-font-lock-defaults)
               (lambda ()
                 (setq defaults-called t)))
              ((symbol-function 'font-lock-refresh-defaults)
               (lambda ()
                 (setq refresh-called t))))
      (let ((font-lock-mode nil))
        (should-not
         (org-roam-organize-cite-display--refresh-font-lock))
        (should defaults-called)
        (should-not refresh-called))
      (setq defaults-called nil
            refresh-called nil)
      (let ((font-lock-mode t))
        (should-not
         (org-roam-organize-cite-display--refresh-font-lock))
        (should defaults-called)
        (should refresh-called)))))

(ert-deftest org-roam-organize-cite-display-test-refresh-respects-font-lock-state ()
  (with-temp-buffer
    (insert "[cite:@ref-a]")
    (org-mode)
    (let ((org-roam-organize-mode t)
          (refresh-count 0)
          flush-called
          ensure-called)
      (let ((overlay
             (org-roam-organize-cite-display--make-overlay
              (point-min) (1+ (point-min)) "Reference A")))
        (setq org-roam-organize-cite-display--title-cache
              (make-hash-table :test 'equal))
        (cl-letf (((symbol-function
                    'org-roam-organize-cite-display--refresh-font-lock)
                   (lambda ()
                     (setq refresh-count (1+ refresh-count))))
                  ((symbol-function 'font-lock-flush)
                   (lambda (&rest _arguments)
                     (setq flush-called t)))
                  ((symbol-function 'font-lock-ensure)
                   (lambda (&rest _arguments)
                     (setq ensure-called t))))
          (let ((font-lock-mode nil))
            (org-roam-organize-cite-display-refresh)
            (should (= refresh-count 1))
            (should-not flush-called)
            (should-not ensure-called)
            (should-not (overlay-buffer overlay))
            (should-not org-roam-organize-cite-display--title-cache))
          (let ((font-lock-mode t))
            (org-roam-organize-cite-display-refresh)
            (should (= refresh-count 2))
            (should flush-called)
            (should ensure-called)))))))

(ert-deftest org-roam-organize-cite-display-test-capabilities-exist ()
  (let ((result
         (org-roam-organize--check-capabilities
          org-roam-organize-cite-display--capability-alist)))
    (ert-info ((cdr result))
      (should (car result)))))

(provide 'org-roam-organize-cite-display-test)
;;; org-roam-organize-cite-display-test.el ends here
