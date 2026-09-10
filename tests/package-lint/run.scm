#!@guile@ \
--no-auto-compile -s
!#

(use-modules (ice-9 ftw)
             (srfi srfi-1)
             (srfi srfi-13))

(define (find-elisp-files directory)
  (append-map
   (lambda (name)
     (let ((path (string-append directory "/" name)))
       (cond
        ((file-is-directory? path)
         (find-elisp-files path))
        ((string-suffix? ".el" path)
         (list path))
        (else
         '()))))
   (scandir directory
            (lambda (name)
              (not (member name '("." "..")))))))

(define home (string-append (getenv "TMPDIR") "/home"))
(define elisp-files (find-elisp-files "@source@"))

(unless (file-exists? home)
  (mkdir home))

(setenv "HOME" home)

(when (null? elisp-files)
  (display "No Emacs Lisp files found.\n" (current-error-port))
  (exit 1))

(let ((status (apply system*
                     "@emacs@"
                     "-Q"
                     "--batch"
                     "-chdir"
                     "@source@"
                     "-L"
                     "@source@"
                     "--load"
                     "package-lint"
                     "--funcall"
                     "package-lint-batch-and-exit"
                     elisp-files)))
  (unless (zero? status)
    (exit 1)))

(close-port (open-output-file (getenv "out")))
