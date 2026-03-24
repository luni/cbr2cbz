#!/bin/bash

# cbr2cbz - Convert CBR files to CBZ format
# Supports both single file and directory processing
# Handles filenames with spaces and special characters

IFS=$'\n\t'

print_usage() {
    echo "Usage: $(basename "$0") [OPTIONS] <file.cbr or directory>"
    echo "Options:"
    echo "  -r, --recursive  Process directories recursively"
    echo "  -c, --cleanup    Remove original CBR files after successful conversion"
    echo "  -j, --jobs N     Number of parallel jobs (default: number of processors)"
    echo "  -i, --comicinfo  Inject XML metadata file as ComicInfo.xml (single file mode only)"
    echo "      --comicinfo-overwrite  Overwrite existing ComicInfo.xml without prompting"
    echo "  -h, --help       Show this help message"
    echo ""
    echo "Examples:"
    echo "  Convert a single file:     $(basename "$0") comic.cbr"
    echo "  Convert a directory:       $(basename "$0") /path/to/comics"
    echo "  Convert recursively:       $(basename "$0") -r /path/to/comics"
    echo "  Clean up after conversion: $(basename "$0") -c /path/to/comics"
    echo "  Combine options:           $(basename "$0") -r -c /path/to/comics"
}

# Check if required commands are available
for cmd in unrar zip file realpath; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: '$cmd' is required but not installed." >&2
        exit 1
    fi
done

# Get number of available processors
NUM_CPUS=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)

# Parse command line arguments
RECURSIVE=false
CLEANUP=false
JOBS=$NUM_CPUS
COMICINFO_FILE=""
COMICINFO_OVERWRITE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            print_usage
            exit 0
            ;;
        -r|--recursive)
            RECURSIVE=true
            shift
            ;;
        -c|--cleanup)
            CLEANUP=true
            shift
            ;;
        -j|--jobs)
            if [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
                JOBS="$2"
                shift 2
            else
                echo "Error: --jobs requires an integer argument >= 1" >&2
                exit 1
            fi
            ;;
        -i|--comicinfo)
            if [[ -n "$2" && ! "$2" =~ ^- ]]; then
                COMICINFO_FILE="$2"
                shift 2
            else
                echo "Error: --comicinfo requires a file path argument" >&2
                exit 1
            fi
            ;;
        --comicinfo-overwrite)
            COMICINFO_OVERWRITE=true
            shift
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "Error: Unknown option: $1" >&2
            print_usage >&2
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

