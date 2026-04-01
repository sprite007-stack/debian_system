#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Video Rename / Optional Move Script
#
# Features:
#   1. Detect first-level subfolders and let you choose:
#        - flatten   : move subfolder videos into root first
#                      then delete empty subfolders
#        - subfolder : process each subfolder separately
#        - skip      : ignore subfolders
#   2. Read video duration + resolution with ffprobe
#   3. Sort videos longest -> shortest
#   4. Choose base name mode:
#        - manual
#        - folder
#   5. Choose action:
#        - rename only
#        - rename + move into resolution folders
#
# Usage:
#   chmod +x video_rename_then_move.sh
#   ./video_rename_then_move.sh /path/to/videos
#
# Dry run:
#   DRY_RUN=1 ./video_rename_then_move.sh /path/to/videos
# ============================================================

ROOT_DIR="${1:-.}"
DRY_RUN="${DRY_RUN:-0}"

VIDEO_EXTENSIONS=(
  "*.mp4" "*.mkv" "*.mov" "*.avi" "*.wmv" "*.flv"
  "*.m4v" "*.mpg" "*.mpeg" "*.webm" "*.ts" "*.mts" "*.m2ts"
)

if ! command -v ffprobe >/dev/null 2>&1; then
  echo "Error: ffprobe is required but not installed."
  echo "Install ffmpeg first."
  exit 1
fi

if [[ ! -d "$ROOT_DIR" ]]; then
  echo "Error: Directory does not exist: $ROOT_DIR"
  exit 1
fi

ROOT_DIR="$(cd "$ROOT_DIR" && pwd)"

cleanup_name() {
  local input="$1"
  input="${input// /_}"
  input="$(echo "$input" | sed 's/[^A-Za-z0-9._-]/_/g')"
  input="$(echo "$input" | sed 's/__*/_/g; s/^_//; s/_$//')"
  echo "$input"
}

safe_mv() {
  local src="$1"
  local dst="$2"

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[DRY RUN] mv -- \"$src\" \"$dst\""
  else
    mv -- "$src" "$dst"
  fi
}

safe_mkdir() {
  local dir="$1"
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[DRY RUN] mkdir -p -- \"$dir\""
  else
    mkdir -p -- "$dir"
  fi
}

safe_rmdir() {
  local dir="$1"
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[DRY RUN] rmdir -- \"$dir\""
  else
    rmdir -- "$dir"
  fi
}

get_video_metadata() {
  local file="$1"
  local width height duration

  width="$(ffprobe -v error -select_streams v:0 \
    -show_entries stream=width \
    -of csv=p=0 "$file" 2>/dev/null | head -n1)"

  height="$(ffprobe -v error -select_streams v:0 \
    -show_entries stream=height \
    -of csv=p=0 "$file" 2>/dev/null | head -n1)"

  duration="$(ffprobe -v error \
    -show_entries format=duration \
    -of csv=p=0 "$file" 2>/dev/null | head -n1)"

  [[ -n "$width" && -n "$height" && -n "$duration" ]] || return 1
  echo "${duration}|${width}|${height}"
}

get_resolution_folder() {
  local width="$1"
  local height="$2"
  local max_dim="$width"

  if (( height > width )); then
    max_dim="$height"
  fi

  if (( max_dim >= 7680 )); then
    echo "8K"
  elif (( max_dim >= 3840 )); then
    echo "4K"
  elif (( max_dim >= 2560 )); then
    echo "1440p"
  elif (( max_dim >= 1920 )); then
    echo "1080p"
  elif (( max_dim >= 1280 )); then
    echo "720p"
  elif (( max_dim >= 854 )); then
    echo "480p"
  else
    echo "other"
  fi
}

