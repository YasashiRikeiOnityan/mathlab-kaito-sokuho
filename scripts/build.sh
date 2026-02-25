#!/bin/bash

# 年度が引数として指定されているか確認
if [ -z "$1" ]; then
    echo "Error: Please specify a year."
    echo "Usage: $0 YEAR [UNIVERSITY] [PROBLEM]"
    echo "  YEAR: Year (required, e.g., 2026)"
    echo "  UNIVERSITY: University name (optional: tokyo, kyoto, science-tokyo)"
    echo "  PROBLEM: Problem number (optional: 1, 2, 3, 4, 5, 6)"
    echo ""
    echo "Examples:"
    echo "  $0 2026          # Compile all files in src/contents/2026"
    echo "  $0 2026 tokyo    # Compile all files in src/contents/2026/tokyo"
    echo "  $0 2026 tokyo 1  # Compile src/contents/2026/tokyo/1.tex"
    exit 1
fi

YEAR=$1
UNIVERSITY=$2
PROBLEM=$3

# 大学名の検証
if [ -n "$UNIVERSITY" ]; then
    case "$UNIVERSITY" in
        tokyo|kyoto|science-tokyo)
            ;;
        *)
            echo "Error: Invalid university name '$UNIVERSITY'."
            echo "Valid university names: tokyo, kyoto, science-tokyo"
            exit 1
            ;;
    esac
fi

# 問題番号の検証
if [ -n "$PROBLEM" ]; then
    case "$PROBLEM" in
        1|2|3|4|5|6)
            ;;
        *)
            echo "Error: Invalid problem number '$PROBLEM'."
            echo "Valid problem numbers: 1, 2, 3, 4, 5, 6"
            exit 1
            ;;
    esac
fi

# 問題番号が指定されている場合は大学名も必須
if [ -n "$PROBLEM" ] && [ -z "$UNIVERSITY" ]; then
    echo "Error: University name is required when problem number is specified."
    exit 1
fi

# コンパイル対象のディレクトリを決定
if [ -n "$PROBLEM" ]; then
    # 第3引数まで指定：特定のファイルをコンパイル
    CONTENTS_DIR="src/contents/${YEAR}/${UNIVERSITY}"
    TEX_FILE="${CONTENTS_DIR}/${PROBLEM}.tex"
    
    if [ ! -f "$TEX_FILE" ]; then
        echo "Error: File '$TEX_FILE' not found."
        exit 1
    fi
    
    TEX_FILES="$TEX_FILE"
elif [ -n "$UNIVERSITY" ]; then
    # 第2引数まで指定：その年度・大学のすべてのtexファイルをコンパイル
    CONTENTS_DIR="src/contents/${YEAR}/${UNIVERSITY}"
    
    if [ ! -d "$CONTENTS_DIR" ]; then
        echo "Error: Directory '$CONTENTS_DIR' not found."
        exit 1
    fi
    
    TEX_FILES=$(find "$CONTENTS_DIR" -maxdepth 1 -name "*.tex" -type f)
    
    if [ -z "$TEX_FILES" ]; then
        echo "Warning: No tex files found under '$CONTENTS_DIR'."
        exit 0
    fi
else
    # 第1引数のみ：その年度のすべてのtexファイルをコンパイル
    CONTENTS_DIR="src/contents/${YEAR}"
    
    if [ ! -d "$CONTENTS_DIR" ]; then
        echo "Error: Directory '$CONTENTS_DIR' not found."
        exit 1
    fi
    
    TEX_FILES=$(find "$CONTENTS_DIR" -name "*.tex" -type f)
    
    if [ -z "$TEX_FILES" ]; then
        echo "Warning: No tex files found under '$CONTENTS_DIR'."
        exit 0
    fi
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

# Dockerイメージをビルド（Dockerfile /src/sty に変更がない場合はスキップ）
# NOTE: `docker build` はキャッシュヒットでも Docker Desktop の「ビルド履歴」に記録が残るため、
#       変更がないときはそもそも `docker build` を叩かないようにする。
get_hash_cmd() {
    if command -v shasum >/dev/null 2>&1; then
        echo "shasum -a 256"
    elif command -v sha256sum >/dev/null 2>&1; then
        echo "sha256sum"
    else
        echo ""
    fi
}

HASH_CMD=$(get_hash_cmd)
if [ -z "$HASH_CMD" ]; then
    echo "Warning: 'shasum' or 'sha256sum' not found. Building Docker image every time."
    NEED_BUILD=1
else
    CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/mathlab-kaito-sokuho"
    CACHE_FILE="${CACHE_DIR}/tex-builder.build-input.sha256"
    mkdir -p "$CACHE_DIR"

    compute_build_input_hash() {
        {
            $HASH_CMD "$DOCKERFILE_PATH"
            if [ -d "src/sty" ]; then
                find "src/sty" -type f -print | LC_ALL=C sort | while IFS= read -r f; do
                    $HASH_CMD "$f"
                done
            fi
        } | $HASH_CMD | awk '{print $1}'
    }

    CURRENT_HASH=$(compute_build_input_hash)
    SAVED_HASH=""
    if [ -f "$CACHE_FILE" ]; then
        SAVED_HASH=$(cat "$CACHE_FILE")
    fi

    NEED_BUILD=0
    if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        NEED_BUILD=1
    elif [ "$CURRENT_HASH" != "$SAVED_HASH" ]; then
        NEED_BUILD=1
    fi
fi

if [ "$NEED_BUILD" -eq 1 ]; then
    echo "Building Docker image..."
    docker build -t "$IMAGE_NAME" -f "$DOCKERFILE_PATH" . || {
        echo "Error: Failed to build Docker image."
        exit 1
    }
    if [ -n "$HASH_CMD" ]; then
        echo "$CURRENT_HASH" > "$CACHE_FILE"
    fi
else
    echo "Docker image is up to date. Skipping build."
fi

# texファイルを検索してコンパイル
echo "Searching for tex files..."

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
