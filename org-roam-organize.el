;;; org-roam-organize.el --- Organize roam-node references -*- lexical-binding: t; coding: utf-8 -*-

;;; commentary:

;; This package provides a comprehensive solution for organizing and managing
;; Org-roam nodes and their references. It implements a minor mode that offers
;; powerful tools for organizing your knowledge base with features for node
;; management, tag handling, backlink completion, and content organization.
;;
;; == OVERVIEW ==
;;
;; Org-roam-organize is designed to help users structure their Org-roam
;; knowledge base by providing tools to move, delete, update, and organize
;; nodes and their references. It's particularly useful for users who want to
;; maintain a hierarchical organization of their notes with Map of Contents (MOC)
;; files.
;;
;; == MAIN FEATURES ==
;;
;; 1. Node Management:
;;    - Move headlines and their corresponding node files between directories
;;    - Delete headlines and their associated files completely
;;    - Update node tags automatically during operations
;;
;; 2. Tag Processing:
;;    - Automatic tag replacement (e.g., :idea: to :note:)
;;    - Tag-based node counting and statistics
;;    - File tag updates across the knowledge base
;;
;; 3. Backlink Management:
;;    - Automatic insertion of missing backlinks for literature nodes
;;    - Citation-based reference completion
;;    - Link consistency maintenance
;;
;; 4. Statistical Functions:
;;    - Count nodes with specific tags
;;    - Update node statistics in MOC files
;;    - Maintain dynamic counters in properties
;;
;; 5. File Organization:
;;    - Move node files to structured directory layouts
;;    - Maintain directory organization based on node types
;;    - ID-based directory creation and management
;;
;; == CONFIGURATION VARIABLES ==
;;
;; Before using this package, you need to configure the following variables:
;;
;; - `org-roam-organize/directory': Root directory for org-roam-organize
;; - `org-roam-organize/fleeting-directory': Directory for temporary nodes
;; - `org-roam-organize/permanent-directory': Directory for permanent nodes
;; - `org-roam-organize/moc-directory': Directory for MOC (Map of Contents) files
;; - `org-roam-organize/top-moc-file': Path to the top-level MOC file
;; - `org-roam-organize/tag-id-alist': Association list mapping tags to node IDs
;; - `org-roam-organize/move-target-directory': Target directory for node movement
;; - `org-roam-organize/move-target-moc-file': Target MOC file for headline movement
;; - `org-roam-organize/move-source-tag': Source tag for automatic replacement
;; - `org-roam-organize/move-target-tag': Target tag for automatic replacement
;; - `org-roam-organize/move-target-directory-id-or-not': Whether to create ID-based directories
;; - `org-roam-organize/move-target-filename-id-or-not': Whether to use ID as filename
;;
;; == KEYBINDINGS ==
;;
;; The package provides the following keybindings when `org-roam-organize-mode' is active:
;;
;; - `C-c o h c': Move current headline and its corresponding node file
;; - `C-c o h d': Delete current headline and its corresponding node file
;; - `C-c o m m': Jump to the top-level MOC
;; - `C-c o m u': Update all MOC node statistics
;; - `C-c o r c': Complete missing backlinks for literature nodes
;;
;; Additional global keybindings:
;;
;; - `C-c o o': Toggle `org-roam-organize-mode'
;; - `C-c o c': Check configuration variables
;;
;; == USAGE ==
;;
;; 1. Configure the required variables in your Emacs configuration
;; 2. Enable `org-roam-organize-mode' with `M-x org-roam-organize-mode' or `C-c o o'
;; 3. Use the keybindings to organize your Org-roam knowledge base
;; 4. Run `org-roam-organize-check-variables' to verify your configuration
;;
;; == IMPLEMENTATION DETAILS ==
;;
;; The package uses Org-roam's database queries to efficiently manage node
;; relationships and maintain consistency across the knowledge base. It includes
;; robust error handling and validation to ensure operations are performed
;; safely and consistently.
;;
;; The mode includes a startup hook that validates configuration variables
;; and ensures the Emacs session is started in the appropriate directory
;; before enabling the functionality.
;;
;; == REQUIREMENTS ==
;;
;; - Org-mode
;; - Org-roam
;; - Emacs 26.1 or later
;;
;; == NOTES ==
;;
;; This package is designed for advanced Org-roam users who need sophisticated
;; organization tools for their knowledge base. The operations performed by
;; this package can modify files and directory structures, so it's recommended
;; to maintain backups of your Org-roam directory.