find_video_files() {
  local search_dir="$1"
  local maxdepth_arg="${2:-}"

  if [[ -n "$maxdepth_arg" ]]; then
    find "$search_dir" -maxdepth "$maxdepth_arg" -type f \( \
      -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.mov" -o -iname "*.avi" -o \
      -iname "*.wmv" -o -iname "*.flv" -o -iname "*.m4v" -o -iname "*.mpg" -o \
      -iname "*.mpeg" -o -iname "*.webm" -o -iname "*.ts" -o -iname "*.mts" -o \
      -iname "*.m2ts" \
    \) -print0
  else
    find "$search_dir" -type f \( \
      -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.mov" -o -iname "*.avi" -o \
      -iname "*.wmv" -o -iname "*.flv" -o -iname "*.m4v" -o -iname "*.mpg" -o \
      -iname "*.mpeg" -o -iname "*.webm" -o -iname "*.ts" -o -iname "*.mts" -o \
      -iname "*.m2ts" \
    \) -print0
  fi
}

collect_videos_with_metadata() {
  local search_dir="$1"
  local output_file="$2"
  local maxdepth_arg="${3:-}"

  : > "$output_file"

  while IFS= read -r -d '' file; do
    metadata="$(get_video_metadata "$file" || true)"

    if [[ -z "$metadata" ]]; then
      echo "Skipping unreadable file: $file"
      continue
    fi

    duration="$(echo "$metadata" | cut -d'|' -f1)"
    width="$(echo "$metadata" | cut -d'|' -f2)"
    height="$(echo "$metadata" | cut -d'|' -f3)"

    if [[ -z "$duration" || -z "$width" || -z "$height" ]]; then
      echo "Skipping missing metadata: $file"
      continue
    fi

    printf '%s\t%s\t%s\t%s\n' "$duration" "$width" "$height" "$file" >> "$output_file"
  done < <(find_video_files "$search_dir" "$maxdepth_arg")
}

move_subfolder_videos_to_root() {
  echo
  echo "=============================="
  echo "SUBFOLDER FLATTENING"
  echo "=============================="

  while IFS= read -r -d '' subdir; do
    while IFS= read -r -d '' file; do
      local filename target_path extension base suffix

      filename="$(basename "$file")"
      target_path="${ROOT_DIR}/${filename}"

      if [[ -e "$target_path" ]]; then
        extension="${filename##*.}"
        base="${filename%.*}"
        suffix=1
        while [[ -e "${ROOT_DIR}/${base}_from_subfolder_${suffix}.${extension}" ]]; do
          ((suffix++))
        done
        target_path="${ROOT_DIR}/${base}_from_subfolder_${suffix}.${extension}"
      fi

      echo "Move to root:"
      echo "  Old: $file"
      echo "  New: $target_path"
      safe_mv "$file" "$target_path"
      echo
    done < <(find_video_files "$subdir" 1)
  done < <(find "$ROOT_DIR" -mindepth 1 -maxdepth 1 -type d -print0)

  echo
  echo "=============================="
  echo "EMPTY FOLDER CLEANUP"
  echo "=============================="

  while IFS= read -r -d '' empty_dir; do
    echo "Delete empty folder:"
    echo "  $empty_dir"
    safe_rmdir "$empty_dir"
    echo
  done < <(find "$ROOT_DIR" -mindepth 1 -maxdepth 1 -type d -empty -print0)
}

rename_and_optionally_move_in_dir() {
  local target_dir="$1"
  local effective_name_mode="$2"
  local effective_base_name="${3:-}"
  local effective_do_move="$4"

  local tmp_file sorted_file renamed_map
  tmp_file="$(mktemp)"
  sorted_file="$(mktemp)"
  renamed_map="$(mktemp)"
  trap 'rm -f "$tmp_file" "$sorted_file" "$renamed_map"' RETURN

  collect_videos_with_metadata "$target_dir" "$tmp_file" 1

  if [[ ! -s "$tmp_file" ]]; then
    echo "No video files found to process in: $target_dir"
    return 0
  fi

  sort -t $'\t' -k1,1nr "$tmp_file" > "$sorted_file"

  echo
  echo "Processing directory:"
  echo "  $target_dir"
  echo
  echo "=============================="
  echo "PHASE 1: RENAME FILES IN PLACE"
  echo "=============================="

  local counter=1

  while IFS=$'\t' read -r duration width height filepath; do
    local dirpath filename extension resolution number
    local dynamic_base_name new_filename renamed_path final_renamed_path
    local suffix

    dirpath="$(dirname "$filepath")"
    filename="$(basename "$filepath")"
    extension="${filename##*.}"
    resolution="${width}x${height}"
    number="$(printf "%03d" "$counter")"

    if [[ "$effective_name_mode" == "folder" ]]; then
      dynamic_base_name="$(basename "$dirpath")"
      dynamic_base_name="$(cleanup_name "$dynamic_base_name")"
      if [[ -z "$dynamic_base_name" ]]; then
        dynamic_base_name="unnamed_folder"
      fi
    else
      dynamic_base_name="$effective_base_name"
    fi

    new_filename="${dynamic_base_name}_${number}_[${resolution}].${extension}"
    renamed_path="${dirpath}/${new_filename}"

    if [[ "$filepath" == "$renamed_path" ]]; then
      final_renamed_path="$renamed_path"
      echo "Already named correctly: $filepath"
      echo
    else
      if [[ -e "$renamed_path" ]]; then
        suffix=1
        while [[ -e "${dirpath}/${dynamic_base_name}_${number}_[${resolution}]_${suffix}.${extension}" ]]; do
          ((suffix++))
        done
        renamed_path="${dirpath}/${dynamic_base_name}_${number}_[${resolution}]_${suffix}.${extension}"
      fi

      echo "Rename:"
      echo "  Old: $filepath"
      echo "  New: $renamed_path"
      echo "  Duration: $duration seconds"
      safe_mv "$filepath" "$renamed_path"
      echo
      final_renamed_path="$renamed_path"
    fi

    printf '%s\t%s\t%s\t%s\n' "$final_renamed_path" "$width" "$height" "$duration" >> "$renamed_map"
    ((counter++))
  done < "$sorted_file"

  if [[ "$effective_do_move" -eq 0 ]]; then
    echo "Done. Files were renamed only in: $target_dir"
    return 0
  fi

  echo
  echo "=============================="
  echo "PHASE 2: MOVE FILES TO FOLDERS"
  echo "=============================="

  while IFS=$'\t' read -r renamed_path width height duration; do
    local current_dir filename resolution_folder target_dir2 target_path
    local extension base_no_ext suffix

    current_dir="$(dirname "$renamed_path")"
    filename="$(basename "$renamed_path")"
    resolution_folder="$(get_resolution_folder "$width" "$height")"
    target_dir2="${current_dir}/${resolution_folder}"
    target_path="${target_dir2}/${filename}"

    if [[ "$current_dir" == "$target_dir2" ]]; then
      echo "Already in correct folder: $renamed_path"
      continue
    fi

    if [[ -e "$target_path" ]]; then
      extension="${filename##*.}"
      base_no_ext="${filename%.*}"
      suffix=1
      while [[ -e "${target_dir2}/${base_no_ext}_${suffix}.${extension}" ]]; do
        ((suffix++))
      done
      target_path="${target_dir2}/${base_no_ext}_${suffix}.${extension}"
    fi

    echo "Move:"
    echo "  Old: $renamed_path"
    echo "  New: $target_path"
    safe_mkdir "$target_dir2"
    safe_mv "$renamed_path" "$target_path"
    echo
  done < "$renamed_map"

  echo "Done. Files were renamed and moved in: $target_dir"
}

# ------------------------------------------------------------
# Detect subfolders
# ------------------------------------------------------------
HAS_SUBFOLDERS=0
if find "$ROOT_DIR" -mindepth 1 -maxdepth 1 -type d | read -r _; then
  HAS_SUBFOLDERS=1
fi

if [[ "$HAS_SUBFOLDERS" -eq 1 ]]; then
  echo "Subfolders were found in:"
  echo "  $ROOT_DIR"
  echo
  echo "Choose how to handle subfolders:"
  echo "  1) flatten    - Move video files from subfolders into the main folder first"
  echo "                  then delete any empty subfolders"
  echo "  2) subfolder  - Run the script separately inside each subfolder"
  echo "  3) skip       - Skip subfolders and only process files already in the main folder"
  echo
  read -r -p "Enter choice [1/2/3, flatten/f, subfolder/sub, skip/s]: " SUBFOLDER_CHOICE

  SUBFOLDER_CHOICE="$(echo "$SUBFOLDER_CHOICE" | tr '[:upper:]' '[:lower:]' | xargs)"

  case "$SUBFOLDER_CHOICE" in
    1|flatten|f|move)
      SUBFOLDER_MODE="flatten"
      ;;
    2|subfolder|sub)
      SUBFOLDER_MODE="subfolder"
      ;;
    3|skip|s|no)
      SUBFOLDER_MODE="skip"
      ;;
    *)
      echo "Error: Invalid choice."
      echo "Valid options: 1, 2, 3, flatten, f, subfolder, sub, skip, s"
      exit 1
      ;;
  esac
