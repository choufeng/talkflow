#!/bin/bash
# 安装所有 git hooks
set -e
cp scripts/pre-commit .git/hooks/pre-commit
cp scripts/post-merge .git/hooks/post-merge
chmod +x .git/hooks/pre-commit .git/hooks/post-merge
echo "Hooks installed."
