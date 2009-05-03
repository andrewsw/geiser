;; eval.ss -- evaluation

;; Copyright (C) 2009 Jose Antonio Ortega Ruiz

;; Author: Jose Antonio Ortega Ruiz <jao@gnu.org>
;; Start date: Sun Apr 26, 2009 00:44

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3 of the License, or
;; (at your option) any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Comentary:

;; Evaluation functions

;;; Code:

#lang scheme

(provide eval-in
         compile-in
         load-file
         compile-file
         macroexpand
         make-repl-reader)

(require scheme/enter geiser/utils geiser/autodoc)

(define last-result (void))
(define nowhere (open-output-nowhere))

(define (ensure-spec spec)
  (cond ((symbol? spec) spec)
        ((not (string? spec)) #f)
        ((not (file-exists? spec)) #f)
        ((absolute-path? spec) `(file ,spec))
        (else spec)))

(define (load-module spec . port)
  (parameterize ((current-error-port (if (null? port) nowhere (car port))))
    (eval #`(enter! #,spec))))

(define (ensure-namespace mod-spec)
  (letrec ((spec (ensure-spec mod-spec))
           (handler (lambda (e)
                      (load-module spec)
                      (enter! #f)
                      (module->namespace spec))))
    (if spec
        (with-handlers ((exn:fail:contract? handler))
          (module->namespace spec))
        (current-namespace))))

(define (namespace->module-path-name ns)
  (let ((rmp (variable-reference->resolved-module-path
              (eval '(#%variable-reference) ns))))
    (and (resolved-module-path? rmp)
         (resolved-module-path-name rmp))))

(define namespace->module-name
  (compose module-path-name->name namespace->module-path-name))

(define last-namespace (make-parameter (current-namespace)))

(define (exn-key e)
  (vector-ref (struct->vector e) 0))

(define (set-last-error e)
  (set! last-result `((error (key . ,(exn-key e))
                             (subr)
                             (msg . ,(exn-message e))))))

(define (set-last-result v . vs)
  (set! last-result `((result  ,v ,@vs))))

(define (eval-in form spec)
  (set-last-result (void))
  (with-handlers ((exn? set-last-error))
    (update-module-cache spec form)
    (call-with-values
        (lambda () (eval form (ensure-namespace spec)))
      set-last-result))
  last-result)

(define compile-in eval-in)

(define (load-file file)
  (with-handlers ((exn? set-last-error))
    (let ((current-path (namespace->module-path-name (last-namespace))))
      (update-module-cache file)
      (set-last-result
       (string-append (with-output-to-string
                        (lambda ()
                          (load-module (ensure-spec file)
                                       (current-output-port))))
                      "done."))
      (load-module (and (path? current-path)
                        (ensure-spec (path->string current-path))))))
  last-result)

(define compile-file load-file)

(define (macroexpand form . all)
  (let ((all (and (not (null? all)) (car all))))
    (with-output-to-string
      (lambda ()
        (pretty-print (syntax->datum ((if all expand expand-once) form)))))))

(define (make-repl-reader builtin-reader)
  (lambda (ns)
    (last-namespace ns)
    (printf "mzscheme@(~a)" (namespace->module-name ns))
    (builtin-reader)))

;;; eval.ss ends here