else
  SUBFOLDER_MODE="none"
fi

# ------------------------------------------------------------
# Base name mode prompt for normal processing
# ------------------------------------------------------------
echo
echo "Choose base name mode:"
echo "  1) manual  - Enter one base name"
echo "  2) folder  - Use the folder name"
echo
read -r -p "Enter choice [1/2, manual/man, folder/f]: " NAME_MODE_CHOICE

NAME_MODE_CHOICE="$(echo "$NAME_MODE_CHOICE" | tr '[:upper:]' '[:lower:]' | xargs)"

case "$NAME_MODE_CHOICE" in
  1|manual|man)
    NAME_MODE="manual"
    read -r -p "Enter the base name (example: summer_2025): " BASE_NAME
    BASE_NAME="$(cleanup_name "$BASE_NAME")"
    if [[ -z "$BASE_NAME" ]]; then
      echo "Error: Base name cannot be empty."
      exit 1
    fi
    ;;
  2|folder|f)
    NAME_MODE="folder"
    BASE_NAME=""
    echo "Using folder names as base names."
    ;;
  *)
    echo "Error: Invalid choice."
    echo "Valid options: 1, 2, manual, man, folder, f"
    exit 1
    ;;
esac

# ------------------------------------------------------------
# Action prompt
# ------------------------------------------------------------
echo
echo "Choose an action:"
echo "  1) rename       - Rename files only"
echo "  2) both         - Rename files and move them into resolution folders"
echo
read -r -p "Enter choice [1/2, rename/r, both/move/m]: " ACTION_CHOICE

