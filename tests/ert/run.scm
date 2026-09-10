#!@guile@ \
--no-auto-compile -s
!#

(define home (string-append (getenv "TMPDIR") "/home"))

(unless (file-exists? home)
  (mkdir home))

(setenv "HOME" home)

(let ((status (system* "@emacs@"
                       "-Q"
                       "--batch"
                       "--load"
                       "@testFile@"
                       "--funcall"
                       "ert-run-tests-batch-and-exit")))
  (unless (zero? status)
    (exit 1)))

(close-port (open-output-file (getenv "out")))
