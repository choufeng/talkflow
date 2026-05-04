#!/bin/bash
# 安装所有 git hooks
set -e
cp scripts/pre-commit .git/hooks/pre-commit
cp scripts/post-merge .git/hooks/post-merge
cp scripts/post-checkout .git/hooks/post-checkout
chmod +x .git/hooks/pre-commit .git/hooks/post-merge .git/hooks/post-checkout
echo "Hooks installed."