ACTION_CHOICE="$(echo "$ACTION_CHOICE" | tr '[:upper:]' '[:lower:]' | xargs)"

case "$ACTION_CHOICE" in
  1|rename|r)
    DO_MOVE=0
    ;;
  2|both|move|m|rename+move)
    DO_MOVE=1
    ;;
  *)
    echo "Error: Invalid choice."
    echo "Valid options: 1, 2, rename, r, both, move, m, rename+move"
    exit 1
    ;;
esac

# ------------------------------------------------------------
# Extra prompt only for subfolder mode
# ------------------------------------------------------------
SUBFOLDER_RUN_NAME_MODE="$NAME_MODE"
SUBFOLDER_RUN_BASE_NAME="$BASE_NAME"

if [[ "$SUBFOLDER_MODE" == "subfolder" ]]; then
  echo
  echo "For subfolder processing, choose naming mode:"
  echo "  1) manual  - Enter a base name to use inside each subfolder"
  echo "  2) folder  - Use each subfolder's name"
  echo
  read -r -p "Enter choice [1/2, manual/man, folder/f]: " SUB_NAME_MODE_CHOICE

  SUB_NAME_MODE_CHOICE="$(echo "$SUB_NAME_MODE_CHOICE" | tr '[:upper:]' '[:lower:]' | xargs)"

  case "$SUB_NAME_MODE_CHOICE" in
    1|manual|man)
      SUBFOLDER_RUN_NAME_MODE="manual"
      read -r -p "Enter the base name for subfolder processing: " SUBFOLDER_RUN_BASE_NAME
      SUBFOLDER_RUN_BASE_NAME="$(cleanup_name "$SUBFOLDER_RUN_BASE_NAME")"
      if [[ -z "$SUBFOLDER_RUN_BASE_NAME" ]]; then
        echo "Error: Base name cannot be empty."
        exit 1
      fi
      ;;
    2|folder|f)
      SUBFOLDER_RUN_NAME_MODE="folder"
      SUBFOLDER_RUN_BASE_NAME=""
      echo "Using each subfolder name as the base name."
      ;;
    *)
      echo "Error: Invalid choice."
      echo "Valid options: 1, 2, manual, man, folder, f"
      exit 1
      ;;
  esac
fi

# ------------------------------------------------------------
# Execute selected workflow
# ------------------------------------------------------------
case "$SUBFOLDER_MODE" in
  flatten)
    move_subfolder_videos_to_root
    rename_and_optionally_move_in_dir "$ROOT_DIR" "$NAME_MODE" "$BASE_NAME" "$DO_MOVE"
    ;;
  subfolder)
    while IFS= read -r -d '' subdir; do
      rename_and_optionally_move_in_dir \
        "$subdir" \
        "$SUBFOLDER_RUN_NAME_MODE" \
        "$SUBFOLDER_RUN_BASE_NAME" \
        "$DO_MOVE"
    done < <(find "$ROOT_DIR" -mindepth 1 -maxdepth 1 -type d -print0)
    ;;
  skip)
    rename_and_optionally_move_in_dir "$ROOT_DIR" "$NAME_MODE" "$BASE_NAME" "$DO_MOVE"
    ;;
  none)
    rename_and_optionally_move_in_dir "$ROOT_DIR" "$NAME_MODE" "$BASE_NAME" "$DO_MOVE"
    ;;
esac

if [[ "$DRY_RUN" == "1" ]]; then
  echo
  echo "Dry run only. No files were changed."
fi
