#!/bin/bash

# 年度が引数として指定されているか確認
if [ -z "$1" ]; then
    echo "Error: Please specify a year."
    echo "Usage: $0 2026"
    exit 1
fi

YEAR=$1
CONTENTS_DIR="src/contents/${YEAR}"

# 指定された年度のディレクトリが存在するか確認
if [ ! -d "$CONTENTS_DIR" ]; then
    echo "Error: Directory '$CONTENTS_DIR' not found."
    exit 1
fi

# Dockerfileのパス
DOCKERFILE_PATH="docker/Dockerfile"

# Dockerfileが存在するか確認
if [ ! -f "$DOCKERFILE_PATH" ]; then
    echo "Error: Dockerfile '$DOCKERFILE_PATH' not found."
    exit 1
fi

# Dockerイメージ名
IMAGE_NAME="tex-builder"

# Dockerイメージをビルド（既に存在する場合はスキップ）
echo "Building Docker image..."
docker build -t "$IMAGE_NAME" -f "$DOCKERFILE_PATH" . || {
    echo "Error: Failed to build Docker image."
    exit 1
}

# texファイルを検索してコンパイル
echo "Searching for tex files..."
TEX_FILES=$(find "$CONTENTS_DIR" -name "*.tex" -type f)

if [ -z "$TEX_FILES" ]; then
    echo "Warning: No tex files found under '$CONTENTS_DIR'."
    exit 0
fi

# 各texファイルをコンパイル
for TEX_FILE in $TEX_FILES; do
    echo "Compiling: $TEX_FILE"
    
    # texファイルのディレクトリとファイル名を取得
    TEX_DIR=$(dirname "$TEX_FILE")
    TEX_BASENAME=$(basename "$TEX_FILE")
    
    # Dockerコンテナを実行してコンパイル
    # 作業ディレクトリをマウントし、texファイルと同じディレクトリで実行
    docker run --rm \
        -v "$(pwd):/workdir" \
        -w "/workdir/$TEX_DIR" \
        "$IMAGE_NAME" \
        -interaction=nonstopmode \
        -output-directory=. \
        "$TEX_BASENAME" || {
        echo "Error: Failed to compile '$TEX_FILE'."
        continue
    }
    
    echo "Done: $TEX_FILE -> $TEX_DIR/$(basename "$TEX_FILE" .tex).pdf"
done

echo "All compilations completed."
