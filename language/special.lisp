;; This software is Copyright (c) 2012 Chris Bagley
;; (techsnuffle<at>gmail<dot>com)
;; Chris Bagley grants you the rights to
;; distribute and use this software as governed
;; by the terms of the Lisp Lesser GNU Public License
;; (http://opensource.franz.com/preamble.html),
;; known as the LLGPL.

(in-package :varjo)
(named-readtables:in-readtable fn_::fn_lambda)

;;{TODO} all special functions starting with :% should start with % as they
;;       are not directly used anyway. After his look into whether any glsl
;;       functions should use keyword names.

;;{TODO} make it handle multiple assignements like cl version
(v-defspecial :setf ((place v-type) (val v-type))
  :return
  (cond ((not (v-placep (code-type place)))
         (error 'non-place-assign :place place :val val))
        ((not (v-type-eq (code-type place) (code-type val)))
         (error 'setf-type-match :code-obj-a place :code-obj-b val))
        (t (merge-obs (list place val) :type (code-type place)
                      :current-line (gen-assignment-string place val)))))

(v-defspecial :%setf ((place v-type) (val v-type))
  :return
  (merge-obs (list place val) :type (code-type place)
             :current-line (gen-assignment-string place val)))

(v-defspecial :progn (&rest body)
  ;; this is super important as it is the only function that implements
  ;; imperitive coding. It does this by passing the env from one form
  ;; to the next.
  :args-valid t
  :return
  (if body
      (let* ((mvb (v-multi-val-base env))
             (env (let ((new-env (clone-environment env)))
                    (setf (v-multi-val-base new-env) nil)
                    new-env))
             (body-objs (append
                         (loop :for code :in (butlast body) :collect
                            (multiple-value-bind (code-obj new-env)
                                (varjo->glsl code env)
                              (when new-env (setf env new-env))
                              code-obj))
                         (let ((code (last1 body)))
                           (setf (v-multi-val-base env) mvb)
                           (list (varjo->glsl code env))))))

        (let ((last-obj (last1 body-objs)))
          (merge-obs body-objs
                     :type (code-type last-obj)
                     :current-line (current-line last-obj)
                     :to-block (merge-lines-into-block-list body-objs)
                     :multi-vals (multi-vals (last1 body-objs)))))
      (make-instance 'code :type (type-spec->type :none))))

(v-defmacro :prog1 (&body body)
  (let ((tmp (free-name 'progn-var)))
    `(let ((,tmp ,(first body)))
       ,@(rest body)
       ,tmp)))


(v-defspecial :multiple-value-bind (vars value-form &rest body)
  :args-valid t
  :return
  (let ((new-env (clone-environment env))
        (base (string-downcase (string (free-name 'mvb)))))
    (setf (v-multi-val-base new-env) base)
    (let ((code-obj (varjo->glsl value-form new-env)))
      (unless (= (length vars) (+ 1 (length (multi-vals code-obj))))
        (error 'multi-val-bind-mismatch :val-form value-form :bindings vars))
      (let* ((mvals (multi-vals code-obj))
             (v-vals (mapcar λ(slot-value _ 'value) mvals))
             (types (cons (code-type code-obj)
                          (mapcar #'v-type v-vals))))
        (varjo->glsl
         `(%clone-env-block
           (%multi-env-progn
            ,@(loop :for type :in types :for name :in vars
                 :for i :from 0 :collect
                 `(%glsl-let ((,name ,(type->type-spec type))) t
                             ,(format nil "~a~a" base i))))
           ;; the meat
           (setf ,(first vars) ,code-obj)
           ,@body)
         env)))))

(v-defspecial :values (&rest values)
  :args-valid t
  :return
  (if (v-multi-val-base env)
      (%values values env)
      (expand->varjo->glsl `(prog1 ,@values) env)))

(defun %values (values env)
  (let ((new-env (clone-environment env)))
    (setf (v-multi-val-base new-env) nil)
    (let* ((qualifier-lists (mapcar #'extract-value-qualifiers values))
           (forms (mapcar #'extract-value-form values))

           (objs (mapcar λ(varjo->glsl _ new-env) forms))
           (base (v-multi-val-base env))
           (glsl-names (loop :for i :below (length forms) :collect
                          (format nil "~a~a" base i)))
           (vals (loop :for o :in objs :for n in glsl-names :collect
                    (make-instance 'v-value :glsl-name n :type (code-type o))))
           (first-name (free-name 'v-tmp env))
           (result (expand->varjo->glsl
                    `(let ((,first-name ,(first objs)))
                       ,@(loop :for o :in (rest objs)
                            :for v :in (rest vals) :collect
                            `(%setf ,v ,o))
                       ,first-name)
                    env)))
      (setf (multi-vals result)
            (mapcar #'make-mval (rest vals) (rest qualifier-lists)))
      result)))

(defun extract-value-qualifiers (value-form)
  (when (and (listp value-form) (keywordp (first value-form)))
    (butlast value-form)))
(defun extract-value-form (value-form)
  (if (and (listp value-form) (keywordp (first value-form)))
      (last1 value-form)
      value-form))

;;--------------------------------------------------
(defclass mval () ((value :initarg :value) (qualifiers :initarg :qualifiers)))

(defun make-mval (v-value &optional qualifiers)
  (make-instance 'mval :value v-value :qualifiers qualifiers))

(defun mval->out-form (mval env)
  (with-slots (value qualifiers) mval
    `(%out (,(free-name :out env) ,@qualifiers) ,value)))
;;--------------------------------------------------

(v-defspecial :return (form)
  :args-valid t
  :return
  (let ((new-env (clone-environment env)))
    ;; we create an environment with the signal to let any 'values' forms
    ;; down the tree know they will be caught and what their name prefix should
    ;; be.
    (setf (v-multi-val-base new-env) "return")
    ;; We then compile the form using the augmented environment, the values
    ;; statements will expand and flow back as 'multi-vals' and the current-line
    ;; now there are two styles of return:
    ;; - The first is for a regular function, in which multivals become
    ;;   out-arguments and the current-line is returned
    ;; - The second is for a shader stage in which the multi-vars become
    ;;   output-variables and the current line is handled in a 'context'
    ;;   specific way.
    (let* ((code-obj (varjo->glsl form new-env))
           (result
            (if (member :main (v-context env))
                (%main-return code-obj env)
                (%regular-value-return code-obj))))
      result)))

;; Used when this is a labels (or otherwise local) function
(defun %regular-value-return (code-obj)
  (merge-obs
   code-obj :type 'v-void
   :current-line (format nil "return ~a" (current-line code-obj))
   :returns (cons (code-type code-obj) (multi-vals code-obj))))


;; Used when this is the main stage function
;; this
(defun %main-return (code-obj env)
  (if (multi-vals code-obj)
      (let* ((mvals (multi-vals code-obj))
             (v-vals (mapcar λ(slot-value _ 'value) mvals))
             (types (mapcar #'v-type v-vals))
             (glsl-lines (mapcar λ(v-glsl-name _) v-vals)))
        (varjo->glsl
         `(%clone-env-block
           (%multi-env-progn
            ,@(loop :for type :in types :for line :in glsl-lines :collect
                 `(%glsl-let ((,(free-name 'x env) ,(type->type-spec type)))
                             t ,line)))
           ;; the meat
           ,(%default-out-for-stage code-obj env)
           ,@(mapcar λ(mval->out-form _ env) (multi-vals code-obj)))
         env))
      (varjo->glsl
         `(%clone-env-block
           (%multi-env-progn ,(%default-out-for-stage code-obj env)))
         env)))

;; fragment comes first as it doesnt restrict the exit type...this is a bug
;; really as fragment out-var should be vec4...We should have a case for
;; when context includes all stages, in which case any type is allowed
(defun %default-out-for-stage (form env)
  (let ((context (v-context env)))
    (cond ((member :fragment context) `(%out (,(free-name :output-color env))
                                             ,form))
          ((member :vertex context) `(setf gl-position ,form))
          (t (error "Have not implemented #'values defaults for this stage ~a"
                    env)))))

(v-defspecial :%clean-env-block (&rest body)
  :args-valid t
  :return (let ((new-env (clean-environment env)))
            (varjo->glsl `(progn ,@body) new-env)))

(v-defspecial :%clean-env-block-for-labels (&rest body)
  :args-valid t
  :return (let ((new-env (clean-environment env)))
            (setf (v-functions new-env)
                  (v-functions env))
            (setf (v-context new-env)
                  (remove :main (v-context env)))
            (varjo->glsl `(progn ,@body) new-env)))

(v-defspecial :%clone-env-block (&rest body)
  :args-valid t
  :return (let ((new-env (clone-environment env)))
            (varjo->glsl `(progn ,@body) new-env)))

(v-defspecial %merge-env (env-a new-env)
  :args-valid t
  :return
  (let ((dummy-code-obj (make-instance 'code :current-line "")))
    (values dummy-code-obj (merge-env env-a new-env))))

;;{TODO} this should have a and &optional for place
;;{TODO} could this take a form and infer the type? yes...it could
;;       should destructively modify the env
(v-defspecial :%make-var (name-string type)
  :args-valid t
  :return (make-instance 'code :type (set-place-t type)
                         :current-line name-string))


(v-defspecial :%typify (form &optional qualifiers)
  :args-valid t
  :return
  (let ((code (varjo->glsl form env)))
    (merge-obs code :type (code-type code)
               :current-line (prefix-type-declaration code qualifiers))))

(defun %validate-var-types (var-name type code-obj)
  (when (and code-obj (typep (code-type code-obj) 'v-stemcell))
    (error "Code not ascertain the type of the stemcell used in the let form:~%(~a ~a)"
           (string-downcase var-name) (current-line code-obj)))
  (when (and (null type) (null code-obj))
    (error "Could not establish the type of the variable: ~s" var-name))
  (when (and code-obj type (not (v-type-eq (code-type code-obj) type)))
    (error "Type specified does not match the type of the form~%~s~%~s"
           (code-type code-obj) type))
  t)

(v-defspecial %glsl-let (form &optional include-type-declaration arg-glsl-name)
  :args-valid t
  :return
  (let* ((var-spec (listify (first form)))
         (glsl-name (or arg-glsl-name
                        (safe-glsl-name-string (free-name (first var-spec) env))))
         (code-obj (when (> (length form) 1) (varjo->glsl (second form) env))))
    (destructuring-bind (name &optional type-spec qualifiers) var-spec
      (declare (ignore qualifiers))
      (let ((type-spec (when type-spec (type-spec->type type-spec))))
        (%validate-var-types name type-spec code-obj)
        (let* ((glsl-let-code
                (if code-obj
                    (if (eq include-type-declaration :env-and-set)
                        `(setf (%make-var ,glsl-name ,(or type-spec (code-type code-obj))) ,code-obj)
                        `(setf (%typify (%make-var ,glsl-name ,(or type-spec (code-type code-obj))))
                               ,code-obj))
                    (if (eq include-type-declaration :env-and-set)
                        `(%make-var ,glsl-name ,type-spec)
                        `(%typify (%make-var ,glsl-name ,type-spec)))))
               (let-obj (varjo->glsl glsl-let-code env)))
          (add-var name
                   (make-instance 'v-value :glsl-name glsl-name
                                  :type (set-place-t
                                         (or type-spec (code-type code-obj))))
                   env t)
          (values (if include-type-declaration
                      (merge-obs let-obj
                                 :type (type-spec->type 'v-none)
                                 :current-line nil
                                 :to-block (append (to-block let-obj)
                                                   (list (current-line
                                                          (end-line let-obj)))))
                      (make-instance 'code :type 'v-none))
                  env))))))

(v-defspecial %multi-env-progn (&rest env-local-expessions)
  :args-valid t
  :return
  (if env-local-expessions
      (let* ((e (mapcar λ(multiple-value-list (varjo->glsl _ env))
                        env-local-expessions))
             (code-objs (mapcar #'first e))
             (env-objs (mapcar #'second e))
             (merged-env (reduce λ(merge-env _ _1) env-objs)))
        (values
         (merge-obs code-objs
                    :type (type-spec->type 'v-none)
                    :current-line nil
                    :to-block (append (mapcan #'to-block code-objs)
                                      (mapcar λ(current-line (end-line _))
                                              code-objs))
                    :to-top (mapcan #'to-top code-objs))
         merged-env))
      (make-instance 'code :type (type-spec->type :none) :current-line "")))

(v-defmacro :let (bindings &body body)
  `(%clone-env-block
    (%multi-env-progn
     ,@(loop :for b :in bindings :collect `(%glsl-let ,b t)))
    ,@body))

(v-defmacro :let* (bindings &rest body)
  (let* ((bindings (reverse bindings))
         (result `(let (,(first bindings)) ,@body)))
    (loop :for binding :in (rest bindings) :do
       (setf result `(let (,binding) ,result)))
    result))

(v-defspecial :%make-function (name raw-args &rest body)
  :args-valid t
  :return
  (let* ((mainp (eq name :main))
         (env (if mainp
                  (let ((new-env (clone-environment env)))
                    (push :main (v-context new-env))
                    new-env)
                  env))
         (args (mapcar #'list raw-args))
         (arg-glsl-names (loop :for (name) :in raw-args :collect
                            (safe-glsl-name-string (free-name name))))
         (body-code `(return (progn ,@body)))
         (body-obj (varjo->glsl `(,(if mainp 'progn '%clean-env-block-for-labels)
                                   (%multi-env-progn
                                    ,@(loop :for b :in args
                                         :for g :in arg-glsl-names
                                         :collect `(%glsl-let ,b nil ,g)))
                                   ,body-code) env))
         (glsl-name (if mainp "main" (safe-glsl-name-string (free-name name))))
         (primary-return (first (returns body-obj)))
         (multi-return-vars (rest (returns body-obj)))
         (type (if mainp (type-spec->type 'v-void) primary-return)))

    (unless (or mainp primary-return) (error 'no-function-returns :name name))
    (add-function
     name (func-spec->function
           (v-make-f-spec name
                          (gen-function-transform glsl-name raw-args
                                                  multi-return-vars)
                          nil ;;should be context
                          (mapcar #'second raw-args)
                          type :glsl-name glsl-name
                          :multi-return-vars multi-return-vars) env) env t)
    (let* ((arg-pairs (loop :for (ignored type) :in raw-args
                         :for name :in arg-glsl-names :collect
                         `(,(v-glsl-string (type-spec->type type)) ,name)))
           (out-arg-pairs (loop :for mval :in multi-return-vars :for i :from 1
                             :for name = (v-glsl-name (slot-value mval 'value)) :collect
                             `(,(v-glsl-string (v-type (slot-value mval 'value)))
                                ,name)))
           (sigs (if mainp
                     (signatures body-obj)
                     (cons (gen-function-signature glsl-name arg-pairs
                                                   out-arg-pairs type)
                           (signatures body-obj))))
           (top (cons-end (gen-function-body-string
                           glsl-name arg-pairs out-arg-pairs type body-obj)
                          (to-top body-obj))))

      (values (merge-obs body-obj
                         :type (type-spec->type 'v-none)
                         :current-line nil
                         :signatures sigs
                         :to-top top
                         :to-block nil
                         :returns nil
                         :out-vars (out-vars body-obj)
                         :multi-vals nil)
              env))))

(v-defmacro :labels (definitions &body body)
  `(%clone-env-block
    ,@(loop :for d :in definitions :collect `(%make-function ,@d))
    ,@body))

;; {TODO} what if type of form is not value
(v-defspecial :%out (name-and-qualifiers form)
  :args-valid t
  :return
  (let* ((form-obj (varjo->glsl form env))
         (out-var-name (if (consp name-and-qualifiers)
                           (first name-and-qualifiers)
                           name-and-qualifiers))
         (qualifiers (when (consp name-and-qualifiers)
                       (rest name-and-qualifiers)))
         (glsl-name (safe-glsl-name-string out-var-name)))
    (if (assoc out-var-name *glsl-variables*)
        (error 'out-var-name-taken out-var-name)
        (end-line
         (merge-obs
          form-obj :type 'v-none
          :current-line (gen-out-var-assignment-string glsl-name form-obj)
          :to-block (to-block form-obj)
          :out-vars (cons `(,out-var-name
                            ,qualifiers
                            ,(make-instance 'v-value :type (code-type form-obj)
                                            :glsl-name glsl-name))
                          (out-vars form-obj))) t))))

(v-defspecial :assert (kind form error-message)
  :args-valid t
  :return
  (case kind
    ((:valid-variable '(:valid-variable))
     (and (symbolp form)
          (handler-case (varjo->glsl form env)
            (varjo-error () (error error-message)))))
    (otherwise (error "Unknown assert kind ~s" kind))))

;; note that just like in lisp this only fails if false. 0 does not fail.
(v-defspecial :if (test-form then-form &optional else-form)
  :args-valid t
  :return
  (let* ((test-obj (varjo->glsl test-form env))
         (then-obj (end-line (varjo->glsl then-form env)))
         (else-obj (when else-form (end-line (varjo->glsl else-form env))))
         (arg-objs (remove-if #'null (list test-obj then-obj else-obj))))
    (when (not (v-typep (code-type test-obj) 'v-bool))
      (setf test-obj (varjo->glsl t env))
      (setf else-obj nil))
    (if (v-typep (code-type test-obj) 'v-bool)
        (merge-obs arg-objs :type :none :current-line nil
                   :to-block (list (gen-if-string test-obj then-obj else-obj)))
        (error "The result of the test must be a bool.~%~s"
               (code-type test-obj)))))

(v-defspecial :while (test &rest body)
  :args-valid t
  :return
  (let* ((test-obj (varjo->glsl test env))
         (body-obj (varjo->glsl `(progn ,@body) env)))
    (if (v-typep (code-type test-obj) 'v-bool)
        (merge-obs (list body-obj test-obj)
                   :type 'v-none :current-line nil
                   :to-block (list (gen-while-string test-obj body-obj)))
        (error 'loop-will-never-halt :test-code test :test-obj test-obj))))


;; {TODO} check keys
(v-defspecial :switch (test-form &rest clauses)
  :args-valid t
  :return
  (let* ((test-obj (varjo->glsl test-form env))
         (keys (mapcar #'first clauses))
         (clause-body-objs (mapcar #'(lambda (x) (varjo->glsl
                                                  `(progn ,(second x)) env))
                           clauses)))
    (if (and (v-typep (code-type test-obj) 'v-i-ui)
             (loop :for key :in keys :always
                (or (eq key 'default) (integerp key))))
        (merge-obs clause-body-objs :type 'v-none
                   :current-line nil
                   :to-block (list (gen-switch-string test-obj keys
                                                      clause-body-objs)))
        (error 'switch-type-error test-obj keys))))

(v-defmacro :s~ (&rest args) `(swizzle ,@args))
(v-defspecial :swizzle (vec-form components)
  :args-valid t
  :return
  (let* ((vec-obj (varjo->glsl vec-form env))
         (allowed (subseq (list #\x #\y #\z #\w) 0
                          (first (v-dimensions (code-type vec-obj)))))
         (comp-string (if (keywordp components)
                          (string-downcase (symbol-name components))
                          (error 'swizzle-keyword :item components)))
         (new-len (length comp-string)))
    (if (and (>= new-len 2) (<= new-len 4)
             (v-typep (code-type vec-obj) 'v-vector)
             (loop :for c :across comp-string
                :always (find c allowed)))
        (merge-obs vec-obj :type (type-spec->type
                                  (p-symb 'varjo 'v-vec new-len))
                   :current-line (gen-swizzle-string vec-obj comp-string))
        (error "swizzle form invalid"))))






;;   (for (a 0) (< a 10) (++ a)
;;     (* a 2))
;; {TODO} double check implications of typify in compile-let-forms
(v-defspecial :for (var-form condition update &rest body)
  :args-valid t
  :return
  (if (consp (first var-form))
      (error 'for-loop-only-one-var)
      (multiple-value-bind (code new-env)
          (varjo->glsl `(%glsl-let ,var-form t) env)
        (let* ((var-string (subseq (first (to-block code)) 0 (1- (length (first (to-block code))))))
               (decl-obj (varjo->glsl (second var-form) new-env))
               (condition-obj (varjo->glsl condition new-env))
               (update-obj (varjo->glsl update new-env))
               (body-obj (end-line (varjo->glsl `(progn ,@body) new-env))))
          (unless (typep (code-type decl-obj) 'v-i-ui)
            (error 'invalid-for-loop-type decl-obj))
          (if (and (null (to-block condition-obj)) (null (to-block update-obj)))
              (merge-obs
               body-obj :type 'v-none :current-line nil
               :to-block `(,(gen-for-loop-string var-string condition-obj
                                                 update-obj body-obj)))
              (error 'for-loop-simple-expression))))))


(v-defspecial :the (type-name form)
  :args-valid t
  :return
  (let ((compiled (varjo->glsl form env))
        (declared-type (type-spec->type type-name)))
    (if (stemcellp (code-type compiled))
        (copy-code compiled
                   :type declared-type
                   :stemcells (let ((stemcell (first (stemcells compiled))))
                                `((,(first stemcell)
                                    ,(second stemcell)
                                    ,type-name))))
        (unless (v-typep compiled declared-type)
          (error "Incorrect declaration that ~a was of type ~a"
                 compiled type-name))))) ;{TODO} proper error here

(v-defspecial :%break ()
  :return
  (progn
    (break "Varjo compiler breakpoint" env)
    (make-none-ob)))
