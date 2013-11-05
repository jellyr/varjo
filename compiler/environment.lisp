;; This software is Copyright (c) 2012 Chris Bagley
;; (techsnuffle<at>gmail<dot>com)
;; Chris Bagley grants you the rights to
;; distribute and use this software as governed
;; by the terms of the Lisp Lesser GNU Public License
;; (http://opensource.franz.com/preamble.html),
;; known as the LLGPL.
(in-package :varjo)

(defparameter *global-env* :-genv-)
(defparameter *global-env-external-funcs* (make-hash-table))
(defparameter *global-env-funcs* (make-hash-table))
(defparameter *global-env-vars* (make-hash-table))
(defparameter *global-env-macros* (make-hash-table))

;;-------------------------------------------------------------------------

(defmethod clone-environment ((env (eql :-genv-)))
  (error 'clone-global-env-error))

(defmethod clone-environment ((env environment))
  (make-instance 'environment :variables (copy-list (v-variables env))
                 :functions (copy-list (v-functions env))
                 :macros (copy-list (v-macros env))
                 :types (copy-list (v-types env))
                 :context (copy-list (v-context env))))

;;-------------------------------------------------------------------------

(defun context-ok-given-restriction (context restriction)
  (every #'identity
         (loop :for item :in restriction :collect
            (if (listp item)
                (some #'identity (loop :for sub-item :in item :collect
                                    (find sub-item context)))
                (find item context)))))

(defmethod valid-for-contextp ((func list) (env environment))
  (let ((restriction (second func))
        (context (v-context env)))
    (if restriction
        (when (context-ok-given-restriction context restriction) func)
        func)))

(defmethod valid-for-contextp ((func v-function) (env environment))
  (let ((restriction (v-restriction func))
        (context (v-context env)))
    (if restriction
        (when (context-ok-given-restriction context restriction) func)
        func)))

;;-------------------------------------------------------------------------

(defmethod add-macro (macro-name (macro function) (context list) 
                      (env (eql :-genv-)) &optional modify-env)
  (declare (ignore modify-env))
  (setf (gethash macro-name *global-env-macros*) `(,macro ,context))
  *global-env*)

(defmethod add-macro (macro-name (macro function) (context list)
                      (env environment) &optional modify-env)
  (let ((env (if modify-env (clone-environment env) env)))
    (setf (gethash macro-name (v-macros env)) `(,macro ,context))
    env))

(defgeneric get-macro (macro-name env))

(defmethod get-macro (macro-name (env (eql :-genv-)))
  (let ((spec (gethash macro-name *global-env-macros*)))
    (when (and spec (valid-for-contextp spec env)) (first spec))))

(defmethod get-macro (macro-name (env environment))
  (or (let ((spec (gethash macro-name (v-macros env))))
        (when (and spec (valid-for-contextp spec env)) (first spec)))
      (get-macro macro-name *global-env*)))

(defmethod v-mboundp (macro-name (env environment))
  (not (null (get-macro macro-name env))))

;;-------------------------------------------------------------------------

(defmethod add-var (var-name (val v-value) (env (eql :-genv-)) 
                    &optional modify-env)
  (declare (ignore modify-env))
  (setf (gethash var-name *global-env-vars*) val)
  *global-env*)

(defmethod add-var (var-name (val v-value) (env environment))
  (let ((env (clone-environment env)))
    (setf (gethash var-name (v-variables env)) val)
    env))

(defmethod add-vars (var-name (vals list) (env environment))
  (let ((env (clone-environment env)))
    (loop :for val :in vals :do (setf (gethash var-name (v-variables env)) val))
    env))

(defgeneric get-var (var-name env))
(defmethod get-var (var-name (env (eql :-genv-)))
  (gethash var-name *global-env-vars*))

(defmethod get-var (var-name (env environment))
  (or (gethash var-name (v-variables env))
      (get-var var-name *global-env*)))

(defmethod v-boundp (var-name (env environment))
  (not (null (get-var var-name env))))

;;-------------------------------------------------------------------------

(defmethod valid-for-contextp ((func v-function) (env environment))
  (let ((restriction (v-restriction func))
        (context (v-context env)))
    (if restriction
        (when (context-ok-given-restriction context restriction) func)
        func)))

(defmethod add-function (func-name (func-spec list) (env (eql :-genv-))
                         &optional modify-env)
  (declare (ignore modify-env))
  (setf (gethash func-name *global-env-funcs*)
        (cons func-spec (gethash func-name *global-env-funcs*)))
  *global-env*)

(defmethod add-function (func-name (func-spec v-function) (env environment)
                         &optional modify-env)
  (let ((env (if modify-env (clone-environment env) env)))
    (setf (gethash func-name (v-functions env))
          (cons func-spec (gethash func-name (v-functions env))))
    env))

(defmethod add-functions (func-name (func-specs list) (env environment)
                          &optional modify-env)
  (let ((env (if modify-env (clone-environment env) env)))
    (loop :for func-spec :in func-specs :do
       (setf (gethash func-name (v-functions env))
             (cons func-spec (gethash func-name (v-functions env)))))
    env))

;; loop and instanstiate
(defmethod get-external-function (func-name (env (eql :-genv-)))
  (let ((f (gethash func-name *global-env-external-funcs*)))
    (when f (func-spec->function f))))

(defmethod get-function (func-name (env (eql :-genv-)))  
  (loop :for func :in (mapcar #'func-spec->function 
                              (gethash func-name *global-env-funcs*))
     :if (and func (valid-for-contextp func env)) :collect func))

(defmethod get-function (func-name (env environment))  
  (append (loop :for func :in (gethash func-name (v-functions env)) 
             :if (and func (valid-for-contextp func env)) :collect func)
          (get-function func-name *global-env*)))

(defmethod v-fboundp (func-name (env environment))
  (not (null (get-function func-name env))))

(defun func-spec->function (spec)
  (destructuring-bind (transform arg-spec return-spec context place 
                                 glsl-spec-matching) spec
    (make-instance 'v-function :glsl-string transform :arg-spec arg-spec
                   :return-spec return-spec :restriction context :place place
                   :glsl-spec-matching glsl-spec-matching)))

(defmethod v-functions ((env (eql :-genv-)))
  (declare (ignore env))
  *global-env-funcs*)

;;-------------------------------------------------------------------------

(defun wipe-global-environment ()
  (loop :for f :being :the :hash-key :of *global-env-funcs* :do
     (remhash f *global-env-funcs*))
  (loop :for f :being :the :hash-key :of *global-env-external-funcs* :do
     (remhash f *global-env-external-funcs*))
  (loop :for f :being :the :hash-key :of *global-env-vars* :do
     (remhash f *global-env-vars*)))
