(in-package :varjo)
(in-readtable fn:fn-reader)

;;
;; Environment Public API
;;
;; In macros we have access to the environment, we should have safe ways to
;; interact with that environment.
;;

;;-------------------------------------------------------------------------
;; Symbol Bindings

(defmethod all-bound-symbols ((env macro-env))
  (all-symbol-binding-names (slot-value env 'env) :stop-at-base t))

;;-------------------------------------------------------------------------
;; Variables

(defmethod variables-in-scope ((env macro-env))
  (let* ((all (all-bound-symbols env))
         (env (slot-value env 'env))
         (bindings (mapcar λ(list _ (get-symbol-binding _ t env)) all))
         (values (remove-if-not λ(typep (second _) 'v-value) bindings)))
    (mapcar #'first values)))

(defmethod variable-in-scope-p ((name symbol) (env macro-env))
  (not (null (find name (variables-in-scope env)))))

;;-------------------------------------------------------------------------
;; Types

(defmethod variable-type ((name symbol) (env macro-env))
  (let* ((binding (%get-val-binding name 'variable-type env)))
    (v-type binding)))

(defmethod argument-type ((name symbol) (env macro-expansion-environment))
  (with-slots (macro-obj) env
    (error 'no-types-for-regular-macro-args
           :macro-name (name macro-obj) :arg name)))

(defmethod argument-type ((name symbol)
                          (env compiler-macro-expansion-environment))
  (code-type (%get-macro-arg name env)))

;;-------------------------------------------------------------------------
;; Uniforms

(defmethod variable-is-uniform-p ((name symbol) (env macro-env))
  (not (null (%uniform-name (%get-val-binding name 'variable-uniform-name env)
                            env))))

(defmethod argument-is-uniform-p ((name symbol)
                                  (env compiler-macro-expansion-environment))
  (not (null (%uniform-name (%get-macro-arg name env) env))))

(defmethod argument-is-uniform-p ((name symbol)
                                  (env macro-expansion-environment))
    (with-slots (macro-obj) env
      (error 'no-tracking-for-regular-macro-args
             :macro-name (name macro-obj) :arg name)))

(defmethod variable-uniform-name ((name symbol) (env macro-env))
  (or (%uniform-name (%get-val-binding name 'variable-uniform-name env) env)
      (error 'not-proved-a-uniform :name name)))

(defmethod argument-uniform-name ((name symbol)
                                  (env compiler-macro-expansion-environment))
  (or (not (null (%uniform-name (%get-macro-arg name env) env)))
      (error 'not-proved-a-uniform :name name)))

(defmethod argument-uniform-name ((name symbol)
                                  (env macro-expansion-environment))
    (with-slots (macro-obj) env
      (error 'no-tracking-for-regular-macro-args
             :macro-name (name macro-obj) :arg name)))

(defmethod add-lisp-form-as-uniform (form type-spec (env macro-env)
                                     &optional name)
  (assert (symbolp name))
  (let ((name (or name (gensym "INJECTED"))))
    (inject-implicit-uniform name type-spec (slot-value env 'env)
                             form)))

;;-------------------------------------------------------------------------
;; Metadata

(defmethod metadata-for-variable ((name symbol) (metadata-key symbol)
                                  (env macro-env))
  (let* ((type (variable-type name env))
         (id (flow-ids type)))
    (metadata-for-flow-id metadata-key id env)))

(defmethod metadata-for-argument ((name symbol) (metadata-key symbol)
                                  (env compiler-macro-expansion-environment))
  (let ((id (flow-ids (%get-macro-arg name env))))
    (metadata-for-flow-id metadata-key id env)))

(defmethod metadata-for-argument ((name symbol) (metadata-key symbol)
                                  (env macro-expansion-environment))
  (with-slots (macro-obj) env
    (error 'no-metadata-for-regular-macro-args
           :macro-name (name macro-obj) :arg name)))

;; (defmethod (setf metadata-for-variable) (value (name symbol) (env macro-env))
;;   (let* ((type (variable-type name env))
;;          (id (flow-ids type)))
;;     (setf (metadata-for-flow-id id env) value)))

;;-------------------------------------------------------------------------
;; Internal Helpers (move these to own file)

(defun %get-macro-arg (name env)
  (with-slots (macro-obj args) env
    (let ((arg-pos (position name (arguments macro-obj))))
      (assert arg-pos () 'unknown-macro-argument
              :macro-name (name macro-obj) :arg name)
      (elt args arg-pos))))

(defmethod %uniform-name ((id flow-identifier) env)
  (first (find id (v-uniforms (slot-value env 'env)) :test #'id=
               :key λ(flow-ids (second _)))))

(defmethod %uniform-name ((code code) (env macro-env))
  (let ((id (flow-ids code)))
    (or (%uniform-name id env)
        (find id (stemcells code) :test #'id= :key #'flow-ids))))

(defmethod %uniform-name ((val v-value) (env macro-env))
  (%uniform-name (flow-ids val) env))


(defun %get-val-binding (name callee env)
  (let ((b (get-symbol-binding name t (slot-value env 'env))))
    (etypecase b
      (v-value b)
      (null (error 'unbound-macro-not-var :name name :callee callee))
      (v-symbol-macro (error 'symbol-macro-not-var :name name
                             :callee callee)))))

(defun all-symbol-binding-names (env &key stop-at-base)
  (let ((result (v-symbol-bindings env)))
    (labels ((stop-p (e)
               (or (and stop-at-base (typep e 'base-environment))
                   (eq e *global-env*))))
      (let ((current-env env))
        (loop :until (stop-p current-env) :do
           (setf current-env (v-parent-env current-env))
           (loop :for binding :in (v-symbol-bindings current-env) :do
              (push binding result)))))
    (let* ((dedup (remove-duplicates result :key #'first))
           (accessible (remove-if-not λ(apply #'binding-accesible-p env _)
                                      dedup))
           (names (mapcar #'first accessible)))
      names)))