if [[ $# -ne 1 ]]; then
    echo "Error: Invalid number of arguments" >&2
    print_usage >&2
    exit 1
fi

INPUT="$1"

if [[ -n "$COMICINFO_FILE" && ! -f "$COMICINFO_FILE" ]]; then
    echo "Error: ComicInfo file not found: $COMICINFO_FILE" >&2
    exit 1
fi

# Global array to track temporary directories
declare -a TEMP_DIRS

# Cleanup function for all temp directories
cleanup() {
    for dir in "${TEMP_DIRS[@]}"; do
        if [[ -n "$dir" && -d "$dir" ]]; then
            rm -rf "$dir"
        fi
    done
}

# Set up cleanup on exit
trap cleanup EXIT

cleanup_after_convert() {
    local cbr_file="$1"
    local cbz_file="$2"

    # Preserve file timestamps
    if ! touch -r "$cbr_file" "$cbz_file"; then
        echo "Error: Failed to preserve timestamp for $cbz_file" >&2
        return 1
    fi

    # Remove original file if cleanup is enabled
    if [[ "$CLEANUP" == true ]]; then
        echo -n "Removing original file... "
        if rm -f "$cbr_file"; then
            echo "OK"
        else
            echo "FAILED" >&2
            echo "Error: Failed to remove $cbr_file" >&2
            return 1
        fi
    fi

    return 0
}

# Function to process a single CBR file
process_cbr_file() {
    local cbr_file="$1"

    if [[ ! -f "$cbr_file" ]]; then
        echo "Error: File not found: $cbr_file" >&2
        return 1
    fi

    if [[ ! "$cbr_file" =~ \.cbr$ ]]; then
        echo "Skipping non-CBR file: $cbr_file" >&2
        return 0
    fi

    local cbz_file="${cbr_file%.*}.cbz"
    if [[ -f "$cbz_file" ]]; then
        echo "Skipping (CBZ already exists): $cbr_file" >&2
        return 0
    fi

    echo "Processing: $cbr_file"

    if [[ -z "$COMICINFO_FILE" ]] && file -- "$cbr_file" | grep -q "Zip archive data"; then
        echo "Skipping (already CBZ): $cbr_file - copying to $cbz_file"
        if ! cp "$cbr_file" "$cbz_file"; then
            echo "Error: Failed to copy $cbr_file to $cbz_file" >&2
            return 1
        fi

        if ! cleanup_after_convert "$cbr_file" "$cbz_file"; then
            return 1
        fi

        return 0
    fi

    local temp_dir=$(mktemp -d -t cbr2cbz_XXXXXXXXXX)
    TEMP_DIRS+=("$temp_dir")

    local cbr_abs_path
    cbr_abs_path=$(realpath -- "$cbr_file")

    if ! (cd "$temp_dir" && unrar x -o+ -ep -inul "$cbr_abs_path"); then
        echo "FAILED (unrar error)"
        return 1
    fi

    if [[ -n "$COMICINFO_FILE" ]]; then
        local inject_comicinfo=true
        if [[ -f "$temp_dir/ComicInfo.xml" && "$COMICINFO_OVERWRITE" != true ]]; then
            if [[ -t 0 ]]; then
                local reply
                printf "ComicInfo.xml already exists in archive for '%s'. Overwrite? [y/N]: " "$cbr_file" >&2
                read -r reply
                if [[ ! "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]; then
                    echo "Skipping: kept existing ComicInfo.xml in archive for $cbr_file"
                    inject_comicinfo=false
                fi
            else
                echo "Error: ComicInfo.xml already exists in archive for $cbr_file." >&2
                echo "Run with --comicinfo-overwrite to overwrite without prompting." >&2
                return 1
            fi
        fi

        if [[ "$inject_comicinfo" == true ]]; then
            if ! cp -- "$COMICINFO_FILE" "$temp_dir/ComicInfo.xml"; then
                echo "Error: Failed to inject ComicInfo.xml into archive for $cbr_file" >&2
                return 1
            fi
        fi
    fi

    # Create CBZ
    if ! (cd "$temp_dir" && zip -r -q "temp.zip" .); then
        echo "Error creating CBZ for $cbr_file" >&2
        return 1
    fi

    # Move the CBZ file from temp dir to the target location
    if ! mv "$temp_dir/temp.zip" "$cbz_file"; then
        echo "Error moving CBZ file to target location" >&2
        return 1
    fi

    cleanup_after_convert "$cbr_file" "$cbz_file"

    echo "Created: $cbz_file"
    rm -rf "$temp_dir"
}

# Function to process files in parallel
process_parallel() {
    local file_list=("$@")
    local total=${#file_list[@]}
    local success=0
    local running=0
    local i=0
    local status_file

    status_file=$(mktemp -t cbr2cbz_XXXXXXXXXX)

    echo "Processing $total files with up to $JOBS parallel jobs..."

    while [[ $i -lt $total || $running -gt 0 ]]; do
        # Start new jobs if we have capacity and files left to process
        while [[ $running -lt $JOBS && $i -lt $total ]]; do
            local file="${file_list[$i]}"
            ((i++))
            ((running++))
            (
                if process_cbr_file "$file"; then
                    echo "1" >> "$status_file"
                else
                    echo "0" >> "$status_file"
                fi
            ) &
        done

        # Wait for next job to finish
        if [[ $running -gt 0 ]]; then
            wait -n
            ((running--))
        fi
    done

    # Count successful conversions
    success=$(grep -c "^1$" "$status_file" 2>/dev/null || echo 0)
    rm -f "$status_file"

    echo "Processed $success of $total files successfully"

    if [[ $success -ne $total ]]; then
        return 1
    fi
    return 0
}

# Function to process a directory
process_directory() {
    local dir="$1"
    local find_cmd=("find" "$dir" "-maxdepth" "1" "-name" "*.cbr" "-type" "f")

    if [[ "$RECURSIVE" == true ]]; then
        find_cmd=("find" "$dir" "-name" "*.cbr" "-type" "f")
    fi

    # Read files into an array
    local files=()
    while IFS= read -r -d $'\0' file; do
        files+=("$file")
    done < <("${find_cmd[@]}" -print0 2>/dev/null | sort -z)

    if [[ ${#files[@]} -eq 0 ]]; then
        echo "No CBR files found in $dir"
        return 0
    fi

    # Process files in parallel
    process_parallel "${files[@]}"
}

# Main execution
if [[ -f "$INPUT" ]]; then
    # Process single file
    process_cbr_file "$INPUT"
elif [[ -d "$INPUT" ]]; then
    if [[ -n "$COMICINFO_FILE" ]]; then
        echo "Error: --comicinfo is only supported when processing a single CBR file" >&2
        exit 1
    fi
    # Process directory
    process_directory "$INPUT"
else
    echo "Error: '$INPUT' is not a valid file or directory" >&2
    exit 1
fi
