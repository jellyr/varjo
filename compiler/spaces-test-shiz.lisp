(in-package :varjo)
(in-readtable fn:fn-reader)

;;
;; Spaces
;;

;;-------------------------------------------------------------------------
;; Varjo types

(def-v-type-class v-space (v-ephemeral-type) ())

(def-v-type-class v-svec (v-type)
  ((glsl-string :initform "vec4" :reader v-glsl-string)))

;;-------------------------------------------------------------------------
;; Metadata types

(def-metadata-kind space-meta ()
  uniform-name)

(def-metadata-kind spatial-meta ()
  in-space)

;;-------------------------------------------------------------------------
;; Spatial Vectors

(defmethod combine-metadata ((meta-a spatial-meta)
                             (meta-b spatial-meta))
  (let ((space-a (in-space meta-a))
        (space-b (in-space meta-b)))
    (if (eq space-a space-b)
        space-a
        (error "Space Analysis Failed: Could not establish at compile time which
space the resulting svec was in between:
~a
and
~a" space-a space-b))))

(defmethod combine-metadata ((meta-a null)
                             (meta-b standard-value-metadata))
  (values nil nil))

(defun get-space-from-svec (svec-code-obj env)
  (in-space (metadata-for-flow-id (flow-ids svec-code-obj) env)))

(defun add-space-to-meta (svec-flow-id space-type env)
  (assert (v-typep space-type 'v-space))
  (setf (metadata-for-flow-id svec-flow-id env)
        (make-instance 'spatial-meta :in-space space-type)))

(v-defspecial sv! ((x :float) (y :float) (z :float) (w :float))
  :return
  (let ((space (get-symbol-binding '*current-space* env)))
    (if space
        (let* ((space-type (v-type space))
               (flow-id (flow-id!))
               (type (type-spec->type 'v-svec flow-id))
               (args (list x y z w)))
          (add-space-to-meta flow-id space-type env)
          (values
           (merge-obs args
                      :type type
                      :current-line (format nil "vec4(~a, ~a, ~a, ~a)"
                                            (current-line x)
                                            (current-line y)
                                            (current-line z)
                                            (current-line w))
                      :to-block (mapcat #'to-block args)
                      :node-tree (ast-node!
                                  'sv!
                                  (mapcar #'node-tree args)
                                  type
                                  env
                                  env))
           env))
        (compile-form `(v! ,x ,y ,z ,w) env))))


;;-------------------------------------------------------------------------
;; Vector Space

(defmethod combine-metadata ((meta-a space-meta)
                             (meta-b space-meta))
  (let ((u-a (uniform-name meta-a))
        (u-b (uniform-name meta-b)))
    (if (eq u-a u-b)
        u-a
        (error "Space Analysis Failed: Could not establish at compile time which
space was returned between:
~a
and
~a" u-a u-b))))

(v-defmacro in (space &body body)
  `(space-boundary-convert
    (let ((*current-space* ,space))
      ,@body)))

(defmacro in (space &body body)
  (declare (ignore space body))
  (error "the 'in' macro can only be used inside shaders"))

;; this func isn't in the ast, which means the build won't
;; stabilize. Add a copy-code and replace the svec-* ast-node
(v-defspecial space-boundary-convert ((form-obj v-type))
  :return
  (if (v-typep (code-type form-obj) 'v-svec)
      (let* ((outer-space (get-symbol-binding '*current-space* env)))
        (if outer-space
            (let* ((inner-space (get-space-from-svec form-obj env))
                   (outer-name (get-uniform-name-from-space outer-space env))
                   (inner-name (get-uniform-name-from-space inner-space env))
                   (implicit-uniform-name
                    (symb inner-name :-to- outer-name :-mat4))
                   (injected (inject-implicit-uniform
                              implicit-uniform-name :mat4 env
                              `(get-transform ,inner-name ,outer-name))))
              (vbind (obj env) (compile-form `(svec-* ,form-obj ,injected) env)
                (add-space-to-meta (flow-ids obj) (v-type outer-space) env)
                (let ((ast (node-tree obj)))
                  (values
                   (copy-code
                    obj
                    :node-tree (ast-node! 'space-boundary-convert
                                          (ast-args ast)
                                          (ast-return-type ast)
                                          (ast-starting-env ast)
                                          (ast-ending-env ast)))
                   env))))
            (values
             (let ((ast (node-tree form-obj)))
               (copy-code
                form-obj
                :node-tree (ast-node! 'space-boundary-convert
                                      (list ast)
                                      (ast-return-type ast)
                                      (ast-starting-env ast)
                                      (ast-ending-env ast))))
             env)))))

(v-defun svec-* (a b) "(~a * ~a)" (v-mat4 v-svec) 1)
(v-defun svec-* (a b) "(~a * ~a)" (v-svec v-mat4) 0)

(defun get-uniform-name-from-space (space env)
  (let ((space-id (flow-ids space)))
    (or (first (find space-id (v-uniforms env) :test #'id=
                     :key λ(flow-ids (second _))))
        (error "Varjo: No uniform var found for space ~a" space))))