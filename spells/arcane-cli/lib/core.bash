#!/usr/bin/env bash

set -euo pipefail

readonly ARCANE_DIR="${ARCANE_DIR:-$HOME/arcane}"
readonly ARCANE_IGNORED_DIRS="archived .data"

_arcane_bold_cyan()  { printf '\033[1;36m%s\033[0m' "$*"; }
_arcane_red()        { printf '\033[0;31m%s\033[0m' "$*"; }
_arcane_green()      { printf '\033[0;32m%s\033[0m' "$*"; }

_arcane_search_regex() {
    local pattern="$1"
    shift

    if command -v rg >/dev/null 2>&1; then
        rg -oN --no-filename "$pattern" "$@" 2>/dev/null || true
    else
        grep -RhoE "$pattern" "$@" 2>/dev/null || true
    fi
}

_arcane_parse_args() {
    ARCANE_DEVICE="$(hostname)"
    ARCANE_INCLUDES=()
    ARCANE_EXCLUDES=()

    local mode="include"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --device|-d)
                [[ $# -lt 2 ]] && { echo "error: --device requires a value" >&2; return 1; }
                ARCANE_DEVICE="$2"
                shift 2
                ;;
            --exclude|-e)
                mode="exclude"
                shift
                ;;
            -*)
                echo "error: unknown option: $1" >&2
                return 1
                ;;
            *)
                if [[ "$mode" == "include" ]]; then
                    ARCANE_INCLUDES+=("$1")
                else
                    ARCANE_EXCLUDES+=("$1")
                fi
                shift
                ;;
        esac
    done

    if [[ ${#ARCANE_INCLUDES[@]} -gt 0 && ${#ARCANE_EXCLUDES[@]} -gt 0 ]]; then
        echo "error: cannot specify both projects and --exclude" >&2
        return 1
    fi
}

_arcane_discover() {
    local device="$1"
    local device_dir="$ARCANE_DIR/$device"

    if [[ ! -d "$device_dir" ]]; then
        echo "error: device directory not found: $device_dir" >&2
        return 1
    fi

    if [[ -f "$device_dir/compose.yaml" ]]; then
        printf '%s\t%s\n' "$device" "$device_dir"
    fi

    local entry
    for entry in "$device_dir"/*/; do
        [[ -d "$entry" ]] || continue
        local name
        name="$(basename "$entry")"

        [[ "$name" == .* ]] && continue

        local ignored=false
        local ign
        for ign in $ARCANE_IGNORED_DIRS; do
            [[ "$name" == "$ign" ]] && { ignored=true; break; }
        done
        $ignored && continue

        [[ -f "$entry/compose.yaml" ]] && printf '%s\t%s\n' "$name" "${entry%/}"
    done
}

_arcane_discover_devices() {
    local entry
    for entry in "$ARCANE_DIR"/*/; do
        [[ -d "$entry" ]] || continue
        local name
        name="$(basename "$entry")"
        [[ "$name" == .* ]] && continue
        printf '%s\t%s\n' "$name" "${entry%/}"
    done
}

_arcane_filter_projects() {
    local projects="$1"
    local filtered=()

    while IFS=$'\t' read -r name path; do
        [[ -n "$name" && -n "$path" ]] || continue

        if [[ ${#ARCANE_INCLUDES[@]} -gt 0 ]]; then
            local include_match=false
            local inc
            for inc in "${ARCANE_INCLUDES[@]}"; do
                [[ "$name" == "$inc" ]] && { include_match=true; break; }
            done
            $include_match || continue
        elif [[ ${#ARCANE_EXCLUDES[@]} -gt 0 ]]; then
            local excluded=false
            local exc
            for exc in "${ARCANE_EXCLUDES[@]}"; do
                [[ "$name" == "$exc" ]] && { excluded=true; break; }
            done
            $excluded && continue
        fi

        filtered+=("$name"$'\t'"$path")
    done <<< "$projects"

    printf '%s\n' "${filtered[@]}"
}

_arcane_selected_projects() {
    local projects
    projects="$(_arcane_discover "$ARCANE_DEVICE")" || return 1

    if [[ -z "$projects" ]]; then
        echo "no projects found for device: $ARCANE_DEVICE" >&2
        return 1
    fi

    local filtered
    filtered="$(_arcane_filter_projects "$projects")"

    if [[ -z "$filtered" ]]; then
        echo "no projects matched the filter" >&2
        return 1
    fi

    printf '%s\n' "$filtered"
}

_arcane_resolve_project() {
    local project="$1"
    local projects
    projects="$(_arcane_discover "$ARCANE_DEVICE")" || return 1

    while IFS=$'\t' read -r name path; do
        [[ "$name" == "$project" ]] || continue
        printf '%s\n' "$path"
        return 0
    done <<< "$projects"

    echo "error: project not found on device '$ARCANE_DEVICE': $project" >&2
    return 1
}

_arcane_project_services() {
    local path="$1"
    awk '
        /^services:[[:space:]]*$/ { in_services=1; next }
        in_services && /^[^[:space:]]/ { in_services=0 }
        in_services && /^[[:space:]][[:space:]][A-Za-z0-9_.-]+:[[:space:]]*$/ {
            line=$0
            sub(/^[[:space:]]+/, "", line)
            sub(/:[[:space:]]*$/, "", line)
            print line
        }
    ' "$path/compose.yaml" 2>/dev/null | awk 'NF'
}

_arcane_find_service_projects() {
    local service="$1"
    local projects
    projects="$(_arcane_discover "$ARCANE_DEVICE")" || return 1

    while IFS=$'\t' read -r name path; do
        [[ -n "$name" && -n "$path" ]] || continue
        while IFS= read -r candidate; do
            [[ -n "$candidate" ]] || continue
            [[ "$candidate" == "$service" ]] || continue
            printf '%s\t%s\n' "$name" "$path"
            break
        done < <(_arcane_project_services "$path")
    done <<< "$projects"
}

_arcane_project_status() {
    local path="$1"
    if ! command -v docker >/dev/null 2>&1; then
        echo "unknown"
        return 0
    fi

    local ids
    ids="$(cd "$path" && docker compose ps -q 2>/dev/null || true)"
    if [[ -n "${ids//[[:space:]]/}" ]]; then
        echo "up"
    else
        echo "down"
    fi
}

_arcane_project_name_from_path() {
    basename "$1"
}

_arcane_project_containers() {
    local path="$1"
    if ! command -v docker >/dev/null 2>&1; then
        return 0
    fi
    (cd "$path" && docker compose ps -aq --all 2>/dev/null || true) | awk 'NF'
}

_arcane_project_images() {
    local path="$1"
    if ! command -v docker >/dev/null 2>&1; then
        return 0
    fi
    (cd "$path" && docker compose config --images 2>/dev/null || true) | awk 'NF' | sort -u
}

_arcane_project_networks() {
    local path="$1"
    if ! command -v docker >/dev/null 2>&1; then
        return 0
    fi

    local project_name
    project_name="$(_arcane_project_name_from_path "$path")"
    docker network ls --filter "label=com.docker.compose.project=${project_name}" --format '{{.Name}}' 2>/dev/null | awk 'NF'
}

_arcane_project_volumes() {
    local path="$1"
    if ! command -v docker >/dev/null 2>&1; then
        return 0
    fi

    local project_name
    project_name="$(_arcane_project_name_from_path "$path")"
    docker volume ls --filter "label=com.docker.compose.project=${project_name}" --format '{{.Name}}' 2>/dev/null | awk 'NF'
}

_arcane_join_lines() {
    local lines=("$@")
    if [[ ${#lines[@]} -eq 0 ]]; then
        printf '-\n'
    else
        printf '%s\n' "${lines[*]}"
    fi
}

_arcane_remove_named_resources() {
    local kind="$1"
    shift
    local items=("$@")

    [[ ${#items[@]} -gt 0 ]] || return 0

    case "$kind" in
        containers)
            docker rm -f "${items[@]}"
            ;;
        images)
            docker image rm -f "${items[@]}"
            ;;
        networks)
            docker network rm "${items[@]}"
            ;;
        volumes)
            docker volume rm "${items[@]}"
            ;;
        *)
            echo "error: unknown resource type: $kind" >&2
            return 1
            ;;
    esac
}

_arcane_each() {
    local action="$1"
    shift

    _arcane_parse_args "$@" || return 1

    local filtered
    filtered="$(_arcane_selected_projects)" || return 1

    local ok=0
    local fail=0
    while IFS=$'\t' read -r name path; do
        [[ -n "$name" && -n "$path" ]] || continue

        printf '%s %s\n' "$(_arcane_bold_cyan "$name")" "$action"
        if (cd "$path" && eval "$action"); then
            ((ok += 1))
        else
            printf '%s %s\n' "$(_arcane_red "$name")" "FAILED"
            ((fail += 1))
        fi
    done <<< "$filtered"

    if [[ $((ok + fail)) -gt 1 ]]; then
        echo
        printf 'Done: %s ok, %s failed\n' "$(_arcane_green "$ok")" "$(_arcane_red "$fail")"
    fi

    [[ $fail -eq 0 ]]
}

_arcane_ls() {
    local mode="${1:-all}"
    shift || true

    _arcane_parse_args "$@" || return 1

    local filtered
    filtered="$(_arcane_selected_projects)" || return 1

    while IFS=$'\t' read -r name path; do
        [[ -n "$name" && -n "$path" ]] || continue
        local status
        status="$(_arcane_project_status "$path")"
        case "$mode" in
            up) [[ "$status" == "up" ]] || continue ;;
            down) [[ "$status" == "down" ]] || continue ;;
        esac
        printf '%-8s %s\n' "$status" "$name"
    done <<< "$filtered"
}

_arcane_path() {
    _arcane_parse_args "$@" || return 1

    if [[ ${#ARCANE_EXCLUDES[@]} -gt 0 ]]; then
        echo "error: arcane path does not support --exclude" >&2
        return 1
    fi
    if [[ ${#ARCANE_INCLUDES[@]} -ne 1 ]]; then
        echo "error: arcane path requires exactly one project name" >&2
        return 1
    fi

    _arcane_resolve_project "${ARCANE_INCLUDES[0]}"
}

_arcane_exec() {
    local device="$(hostname)"
    local project=""
    local positional=()
    local cmd=()
    local seen_separator=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --device|-d)
                [[ $# -lt 2 ]] && { echo "error: --device requires a value" >&2; return 1; }
                device="$2"
                shift 2
                ;;
            --project|-p)
                [[ $# -lt 2 ]] && { echo "error: --project requires a value" >&2; return 1; }
                project="$2"
                shift 2
                ;;
            --)
                shift
                cmd=("$@")
                seen_separator=true
                break
                ;;
            -*)
                echo "error: unknown option: $1" >&2
                return 1
                ;;
            *)
                positional+=("$1")
                shift
                ;;
        esac
    done

    $seen_separator || { echo "error: exec requires '--' before the command" >&2; return 1; }
    [[ ${#positional[@]} -eq 1 ]] || { echo "error: exec requires exactly one service name before '--'" >&2; return 1; }
    [[ ${#cmd[@]} -gt 0 ]] || { echo "error: exec requires a command after '--'" >&2; return 1; }

    ARCANE_DEVICE="$device"

    local service="${positional[0]}"
    local target_project="$project"
    local target_path=""

    if [[ -n "$project" ]]; then
        target_path="$(_arcane_resolve_project "$project")" || return 1

        if ! _arcane_project_services "$target_path" | grep -Fxq "$service"; then
            echo "error: service '$service' not found in project '$project' on device '$ARCANE_DEVICE'" >&2
            return 1
        fi
    else
        local matches=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && matches+=("$line")
        done < <(_arcane_find_service_projects "$service")

        if [[ ${#matches[@]} -eq 0 ]]; then
            echo "error: service '$service' not found on device '$ARCANE_DEVICE'" >&2
            return 1
        fi

        if [[ ${#matches[@]} -gt 1 ]]; then
            echo "error: service '$service' matches multiple projects on device '$ARCANE_DEVICE'; use --project/-p" >&2
            return 1
        fi

        IFS=$'\t' read -r target_project target_path <<<"${matches[0]}"
    fi

    (cd "$target_path" && docker compose exec "$service" "${cmd[@]}")
}

_arcane_bash() {
    local device="$(hostname)"
    local project=""
    local positional=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --device|-d)
                [[ $# -lt 2 ]] && { echo "error: --device requires a value" >&2; return 1; }
                device="$2"
                shift 2
                ;;
            --project|-p)
                [[ $# -lt 2 ]] && { echo "error: --project requires a value" >&2; return 1; }
                project="$2"
                shift 2
                ;;
            -*)
                echo "error: unknown option: $1" >&2
                return 1
                ;;
            *)
                positional+=("$1")
                shift
                ;;
        esac
    done

    [[ ${#positional[@]} -eq 1 ]] || { echo "error: bash requires exactly one service name" >&2; return 1; }

    ARCANE_DEVICE="$device"

    local service="${positional[0]}"
    local target_project="$project"
    local target_path=""

    if [[ -n "$project" ]]; then
        target_path="$(_arcane_resolve_project "$project")" || return 1

        if ! _arcane_project_services "$target_path" | grep -Fxq "$service"; then
            echo "error: service '$service' not found in project '$project' on device '$ARCANE_DEVICE'" >&2
            return 1
        fi
    else
        local matches=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && matches+=("$line")
        done < <(_arcane_find_service_projects "$service")

        if [[ ${#matches[@]} -eq 0 ]]; then
            echo "error: service '$service' not found on device '$ARCANE_DEVICE'" >&2
            return 1
        fi

        if [[ ${#matches[@]} -gt 1 ]]; then
            echo "error: service '$service' matches multiple projects on device '$ARCANE_DEVICE'; use --project/-p" >&2
            return 1
        fi

        IFS=$'\t' read -r target_project target_path <<<"${matches[0]}"
    fi

    (cd "$target_path" && docker compose exec "$service" bash)
}

_arcane_resources() {
    _arcane_parse_args "$@" || return 1

    local filtered
    filtered="$(_arcane_selected_projects)" || return 1

    while IFS=$'\t' read -r name path; do
        [[ -n "$name" && -n "$path" ]] || continue

        mapfile -t containers < <(_arcane_project_containers "$path")
        mapfile -t images < <(_arcane_project_images "$path")
        mapfile -t networks < <(_arcane_project_networks "$path")
        mapfile -t volumes < <(_arcane_project_volumes "$path")

        printf '%s (%s)\n' "$name" "$path"
        printf '  containers: %s\n' "$(_arcane_join_lines "${containers[@]}")"
        printf '  images: %s\n' "$(_arcane_join_lines "${images[@]}")"
        printf '  networks: %s\n' "$(_arcane_join_lines "${networks[@]}")"
        printf '  volumes: %s\n' "$(_arcane_join_lines "${volumes[@]}")"
    done <<< "$filtered"
}

_arcane_rm() {
    local resource_type="$1"
    shift

    case "$resource_type" in
        containers|images|networks|volumes|all) ;;
        *)
            echo "error: rm supports containers, images, networks, volumes, or all" >&2
            return 1
            ;;
    esac

    _arcane_parse_args "$@" || return 1

    local filtered
    filtered="$(_arcane_selected_projects)" || return 1

    while IFS=$'\t' read -r name path; do
        [[ -n "$name" && -n "$path" ]] || continue

        printf '%s remove %s\n' "$(_arcane_bold_cyan "$name")" "$resource_type"

        if [[ "$resource_type" == "containers" || "$resource_type" == "all" ]]; then
            mapfile -t containers < <(_arcane_project_containers "$path")
            _arcane_remove_named_resources containers "${containers[@]}"
        fi
        if [[ "$resource_type" == "images" || "$resource_type" == "all" ]]; then
            mapfile -t images < <(_arcane_project_images "$path")
            _arcane_remove_named_resources images "${images[@]}"
        fi
        if [[ "$resource_type" == "networks" || "$resource_type" == "all" ]]; then
            mapfile -t networks < <(_arcane_project_networks "$path")
            _arcane_remove_named_resources networks "${networks[@]}"
        fi
        if [[ "$resource_type" == "volumes" || "$resource_type" == "all" ]]; then
            mapfile -t volumes < <(_arcane_project_volumes "$path")
            _arcane_remove_named_resources volumes "${volumes[@]}"
        fi
    done <<< "$filtered"
}

_arcane_html_escape() {
    local s="$1"
    s="${s//&/&amp;}"
    s="${s//</&lt;}"
    s="${s//>/&gt;}"
    s="${s//\"/&quot;}"
    printf '%s' "$s"
}

_arcane_collect_nginx_urls() {
    local project_path="$1"

    local file
    while IFS= read -r -d '' file; do
        _arcane_search_regex 'https?://[A-Za-z0-9._~:/?#\[\]@!$&()*+,;=%-]+' "$file"
    done < <(find "$project_path" -maxdepth 5 -type f \
        \( -name 'compose.yaml' -o -name 'compose.yml' -o -name '*.conf' -o -name '.env' -o -name '.env.*' -o -name '*.env' \) \
        -print0)

    while IFS= read -r line; do
        line="${line#server_name }"
        line="${line%;}"
        local host
        for host in $line; do
            [[ -z "$host" || "$host" == "_" || "$host" == "localhost" ]] && continue
            [[ "$host" =~ [*] ]] && continue
            printf 'http://%s\n' "$host"
        done
    done < <(_arcane_search_regex 'server_name[[:space:]]+[^;]+;' "$project_path")

    while IFS= read -r host; do
        [[ -z "$host" || "$host" == "localhost" ]] && continue
        printf 'http://%s\n' "$host"
    done < <(_arcane_search_regex 'Host\(`[^`]+`\)' "$project_path" | sed -E 's/Host\(`([^`]+)`\)/\1/')
}

_arcane_write_bookmark_entry() {
    local url="$1"
    local label="$2"
    printf '<DT><A HREF="%s">%s</A>\n' "$(_arcane_html_escape "$url")" "$(_arcane_html_escape "$label")"
}

_arcane_favorites() {
    local device_filter=""
    local output="$ARCANE_DIR/arcane-nginx-bookmarks.html"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --device|-d)
                [[ $# -lt 2 ]] && { echo "error: --device requires a value" >&2; return 1; }
                device_filter="$2"
                shift 2
                ;;
            --output|-o)
                [[ $# -lt 2 ]] && { echo "error: --output requires a value" >&2; return 1; }
                output="$2"
                shift 2
                ;;
            *)
                echo "error: unknown option: $1" >&2
                return 1
                ;;
        esac
    done

    local devices=()
    local discovered
    discovered="$(_arcane_discover_devices)"
    if [[ -z "$discovered" ]]; then
        echo "error: no device directories found in $ARCANE_DIR" >&2
        return 1
    fi

    while IFS=$'\t' read -r name _path; do
        if [[ -n "$device_filter" && "$name" != "$device_filter" ]]; then
            continue
        fi
        devices+=("$name")
    done <<< "$discovered"

    if [[ ${#devices[@]} -eq 0 ]]; then
        echo "error: device not found: $device_filter" >&2
        return 1
    fi

    mkdir -p "$(dirname "$output")"
    {
        echo '<!DOCTYPE NETSCAPE-Bookmark-file-1>'
        echo '<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">'
        echo '<TITLE>Bookmarks</TITLE>'
        echo '<H1>Bookmarks</H1>'
        echo '<DL><p>'
        echo '<DT><H3>arcane</H3>'
        echo '<DL><p>'
    } >"$output"

    local total=0
    local device
    for device in "${devices[@]}"; do
        local projects
        projects="$(_arcane_discover "$device" || true)"
        [[ -z "$projects" ]] && continue

        {
            printf '<DT><H3>%s</H3>\n' "$(_arcane_html_escape "$device")"
            echo '<DL><p>'
        } >>"$output"

        while IFS=$'\t' read -r project path; do
            [[ -n "$project" && -n "$path" ]] || continue
            mapfile -t urls < <(_arcane_collect_nginx_urls "$path" | awk 'NF' | sort -u)
            [[ ${#urls[@]} -gt 0 ]] || continue

            {
                printf '<DT><H3>%s</H3>\n' "$(_arcane_html_escape "$project")"
                echo '<DL><p>'
            } >>"$output"

            local url
            for url in "${urls[@]}"; do
                _arcane_write_bookmark_entry "$url" "$url" >>"$output"
                ((total += 1))
            done

            echo '</DL><p>' >>"$output"
        done <<< "$projects"

        echo '</DL><p>' >>"$output"
    done

    {
        echo '</DL><p>'
        echo '</DL><p>'
    } >>"$output"

    echo "Bookmarks generated: $output ($total URL(s))"
}

_arcane_dump() {
    if ! command -v 7z >/dev/null 2>&1; then
        echo "error: 7z not found. Install p7zip-full." >&2
        return 1
    fi

    local stamp
    stamp="$(date +%Y-%m-%d)"
    local output="$ARCANE_DIR/arcane-env-dump-${stamp}.7z"

    local env_files=()
    while IFS= read -r -d '' f; do
        env_files+=("$f")
    done < <(find "$ARCANE_DIR" -name '.env' \
        -not -path '*/archived/*' \
        -not -path '*/.data/*' \
        -not -path '*/node_modules/*' \
        -print0)

    if [[ ${#env_files[@]} -eq 0 ]]; then
        echo "no .env files found" >&2
        return 1
    fi

    echo "Found ${#env_files[@]} .env file(s):"
    local f
    for f in "${env_files[@]}"; do
        echo "  ${f#"$ARCANE_DIR/"}"
    done

    local rel_paths=()
    for f in "${env_files[@]}"; do
        rel_paths+=("${f#"$ARCANE_DIR/"}")
    done

    (cd "$ARCANE_DIR" && 7z a -p -mhe=on "$output" "${rel_paths[@]}")

    echo
    echo "Archive: $output"

    local gitignore="$ARCANE_DIR/.gitignore"
    local pattern="arcane-env-dump-*.7z"
    if [[ -f "$gitignore" ]]; then
        if ! grep -qF "$pattern" "$gitignore"; then
            echo "$pattern" >>"$gitignore"
            echo "Added $pattern to .gitignore"
        fi
    else
        echo "$pattern" >"$gitignore"
        echo "Created .gitignore with $pattern"
    fi
}

_arcane_restore() {
    local archive="$1"

    if ! command -v 7z >/dev/null 2>&1; then
        echo "error: 7z not found. Install p7zip-full." >&2
        return 1
    fi

    if [[ ! -f "$archive" ]]; then
        echo "error: archive not found: $archive" >&2
        return 1
    fi

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT

    if ! 7z x -o"$tmpdir" "$archive"; then
        echo "error: failed to extract archive" >&2
        return 1
    fi

    local env_files=()
    while IFS= read -r -d '' f; do
        env_files+=("$f")
    done < <(find "$tmpdir" -name '.env' -print0)

    if [[ ${#env_files[@]} -eq 0 ]]; then
        echo "no .env files found in archive" >&2
        return 1
    fi

    echo "Files to restore:"
    local has_overwrites=false
    local f
    for f in "${env_files[@]}"; do
        local rel="${f#"$tmpdir/"}"
        local target="$ARCANE_DIR/$rel"
        if [[ -f "$target" ]]; then
            echo "  $rel (overwrite)"
            has_overwrites=true
        else
            echo "  $rel (new)"
        fi
    done

    if $has_overwrites; then
        echo
        read -r -p "Some files will be overwritten. Continue? [y/N] " confirm
        case "$confirm" in
            [yY]|[yY][eE][sS]) ;;
            *)
                echo "Aborted."
                return 1
                ;;
        esac
    fi

    for f in "${env_files[@]}"; do
        local rel="${f#"$tmpdir/"}"
        local target="$ARCANE_DIR/$rel"
        mkdir -p "$(dirname "$target")"
        cp "$f" "$target"
        echo "Restored: $rel"
    done

    echo "Done."
}