;;; code:

;; ==============================
;; 声明外部依赖
;; ==============================

(eval-when-compile
  (require 'cl-lib)
  (require 'org)
  (require 'org-element)
  (require 'org-roam))

;; ==============================
;; 用户变量定义
;; ==============================

(defgroup org-roam-organize
  nil
  "org-roam-organize variables"
  :group 'org-roam)

(defcustom org-roam-organize/directory
  nil
  "org-roam-organize 根目录"
  :type 'directory
  :group 'org-roam-organize)

(defcustom org-roam-organize/directory-p
  nil
  "Bool 型变量, 是否允许在非 org-roam-organize 根目录下启动 org-roam-organize, 默认值为nil"
  :type 'boolean
  :group 'org-roam-organize)

(defcustom org-roam-organize/fleeting-directory
  nil
  "Fleeting 节点所在目录"
  :type 'directory
  :group 'org-roam-organize)

(defcustom org-roam-organize/permanent-directory
  nil
  "Permanent 节点所在目录"
  :type 'directory
  :group 'org-roam-organize)

(defcustom org-roam-organize/moc-directory
  nil
  "MOC 节点所在目录"
  :type 'directory
  :group 'org-roam-organize)

(defcustom org-roam-organize/move-target-directory
  org-roam-organize/permanent-directory
  "整理节点移动文件时的目标目录"
  :type 'directory
  :group 'org-roam-organize)

(defcustom org-roam-organize/top-moc-file
  nil
  "顶层 MOC 的 绝对路径"
  :type 'file
  :group 'org-roam-organize)

(defcustom org-roam-organize/move-target-moc-file
  nil
  "整理节点移动headline时的目标 MOC 文件"
  :type 'file
  :group 'org-roam-organize)

(defcustom org-roam-organize/move-source-tag
  nil
  "整理节点移动headline时的源标签"
  :type 'string
  :group 'org-roam-organize)

(defcustom org-roam-organize/move-target-tag
  nil
  "整理节点移动headline时的目标标签"
  :type 'string
  :group 'org-roam-organize)

(defcustom org-roam-organize/move-target-directory-id-or-not
  t
  "Bool型变量, 默认值为t. 整理节点移动文件时的是否根据ID创建目标目录. "
  :type 'boolean
  :group 'org-roam-organize)

(defcustom org-roam-organize/move-target-filename-id-or-not
  nil
  "Bool型变量, 默认值为nil. 整理节点移动文件时的是否将移动后的文件名称设置为id. "
  :type 'boolean
  :group 'org-roam-organize)

(defcustom org-roam-organize/tag-id-alist
  '((nil . nil))
  "MOC 对应标签与 MOC ID 的映射表"
  :type 'alist
  :group 'org-roam-organize)

(defcustom org-roam-organize/capture-templates
  nil
  "创建 MOC 文件所用捕获模板"
  :type 'sexp
  :group 'org-roam-organize)

;; ==============================
;; 常量定义
;; ==============================

(defconst org-roam-organize//variable-type-alist
  '((org-roam-organize/directory . directory)
    (org-roam-organize/moc-directory . directory)
    (org-roam-organize/fleeting-directory . directory)
    (org-roam-organize/permanent-directory . directory)
    (org-roam-organize/directory-p . boolean)
    (org-roam-organize/tag-id-alist . list)
    (org-roam-organize/top-moc-file . file)
    (org-roam-organize/move-target-directory . directory)
    (org-roam-organize/move-target-moc-file . file)
    (org-roam-organize/move-source-tag . string)
    (org-roam-organize/move-target-tag . string)
    (org-roam-organize/move-target-directory-id-or-not . boolean)
    (org-roam-organize/move-target-filename-id-or-not . boolean)
    (org-roam-organize/capture-templates . list)))

;; ==============================
;; 内部函数
;; ==============================

;; 变量检查
(defun org-roam-organize--check-variables (root_dir alist)
  (if (listp alist)
      (let* ((result_bool t)
	     (result_message (concat "All org-roam-organize/* variables are as follow.\n" ))
	     (add_to_result_message_
              (lambda (var_name var_value var_expected_type type_p_)
		(setq result_message
		      (concat
                       result_message
                       (format 
			"- %s? %s \n" 
			var_name 
			var_value)
                       (format 
			"  %s? %s (should be t)\n"
			var_expected_type 
			(funcall type_p_ var_value))
                       (when (eq var_expected_type 'directory)
			 (when (file-directory-p var_value)
			   (format
			    "  in org-roam-organize root directory? %s (should be t)\n"
			    (file-in-directory-p
			     (expand-file-name var_value)
			     (expand-file-name root_dir) )))))))))
	(dolist (pair alist)
          (let* ((var_name (car pair))
		 (var_value (symbol-value var_name))
		 (var_expected_type (cdr pair))
		 (add_to_result_message_short_ 
		  (lambda (type_p_) 
                    (funcall 
                     add_to_result_message_ 
                     var_name 
                     var_value 
                     var_expected_type 
                     type_p_))))
            (cond
             ((eq var_expected_type 'list)
              (funcall add_to_result_message_short_ 'listp)
              (unless (and (boundp var_name) (listp var_value))
		(setq result_bool nil)))
             ((eq var_expected_type 'string)
              (funcall add_to_result_message_short_ 'stringp)
              (unless (and (boundp var_name) (stringp var_value))
		(setq result_bool nil)))
             ((eq var_expected_type 'directory)
              (funcall add_to_result_message_short_ 'file-directory-p)
              (unless (and 
                       (boundp var_name) 
                       (stringp var_value)
                       (file-directory-p var_value)
                       (file-in-directory-p
			(expand-file-name var_value)
			(expand-file-name root_dir)))
		(setq result_bool nil)))
             ((eq var_expected_type 'file)
              (funcall add_to_result_message_short_ 'file-exists-p)
              (unless (and 
                       (boundp var_name) 
                       (stringp var_value) 
                       (file-exists-p var_value))
		(setq result_bool nil)))
             ((eq var_expected_type 'boolean)
              (funcall add_to_result_message_short_ 'booleanp)
              (unless
                  (and (boundp var_name) (booleanp var_value))
		(setq result_bool nil)))
             (t (error "Unknown type: %s" var_expected_type)))))
	(cons result_bool result_message))
    (error "Inner Variable org-roam-organize//variable-type-alist is NOT defined properly. ")))

;; hash表转换为alist
(defun org-roam-organize--hash-table-to-alist (hash_table)
  (when org-roam-organize-mode
    (let (result)
      (maphash 
       (lambda 
         (key value)
         (push (cons key value) result))
       hash_table)
      (nreverse result))))  ;; nreverse to reverse the list back to original order

;; alist转换为hash表
(defun org-roam-organize--alist-to-hash-table (alist)
  (when org-roam-organize-mode
    (let ((ht (make-hash-table :test 'equal)))
      (dolist (row alist)
        (puthash 
         (car row)
         (append (gethash (car row) ht) (list (cdr row)))
         ht))
      ht)))

;; 替换tag
(defun org-roam-organize--update-filetag (file source_tag target_tag)
  "In FILE, replace SOURCE_TAG with TARGET_TAG in #+FILETAGS: line only. If no #+FILETAGS: line exists, do nothing."
  (when org-roam-organize-mode
    (with-current-buffer (find-file-noselect file)
      (goto-char (point-min))
      (if (re-search-forward "^#\\+FILETAGS:[ \t]*\\(.*\\)$" nil t)
          (let* ((old (match-string 1))
		 ;; 保留所有原有 tag，只替换 source_tag
		 (new (replace-regexp-in-string (concat ":" source_tag ":") (concat ":" target_tag ":") old)))
            (unless (string= old new)
              ;; 用 new 覆盖 old
              (replace-match new nil nil nil 1)
              (save-buffer)
              (message "Updated FILETAGS in %s: %s → %s" file source_tag target_tag)))
        (message "No #+FILETAGS: found in %s; skipping tag update" file)))))

;; 从光标获取headline中通过id的引用指向的node的信息
(defun org-roam-organize--get-node-info-from-cite-in-headline (&optional pos)
  (when org-roam-organize-mode
    (let* ((pos (or pos (point)))
           (el (save-excursion (goto-char pos) (org-element-at-point)))
           (title (org-element-property :raw-value el))
           id node file)
      ;; 检查 headline 类型
      (unless (eq (org-element-type el) 'headline)
        (user-error "Not on a headline"))
      ;; 提取 id
      (setq id 
            (if (string-match "\\[\\[id:\\([^]]+\\)\\]\\[" title)
		(match-string 1 title)
              (user-error "No [[id:...]] link found in this headline")))
      ;; 获取 org-roam node
      (setq node 
            (or 
             (org-roam-node-from-id id)
             (user-error "No org-roam node with id %s" id)))
      ;; 返回 plist
      (list :id id :node node))))

;; 对给定tag列表, 查出数据库中表nodes内level=0的node数量
(defun org-roam-organize--count-nodes-with-given-tag-list (tag_list &optional hash_to_alist)
  "Return an alist of (TAG . COUNT) for level=0 nodes, given a list of TAGS. Includes all tags in TAG_LIST, assigning zero to those not present in DB. The input parameter must be a 1-dim' list or vector. "
  (when org-roam-organize-mode
    (let* ((tag_count (make-hash-table :test 'equal))
           (result
            (org-roam-db-query
             [:select [t:tag (funcall count t:tag)]
		      :from (as tags t)
		      :join (as nodes n)
		      :on (and (= n:level 0) (= n:id t:node_id))
		      :where (in t:tag $v1)
		      :group-by t:tag]
             (vconcat tag_list))))
      (dolist (tag tag_list)
        (puthash tag 0 tag_count))
      (dolist (item result)
        (let ((tag (nth 0 item))
              (count (nth 1 item)))
          (puthash tag count tag_count)))
      (if hash_to_alist
          (org-roam-organize--hash-table-to-alist tag_count)
        tag_count))))

;; 检查需要却没有被插入link于给定node的node的id
(defun org-roam-organize--check-file-node-no-linked-headline (tag_id table col)
  "Given TAG_ID (alist of TAG . ID), return an alist of (source_id . dest_id_list) where dest_id_list contains level=0 node ids for TAG not already linked from source_id."
  (when org-roam-organize-mode
    (let* ((tag_list
            (mapcar (lambda (e) (format "%s" (car e))) tag_id))
           (id_list
            (mapcar (lambda (e) (format "%s" (cdr e))) tag_id))
           (result_tag_all_id
            (mapcar 
             (lambda (x) (cons (nth 0 x) (nth 1 x)))
             (org-roam-db-query 
              (vector
               :select (vector (intern (concat "t:" col)) (intern "t:node_id"))
               :from (list 'as (intern (concat table)) 't)
               :join '(as nodes n) :on '(and (= n:level 0) (= n:id t:node_id))
	       :where (list 'in (intern (concat "t:" col)) '$v1))
              (vconcat tag_list))))
           (result_id_linked_id
            (mapcar 
             (lambda (x) (cons (nth 0 x) (nth 1 x)))
             (org-roam-db-query
              [:select [l:source l:dest]
		       :from (as links l)
		       :join (as nodes n) :on (and (= n:level 0) (= n:id l:dest))
		       :where (and (= l:type "id") (in l:source $v1))]
              (vconcat id_list))))
           (tag_to_nodes (org-roam-organize--alist-to-hash-table result_tag_all_id))
           (source_to_linked (org-roam-organize--alist-to-hash-table result_id_linked_id)))
      (cl-loop 
       for pair in tag_id
       for tag    = (car pair)
       for source = (cdr pair)
       for all_nodes   = (gethash tag tag_to_nodes)
       for linked_nodes = (gethash source source_to_linked)
       collect
       (cons 
        source
        (let ((linked-ht (make-hash-table :test 'equal)))
          (dolist (x linked_nodes) 
            (puthash x t linked-ht))
          (seq-filter 
           (lambda (x) (not (gethash x linked-ht)))
           all_nodes)))))))

;; 在给定id的node中插入指定形式的id型link
(defun org-roam-organize--insert-id-type-link-headline (pair)
  "Insert org entries for level0 nodes given SOURCE_DEST_ALIST. PAIR is a cons cell of (source_id . dest_id_list), where source_id is a string and dest_id_list is a list of node IDs (may be empty)."
  (when org-roam-organize-mode
    (let* ((source_id (car pair))
           (dest_ids (cdr pair)))
      (when dest_ids
        (dolist (id dest_ids)
          (let* ((node (org-roam-node-from-id id))
		 (source-node (org-roam-node-from-id source_id)))
            (when (and node source-node)
              (let* ((content 
                      (format "** [[id:%s][%s]]\n"
			      (org-roam-node-id node)
			      (org-roam-node-title node))))
                (with-current-buffer (find-file-noselect (org-roam-node-file source-node))
                  (goto-char (point-max))
                  (insert content)
                  (save-buffer))
                (message "%s" content)))))))))

;; ==============================
;; 可调用结构函数
;; ==============================

;; 变量检查
(defun org-roam-organize-check-variables ()
  (interactive)
  (message "%s" (org-roam-organize--check-variables org-roam-organize/directory org-roam-organize//variable-type-alist)))

;; 创建目录
(defun org-roam-organize-create-directory ()
  (interactive)
  (let ((dir_list (list org-roam-organize/directory 
                        org-roam-organize/moc-directory
		                    org-roam-organize/fleeting-directory
                        org-roam-organize/permanent-directory)))
       (dolist (dir dir_list)
              (unless (file-exists-p dir)
                      (make-directory dir t)))))

;; ==============================
;; 可调用功能函数
;; ==============================

;; 打开顶层moc
(defun org-roam-organize-goto-map-of-maps ()
  "Open the top-level Map of Contents file using its file path."
  (interactive)
  (if org-roam-organize-mode
      (let ((file_path org-roam-organize/top-moc-file))
        (cond
         ((not file_path)
          (message "Top MOC file path is not defined. Please check your configuration."))
         ((not (file-exists-p file_path))
          (message "Top MOC file not found at path: %s" file_path))
         (t
          (find-file file_path)
          ;; Optional enhancements (kept commented as in original)
          ;; (display-line-numbers-mode 1)
          ;; (font-lock-mode 1)
          ;; (font-lock-fontify-buffer)
          (message "Opened Top MOC: %s" (file-name-nondirectory file_path)))))
    (message "[WARNING] This function requires org-roam-organize-mode to be enabled (current value: %s)" 
             org-roam-organize-mode)))

;; 更改moc中形如[[id][title]]的headline及其对应node文件的位置
(defun org-roam-organize-headline-move (source_pos)
  "Move headline at source_pos to `org-roam-organize/move-target-moc-file`. Update roam-node tags (:idea: -> :note:), move its file to `org-roam-organize/move-target-directory/${id}/`, and save involved files."
  (interactive (list (point)))
  (if (and
       org-roam-organize-mode)
      (let* ((source_buf (current-buffer)) ; 提取id和node信息
             (info (org-roam-organize--get-node-info-from-cite-in-headline source_pos))
             (id   (plist-get info :id))
             (node (plist-get info :node))
             (old_file (org-roam-node-file node))
             (tags     (org-roam-node-tags node)) 
             (source_tag org-roam-organize/move-source-tag)
             (target_tag org-roam-organize/move-target-tag)
             (new-tags 
              (mapcar 
               (lambda (tag) (if (string= tag source_tag) target_tag tag))
               tags))
             (target_dir_bool_id_or_not org-roam-organize/move-target-directory-id-or-not)
             (dir 
              (if target_dir_bool_id_or_not
		  (expand-file-name id org-roam-organize/move-target-directory)
		(expand-file-name org-roam-organize/move-target-directory)))
             (filename_bool_id_or_not org-roam-organize/move-target-filename-id-or-not)
             (new_file 
              (if filename_bool_id_or_not
		  (expand-file-name (concat id ".org") dir)
		(expand-file-name (file-name-nondirectory old_file) dir)))
             (target_buf (find-file-noselect org-roam-organize/move-target-moc-file))
             ;; (permanent-target (with-current-buffer target_buf (point-max-marker)))
	     )
	(unless (file-exists-p dir)
          (make-directory dir t))
	(org-roam-organize--update-filetag old_file source_tag target_tag)
	;; 移动文件
	(unless (string= 
		 (expand-file-name old_file)
		 (expand-file-name new_file))
          (rename-file old_file new_file t)
	  )
	(save-excursion
          (goto-char source_pos)
          (unless (org-at-heading-p)
            (org-back-to-heading t)) ; 确保在 headline 开头
          (let ((subtree-str (org-copy-subtree t)))
            (org-cut-subtree)
            (with-current-buffer (find-file-noselect org-roam-organize/move-target-moc-file)
              (goto-char (point-max))
              (insert subtree-str))))
	(save-buffer) 
	(with-current-buffer source_buf 
          (save-buffer))
	(with-current-buffer target_buf 
          (save-buffer))
	(with-current-buffer (find-file-noselect new_file) 
          (save-buffer))
	(message "Moved node with id:%s, updated moc headline and files tag, moved file, and saved files." id)
	;; (run-with-idle-timer 0.5 nil #'org-roam-db-sync)
	)
    (message "[WARNING] This function is not valid, since org-roam-organize-mode = %s. " org-roam-organize-mode)))

;; 删除moc中含[id]headline及对应的node
(defun org-roam-organize-headline-delete (&optional pos)
  (interactive (list (point)))
  (if org-roam-organize-mode
      (let* ((info (org-roam-organize--get-node-info-from-cite-in-headline pos))
             (id (plist-get info :id))
             (node (plist-get info :node))
             (tags (org-roam-node-tags node))
             (dir (expand-file-name id org-roam-organize/move-target-directory))
             (file (org-roam-node-file node))
             (target_tag org-roam-organize/move-target-tag)
             (target_dir_bool_id_or_not org-roam-organize/move-target-directory-id-or-not))
	(delete-file file)
	(when 
            (and
             (member target_tag tags)
             target_dir_bool_id_or_not
             (file-directory-p dir))
          (delete-directory dir t))
	(save-excursion
          (org-back-to-heading t)
          (org-cut-subtree))
	(message "Deleted node with id:%s" id)
	(save-buffer))
    (message "[WARNING] This function is not valid, since org-roam-organize-mode = %s. " org-roam-organize-mode)))

;; 更新moc
(defun org-roam-organize-update-mocs ()
  "Update Org-roam nodes with tag count information. For each tag in `tag-id-alist`, count how many nodes have that tag, and write the count into the corresponding node's property field."
  (interactive)
  (if org-roam-organize-mode
      (let ((tag_id org-roam-organize/tag-id-alist)
            (sth_unexpected nil))
	;; 开始提示
	(message "[INFO] Begin Check and Update. ")
	(org-roam-db)
	(cond
         ((not tag_id)
          (progn
            (setq sth_unexpected t)
            (message "[WARNING] No tag-id map found. ")))
         (t
          (let* ((inhibit-message t)
		 (tag_list (mapcar (lambda (e) (format "%s" (car e))) tag_id))
		 (tag_count_hash (org-roam-organize--count-nodes-with-given-tag-list tag_list))
		 (source_dest_alist (org-roam-organize--check-file-node-no-linked-headline tag_id "tags" "tag")))
            (dolist (entry tag_id)
              (let* ((tag (car entry))
                     (id (cdr entry))
                     (count (gethash tag tag_count_hash))
                     (marker (org-id-find id 'marker)))
                (if
                    (and
                     marker
                     count)
                    (progn
                      (with-current-buffer (marker-buffer marker)
			(goto-char marker)
			(let ((field (format "NUM_OF_%s_NODES" (upcase tag))))
                          (org-entry-put (point) field (number-to-string count))
                          (save-buffer))))
                  (progn
                    (setq sth_unexpected t)
                    (message "[WARNING] SQL query failed or ID input is invalid. ")))))
            (dolist (pair source_dest_alist)
              (org-roam-organize--insert-id-type-link-headline pair)))))
	(if sth_unexpected
            (message "[WARNING] End, but something UNEXPECTED happened, please check *Message*. ")
          (message "[INFO] Update Successful. ")))
    (message "[WARNING] This function is not valid, since org-roam-organize-mode = %s. " org-roam-organize-mode)))

;; 文献节点反链补全
(defun org-roam-organize-ref-backlink-complete ()
  (interactive)
  (if org-roam-organize-mode
      (progn
	(message "[INFO] Begin Check and Insert. ")
	(org-roam-db)
	(let* ((ref_id (mapcar
			(lambda (x) (cons (nth 0 x) (nth 1 x)))
			(org-roam-db-query
			 [:select [r:ref r:node_id]
				  :from (as refs r)
				  :join (as nodes n) :on (and (= level 0) (= n:id r:node_id))
				  :where (= r:type "cite")])))
               (source_dest_alist (org-roam-organize--check-file-node-no-linked-headline ref_id "citations" "cite_key")))
          (message "[INFO] Check Complete. Insert backlinks Start up. ")
          (dolist 
              (pair source_dest_alist)
            (org-roam-organize--insert-id-type-link-headline pair))
          (message "[INFO] Insert Complete. ")))
    (message "[WARNING] This function is not valid, since org-roam-organize-mode = %s. " org-roam-organize-mode)))

;; ==============================
;; Minor-Mode
;; ==============================

;; defination
(define-minor-mode org-roam-organize-mode
  "org-roam-organize mode"
  :lighter " Organize"
  :keymap 
  (let ((oro_keymap (make-sparse-keymap)))
    (define-key oro_keymap (kbd "C-c o h c") #'org-roam-organize-headline-move)
    (define-key oro_keymap (kbd "C-c o h d") #'org-roam-organize-headline-delete)
    (define-key oro_keymap (kbd "C-c o m m") #'org-roam-organize-goto-map-of-maps)
    (define-key oro_keymap (kbd "C-c o m u") #'org-roam-organize-update-mocs)
    (define-key oro_keymap (kbd "C-c o r c") #'org-roam-organize-ref-backlink-complete)
    oro_keymap)
  ;; :group nil
  :global t
  :init-value nil)

;; hook
(add-hook 'org-roam-organize-mode-hook
	  (lambda () 
	    (let* ((root_dir 
		    (when (boundp 'org-roam-organize/directory) 
		      org-roam-organize/directory))
		   (check_result
		    (when (boundp 'org-roam-organize//variable-type-alist)
		      (org-roam-organize--check-variables root_dir org-roam-organize//variable-type-alist))))
	      (cond
               ((not (car check_result))
		(setq org-roam-organize-mode nil)
		(message (concat
			  "[WARNING] There be variablies not defined properly. "
			  "Org Roam Organize Mode setup failed.\n"
			  (cdr check_result))))
              ((not (or
        org-roam-organize/directory-p
        (file-in-directory-p
          (expand-file-name default-directory)
          (expand-file-name root_dir))))
		(setq org-roam-organize-mode nil)
		(message (concat (format 
				  "[WARNING] Not startup Emacs under %s. " 
				  root_dir)
				 "Org Roam Organize Mode setup failed. ")))
               (t
		(unless (featurep 'org) (require 'org))
		(unless (featurep 'org-element) (require 'org-element))
		(unless (featurep 'org-roam) (require 'org-roam))
		(unless (featurep 'cl-lib) (require 'cl-lib))
    (dolist (tmpl org-roam-organize/capture-templates)
            (unless (assoc (car tmpl) org-roam-capture-templates) ; 仅当快捷键不存在时添加
                    (setq org-roam-capture-templates
                          (append org-roam-capture-templates (list tmpl))))))))))

(provide 'org-roam-organize)
;;; org-roam-organize.el ends here