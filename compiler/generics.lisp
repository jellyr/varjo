(in-package :varjo)

(defgeneric compile-form (code env))
(defgeneric v-place-function-p (f))
(defgeneric type->type-spec (type))
(defgeneric v-true-type (object))
(defgeneric v-glsl-size (type))
(defgeneric v-type-eq (a b &optional env))
(defgeneric v-typep (a b &optional env))
(defgeneric v-casts-to (from-type to-type env))
(defgeneric v-casts-to-p (from-type to-type env))
(defgeneric post-initialise (object))
(defgeneric v-code-type-eq (a b &optional env))
(defgeneric v-make-value (type env &key glsl-name flow-ids function-scope read-only))
(defgeneric get-flow-id-for-stem-cell (stem-cell-symbol e))
(defgeneric dedup-function (code e))
(defgeneric used-symbol-macros (e))
(defgeneric (setf used-symbol-macros) (value e))
(defgeneric used-macros (e))
(defgeneric used-external-functions (e))
(defgeneric (setf used-external-functions) (value e))
(defgeneric (setf used-macros) (value e))
(defgeneric used-compiler-macros (e))
(defgeneric (setf used-compiler-macros) (value e))
(defgeneric valid-for-contextp (func env))
(defgeneric add-macro (macro-name macro context env))
(defgeneric %get-macro-spec (macro-name env))
(defgeneric v-mboundp (macro-name env))
(defgeneric add-symbol-macro (macro-name macro context env))
(defgeneric %get-symbol-macro-spec (macro-name env))
(defgeneric add-compiler-macro (macro-name macro context env))
(defgeneric %get-compiler-macro-spec (macro-name env))
(defgeneric add-var (var-name val env))
(defgeneric %add-var (var-name val env))
(defgeneric v-boundp (var-name env))
(defgeneric add-equivalent-name (existing-name new-name))
(defgeneric add-function (func-name func-spec env))
(defgeneric %add-function (func-name func-spec env))
(defgeneric get-function-by-name (func-name env))
(defgeneric %get-functions-by-name (func-name env))
(defgeneric special-raw-argp (func))
(defgeneric special-func-argp (func))
(defgeneric special-basic-argp (func))
(defgeneric v-fboundp (func-name env))
(defgeneric ast-kindp (node kind))
(defgeneric ast-typep (node type))
(defgeneric origin-name (origin))
(defgeneric val-origins (node &optional error-on-missingp))
(defgeneric indent (input &optional count))
(defgeneric v-fake-type (object))
(defgeneric v-special-functionp (func))
(defgeneric v-element-type (object))
(defgeneric merge-obs (objs &key type current-line to-block
                              to-top out-vars returns multi-vals
                              stemcells out-of-scope-args flow-ids
			      place-tree mutations node-tree))
(defgeneric copy-code (code-obj &key type current-line to-block to-top
                                  out-vars returns multi-vals
                                  stemcells out-of-scope-args flow-ids
				  place-tree mutations node-tree))
(defgeneric flow-id-origins (node &optional error-on-missingp context))

(defgeneric push-non-implicit-function-for-dedup (code func e))
(defgeneric func-need-arguments-compiledp (func))
(defgeneric get-macro (macro-name env))
(defgeneric get-symbol-macro (macro-name env))
(defgeneric get-compiler-macro (macro-name env))
(defgeneric get-var (var-name env))
(defgeneric raw-ids (flow-id))
(defgeneric add-external-function (name in-args uniforms code
				   &optional valid-glsl-versions))
(defgeneric delete-external-function (name in-args-types))
(defgeneric record-func-usage (func env))
(defgeneric v-name-map (env))
