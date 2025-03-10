#!/bin/bash

# 应用补丁的函数
apply_patches() {
    local series_file="$1"  # series 文件路径
    local patch_dir="$2"    # 补丁文件所在的目录

    # 检查 series 文件是否存在
    if [[ ! -f "$series_file" ]]; then
        echo "Error: $series_file not found! No patches will be applied."
        return 1
    fi

    echo "Applying patches in order..."
    while IFS= read -r patch_file; do
        # 跳过空行或注释行
        [[ -z "$patch_file" || "$patch_file" == \#* ]] && continue

        patch_path="${patch_dir%/}/$patch_file"

        if [[ -f "$patch_path" ]]; then
            echo "Applying patch: $patch_file"
            patch -Np1 < "$patch_path" || { echo "Failed to apply patch: $patch_path"; exit 1; }  # 根据实际情况可能需要调整 `-p1`
        else
            echo "Warning: Patch file $patch_path not found!"
        fi
    done < "$series_file"
    
    echo "All patches applied successfully!"
}

# 撤销补丁的函数
reverse_patches() {
    local series_file="$1"  # series 文件路径
    local patch_dir="$2"    # 补丁文件所在的目录

    # 检查 series 文件是否存在
    if [[ ! -f "$series_file" ]]; then
        echo "Error: $series_file not found! No patches will be reversed."
        return 1
    fi

    echo "Reversing patches in reverse order..."
    tac "$series_file" | while IFS= read -r patch_file; do
        # 跳过空行或注释行
        [[ -z "$patch_file" || "$patch_file" == \#* ]] && continue

        patch_path="${patch_dir%/}/$patch_file"
        
        if [[ -f "$patch_path" ]]; then
            echo "Reversing patch: $patch_file"
            patch -Np1 -R < "$patch_path" || { echo "Failed to reverse patch: $patch_path"; exit 1; }  # 根据实际情况可能需要调整 `-p1`
        else
            echo "Warning: Patch file $patch_path not found!"
        fi
    done
    
    echo "All patches reversed successfully!"
}

# 使用示例：调用 apply_patches 或 reverse_patches 函数

# 假设你有以下参数：
# - `series_file` 是你的补丁列表文件路径。
# - `patch_dir` 是补丁文件所在的目录。

# 应用补丁
# apply_patches "path/to/your/series" "path/to/your/patches"

# 撤销补丁
# reverse_patches "path/to/your/series" "path/to/your/patches"
