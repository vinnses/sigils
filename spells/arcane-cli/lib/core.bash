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
    ARCANE_DEVICE="${ARCANE_DEVICE:-$(hostname)}"
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

_arcane_archived_device_dir() {
    local device="$1"
    printf '%s\n' "$ARCANE_DIR/archived/$device"
}

_arcane_parse_device_project() {
    ARCANE_DEVICE="${ARCANE_DEVICE:-$(hostname)}"
    ARCANE_PROJECT=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --device|-d)
                [[ $# -lt 2 ]] && { echo "error: --device requires a value" >&2; return 1; }
                ARCANE_DEVICE="$2"
                shift 2
                ;;
            -*)
                echo "error: unknown option: $1" >&2
                return 1
                ;;
            *)
                if [[ -n "$ARCANE_PROJECT" ]]; then
                    echo "error: expected exactly one project" >&2
                    return 1
                fi
                ARCANE_PROJECT="$1"
                shift
                ;;
        esac
    done

    [[ -n "$ARCANE_PROJECT" ]] || { echo "error: project is required" >&2; return 1; }
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
        printf '%s\n' '-'
    else
        printf '%s\n' "${lines[*]}"
    fi
}

_arcane_remove_named_resources() {
    local kind="$1"
    local force="${2:-false}"
    shift 2
    local items=("$@")

    [[ ${#items[@]} -gt 0 ]] || return 0

    case "$kind" in
        containers)
            if [[ "$force" == "true" ]]; then
                docker rm -f "${items[@]}"
            else
                docker rm "${items[@]}"
            fi
            ;;
        images)
            if [[ "$force" == "true" ]]; then
                docker image rm -f "${items[@]}"
            else
                docker image rm "${items[@]}"
            fi
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

_arcane_resource_type_valid() {
    case "$1" in
        containers|images|networks|volumes|all) return 0 ;;
        *) return 1 ;;
    esac
}

_arcane_resource_type_set() {
    local spec="$1"

    if [[ "$spec" == "all" ]]; then
        printf '%s\n' containers images networks volumes
        return 0
    fi

    local parts=()
    IFS=',' read -r -a parts <<<"$spec"

    local part
    for part in "${parts[@]}"; do
        if [[ -z "$part" || "$part" == "all" ]] || ! _arcane_resource_type_valid "$part"; then
            echo "error: resource type must be containers, images, networks, volumes, all, or a comma-separated list" >&2
            return 1
        fi
        printf '%s\n' "$part"
    done
}

_arcane_project_resource_names() {
    local path="$1"
    local kind="$2"

    case "$kind" in
        containers) _arcane_project_containers "$path" ;;
        images) _arcane_project_images "$path" ;;
        networks) _arcane_project_networks "$path" ;;
        volumes) _arcane_project_volumes "$path" ;;
        *)
            echo "error: unknown resource type: $kind" >&2
            return 1
            ;;
    esac
}

_arcane_print_project_resources() {
    local name="$1"
    local path="$2"
    local kind="${3:-all}"

    local type_output
    type_output="$(_arcane_resource_type_set "$kind")" || return 1
    local types=()
    mapfile -t types <<<"$type_output"

    printf '%s (%s)\n' "$name" "$path"

    local type
    for type in "${types[@]}"; do
        local resources=()
        mapfile -t resources < <(_arcane_project_resource_names "$path" "$type")
        printf '  %s: %s\n' "$type" "$(_arcane_join_lines "${resources[@]}")"
    done
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

    if [[ ${#ARCANE_INCLUDES[@]} -gt 0 ]]; then
        if [[ "$mode" != "all" ]]; then
            echo "error: --up/--down only apply when listing projects" >&2
            return 1
        fi
        if [[ ${#ARCANE_EXCLUDES[@]} -gt 0 ]]; then
            echo "error: cannot use --exclude when listing project resources" >&2
            return 1
        fi
        if [[ ${#ARCANE_INCLUDES[@]} -gt 2 ]]; then
            echo "error: list accepts at most one project and one resource type" >&2
            return 1
        fi

        local project="${ARCANE_INCLUDES[0]}"
        local resource_type="${ARCANE_INCLUDES[1]:-all}"
        if ! _arcane_resource_type_valid "$resource_type"; then
            echo "error: list resource type must be containers, images, networks, volumes, or all" >&2
            return 1
        fi

        local path
        path="$(_arcane_resolve_project "$project")" || return 1
        _arcane_print_project_resources "$project" "$path" "$resource_type"
        return 0
    fi

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

_arcane_ls_archived() {
    _arcane_parse_args "$@" || return 1

    if [[ ${#ARCANE_EXCLUDES[@]} -gt 0 ]]; then
        echo "error: --exclude is not supported with --archived" >&2
        return 1
    fi
    if [[ ${#ARCANE_INCLUDES[@]} -gt 1 ]]; then
        echo "error: list --archived accepts at most one project filter" >&2
        return 1
    fi

    local archived_dir
    archived_dir="$(_arcane_archived_device_dir "$ARCANE_DEVICE")"
    if [[ ! -d "$archived_dir" ]]; then
        echo "no archived projects found for device: $ARCANE_DEVICE" >&2
        return 1
    fi

    local found=false
    local entry
    for entry in "$archived_dir"/*/; do
        [[ -d "$entry" ]] || continue
        local name
        name="$(basename "$entry")"
        [[ "$name" == .* ]] && continue
        if [[ ${#ARCANE_INCLUDES[@]} -eq 1 && "$name" != "${ARCANE_INCLUDES[0]}" ]]; then
            continue
        fi
        found=true
        printf 'archived %s\n' "$name"
    done

    if ! $found; then
        echo "no archived projects matched the filter" >&2
        return 1
    fi
}

_arcane_exec() {
    local device="${ARCANE_DEVICE:-$(hostname)}"
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
            echo "error: service '$service' matches multiple projects on device '$ARCANE_DEVICE'" >&2
            echo "projects:" >&2
            local match
            for match in "${matches[@]}"; do
                IFS=$'\t' read -r target_project _target_path <<<"$match"
                echo "  $target_project" >&2
            done
            echo "use --project/-p to choose one" >&2
            return 1
        fi

        IFS=$'\t' read -r target_project target_path <<<"${matches[0]}"
    fi

    (cd "$target_path" && docker compose exec "$service" "${cmd[@]}")
}

_arcane_archive() {
    _arcane_parse_device_project "$@" || return 1

    local source
    source="$(_arcane_resolve_project "$ARCANE_PROJECT")" || return 1

    local archived_dir target
    archived_dir="$(_arcane_archived_device_dir "$ARCANE_DEVICE")"
    target="$archived_dir/$ARCANE_PROJECT"

    if [[ -e "$target" ]]; then
        echo "error: archived project already exists: $target" >&2
        return 1
    fi

    mkdir -p "$archived_dir"
    mv "$source" "$target"
    echo "Archived: $ARCANE_DEVICE/$ARCANE_PROJECT"
}

_arcane_unarchive() {
    _arcane_parse_device_project "$@" || return 1

    local archived_dir source device_dir target
    archived_dir="$(_arcane_archived_device_dir "$ARCANE_DEVICE")"
    source="$archived_dir/$ARCANE_PROJECT"
    device_dir="$ARCANE_DIR/$ARCANE_DEVICE"
    target="$device_dir/$ARCANE_PROJECT"

    if [[ ! -d "$source" ]]; then
        echo "error: archived project not found: $source" >&2
        return 1
    fi
    if [[ -e "$target" ]]; then
        echo "error: active project already exists: $target" >&2
        return 1
    fi

    mkdir -p "$device_dir"
    mv "$source" "$target"
    echo "Restored: $ARCANE_DEVICE/$ARCANE_PROJECT"
}

_arcane_rewrite_clone_file() {
    local file="$1"
    local from_device="$2"
    local to_device="$3"
    local from_project="$4"
    local to_project="$5"

    grep -Iq . "$file" 2>/dev/null || return 0

    sed -i \
        -e "s|/$from_device/$from_project|/$to_device/$to_project|g" \
        -e "s|\\(ARCANE_DEVICE=\\)$from_device\\b|\\1$to_device|g" \
        -e "s|\\(DEVICE=\\)$from_device\\b|\\1$to_device|g" \
        -e "s|\\(HOST=\\)$from_device\\b|\\1$to_device|g" \
        -e "s|\\(ARCANE_PROJECT=\\)$from_project\\b|\\1$to_project|g" \
        -e "s|\\(PROJECT=\\)$from_project\\b|\\1$to_project|g" \
        -e "s|\\(COMPOSE_PROJECT_NAME=\\)$from_project\\b|\\1$to_project|g" \
        "$file"
}

_arcane_clone() {
    local from_device=""
    local to_device=""
    local new_name=""
    local project=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from)
                [[ $# -lt 2 ]] && { echo "error: --from requires a value" >&2; return 1; }
                from_device="$2"
                shift 2
                ;;
            --to)
                [[ $# -lt 2 ]] && { echo "error: --to requires a value" >&2; return 1; }
                to_device="$2"
                shift 2
                ;;
            --new)
                [[ $# -lt 2 ]] && { echo "error: --new requires a value" >&2; return 1; }
                new_name="$2"
                shift 2
                ;;
            -*)
                echo "error: unknown option: $1" >&2
                return 1
                ;;
            *)
                if [[ -n "$project" ]]; then
                    echo "error: clone expects exactly one project" >&2
                    return 1
                fi
                project="$1"
                shift
                ;;
        esac
    done

    [[ -n "$from_device" ]] || { echo "error: clone requires --from <device>" >&2; return 1; }
    [[ -n "$to_device" ]] || { echo "error: clone requires --to <device>" >&2; return 1; }
    [[ -n "$project" ]] || { echo "error: clone requires a project" >&2; return 1; }

    local target_project="${new_name:-$project}"
    local source="$ARCANE_DIR/$from_device/$project"
    local target_dir="$ARCANE_DIR/$to_device"
    local target="$target_dir/$target_project"

    if [[ ! -d "$source" ]]; then
        echo "error: source project not found: $source" >&2
        return 1
    fi
    if [[ -e "$target" ]]; then
        echo "error: target project already exists: $target" >&2
        return 1
    fi

    mkdir -p "$target_dir"
    cp -a "$source" "$target"

    local file
    while IFS= read -r -d '' file; do
        _arcane_rewrite_clone_file "$file" "$from_device" "$to_device" "$project" "$target_project"
    done < <(find "$target" -type f \
        -not -path '*/.git/*' \
        -not -path '*/node_modules/*' \
        -not -path '*/.data/*' \
        -print0)

    echo "Cloned: $from_device/$project -> $to_device/$target_project"
}

_arcane_remove() {
    local device="${ARCANE_DEVICE:-$(hostname)}"
    local force=false
    local positional=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --device|-d)
                [[ $# -lt 2 ]] && { echo "error: --device requires a value" >&2; return 1; }
                device="$2"
                shift 2
                ;;
            --force|-f)
                force=true
                shift
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

    ARCANE_DEVICE="$device"

    if [[ ${#positional[@]} -lt 2 ]]; then
        echo "error: remove requires <project> <containers|images|networks|volumes|all>[,<type>...] [names...]" >&2
        return 1
    fi

    local project="${positional[0]}"
    local resource_spec="${positional[1]}"
    local names=("${positional[@]:2}")
    local path
    path="$(_arcane_resolve_project "$project")" || return 1

    local type_output
    type_output="$(_arcane_resource_type_set "$resource_spec")" || return 1
    local types=()
    mapfile -t types <<<"$type_output"

    if [[ ${#names[@]} -gt 0 && ${#types[@]} -ne 1 ]]; then
        echo "error: named resources require exactly one resource type" >&2
        return 1
    fi

    local type
    for type in "${types[@]}"; do
        local targets=()
        if [[ ${#names[@]} -gt 0 ]]; then
            targets=("${names[@]}")
        else
            mapfile -t targets < <(_arcane_project_resource_names "$path" "$type")
        fi

        printf '%s remove %s\n' "$(_arcane_bold_cyan "$project")" "$type"
        _arcane_remove_named_resources "$type" "$force" "${targets[@]}"
    done
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

_arcane_nginx_urls() {
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

_arcane_project_env_file_refs() {
    local path="$1"
    local compose

    for compose in "$path/compose.yaml" "$path/compose.yml"; do
        [[ -f "$compose" ]] || continue
        awk '
            /^[[:space:]]*env_file:[[:space:]]*[^[:space:]]/ {
                line=$0
                sub(/^[[:space:]]*env_file:[[:space:]]*/, "", line)
                gsub(/["'\''"]/, "", line)
                print line
                next
            }
            /^[[:space:]]*env_file:[[:space:]]*$/ { in_env=1; next }
            in_env && /^[[:space:]]*-[[:space:]]*/ {
                line=$0
                sub(/^[[:space:]]*-[[:space:]]*/, "", line)
                gsub(/["'\''"]/, "", line)
                print line
                next
            }
            in_env && /^[[:space:]]*[A-Za-z0-9_.-]+:[[:space:]]*/ { in_env=0 }
        ' "$compose" | awk 'NF'
    done
}

_arcane_collect_env_files_for_project() {
    local path="$1"
    local files=()
    local f

    while IFS= read -r -d '' f; do
        files+=("$f")
    done < <(find "$path" -maxdepth 2 -type f \
        \( -name '.env' -o -name '.env.*' -o -name '*.env' \) \
        -print0)

    local ref
    while IFS= read -r ref; do
        [[ -n "$ref" ]] || continue
        [[ "$ref" = /* ]] && f="$ref" || f="$path/$ref"
        [[ -f "$f" ]] && files+=("$f")
    done < <(_arcane_project_env_file_refs "$path")

    printf '%s\n' "${files[@]}" | awk 'NF' | sort -u
}

_arcane_dump_add_file() {
    local tmpdir="$1"
    local manifest="$2"
    local file="$3"
    local rel="${file#"$ARCANE_DIR/"}"
    local staged="$tmpdir/files/$rel"

    mkdir -p "$(dirname "$staged")"
    cp "$file" "$staged"
    printf 'file\t%s\t%s\n' "$rel" "files/$rel" >>"$manifest"
}

_arcane_dump_add_volume() {
    local tmpdir="$1"
    local manifest="$2"
    local device="$3"
    local project="$4"
    local volume="$5"
    local rel="volumes/$device/$project/$volume.tar"
    local outdir="$tmpdir/volumes/$device/$project"

    mkdir -p "$outdir"
    if ! docker run --rm -v "$volume:/volume:ro" -v "$outdir:/backup" alpine tar -C /volume -cf "/backup/$volume.tar" .; then
        echo "error: failed to export volume: $volume" >&2
        return 1
    fi
    printf 'volume\t%s\t%s\t%s\t%s\n' "$device" "$project" "$volume" "$rel" >>"$manifest"
}

_arcane_dump_write_gitignore() {
    local pattern="$1"
    local gitignore="$ARCANE_DIR/.gitignore"

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

_arcane_dump() {
    if ! command -v 7z >/dev/null 2>&1; then
        echo "error: 7z not found. Install p7zip-full." >&2
        return 1
    fi

    local device="${ARCANE_DEVICE:-$(hostname)}"
    local output=""
    local only_env=false
    local include_volumes=false
    local positional=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --device|-d)
                [[ $# -lt 2 ]] && { echo "error: --device requires a value" >&2; return 1; }
                device="$2"
                shift 2
                ;;
            --output|-o)
                [[ $# -lt 2 ]] && { echo "error: --output requires a value" >&2; return 1; }
                output="$2"
                shift 2
                ;;
            --only-env|env)
                only_env=true
                shift
                ;;
            --volumes)
                include_volumes=true
                shift
                ;;
            all)
                only_env=false
                shift
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

    ARCANE_DEVICE="$device"

    local stamp
    stamp="$(date +%Y-%m-%d)"
    if $include_volumes; then
        output="${output:-$ARCANE_DIR/arcane-dump-${stamp}.7z}"
    else
        output="${output:-$ARCANE_DIR/arcane-env-dump-${stamp}.7z}"
    fi

    if ! $only_env; then
        only_env=true
    fi

    local selected=()
    if [[ ${#positional[@]} -gt 0 ]]; then
        local project path
        for project in "${positional[@]}"; do
            path="$(_arcane_resolve_project "$project")" || return 1
            selected+=("$project"$'\t'"$path")
        done
    else
        local projects
        projects="$(_arcane_selected_projects)" || return 1
        local _name path
        while IFS=$'\t' read -r _name path; do
            [[ -n "$_name" && -n "$path" ]] && selected+=("$_name"$'\t'"$path")
        done <<< "$projects"
    fi

    local env_files=()
    local selected_entry selected_name selected_path
    for selected_entry in "${selected[@]}"; do
        IFS=$'\t' read -r selected_name selected_path <<<"$selected_entry"
        while IFS= read -r f; do
            [[ -n "$f" ]] && env_files+=("$f")
        done < <(_arcane_collect_env_files_for_project "$selected_path")
    done

    if [[ ${#env_files[@]} -eq 0 ]]; then
        echo "no environment files found" >&2
        return 1
    fi

    mapfile -t env_files < <(printf '%s\n' "${env_files[@]}" | sort -u)

    echo "Found ${#env_files[@]} environment file(s):"
    local f
    for f in "${env_files[@]}"; do
        echo "  ${f#"$ARCANE_DIR/"}"
    done

    local rel_paths=()
    for f in "${env_files[@]}"; do
        rel_paths+=("${f#"$ARCANE_DIR/"}")
    done

    if $include_volumes; then
        local tmpdir
        tmpdir="$(mktemp -d)"
        local manifest="$tmpdir/manifest.tsv"
        : >"$manifest"

        for f in "${env_files[@]}"; do
            _arcane_dump_add_file "$tmpdir" "$manifest" "$f"
        done

        for selected_entry in "${selected[@]}"; do
            IFS=$'\t' read -r selected_name selected_path <<<"$selected_entry"
            local volumes=()
            mapfile -t volumes < <(_arcane_project_volumes "$selected_path")
            local volume
            for volume in "${volumes[@]}"; do
                [[ -n "$volume" ]] || continue
                _arcane_dump_add_volume "$tmpdir" "$manifest" "$ARCANE_DEVICE" "$selected_name" "$volume" || {
                    rm -rf "$tmpdir"
                    return 1
                }
            done
        done

        (cd "$tmpdir" && 7z a -p -mhe=on "$output" .)
        rm -rf "$tmpdir"
    else
        (cd "$ARCANE_DIR" && 7z a -p -mhe=on "$output" "${rel_paths[@]}")
    fi

    echo
    echo "Archive: $output"

    _arcane_dump_write_gitignore "arcane-env-dump-*.7z"
    _arcane_dump_write_gitignore "arcane-dump-*.7z"
}

_arcane_restore() {
    local archive="$1"
    shift || true
    local force=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force|-f)
                force=true
                shift
                ;;
            *)
                echo "error: unknown option: $1" >&2
                return 1
                ;;
        esac
    done

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
    trap "rm -rf '$tmpdir'" RETURN

    if ! 7z x -o"$tmpdir" "$archive"; then
        echo "error: failed to extract archive" >&2
        return 1
    fi

    if [[ -f "$tmpdir/manifest.tsv" ]]; then
        if [[ "$force" != "true" ]]; then
            local preflight_line preflight_kind
            while IFS= read -r preflight_line; do
                [[ -n "$preflight_line" ]] || continue
                IFS=$'\t' read -r preflight_kind _rest <<<"$preflight_line"
                case "$preflight_kind" in
                    file)
                        local preflight_rel preflight_archive_rel preflight_target
                        IFS=$'\t' read -r _kind preflight_rel preflight_archive_rel <<<"$preflight_line"
                        preflight_target="$ARCANE_DIR/$preflight_rel"
                        if [[ -e "$preflight_target" ]]; then
                            echo "error: file already exists; rerun with --force: $preflight_rel" >&2
                            return 1
                        fi
                        ;;
                    volume)
                        local preflight_device preflight_project preflight_volume preflight_volume_archive
                        IFS=$'\t' read -r _kind preflight_device preflight_project preflight_volume preflight_volume_archive <<<"$preflight_line"
                        if docker volume inspect "$preflight_volume" >/dev/null 2>&1; then
                            echo "error: volume already exists; rerun with --force: $preflight_volume" >&2
                            return 1
                        fi
                        ;;
                esac
            done < "$tmpdir/manifest.tsv"
        fi

        local line kind
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            IFS=$'\t' read -r kind _rest <<<"$line"
            case "$kind" in
                file)
                    local rel archive_rel target
                    IFS=$'\t' read -r _kind rel archive_rel <<<"$line"
                    target="$ARCANE_DIR/$rel"
                    if [[ -e "$target" && "$force" != "true" ]]; then
                        echo "error: file already exists; rerun with --force: $rel" >&2
                        return 1
                    fi
                    mkdir -p "$(dirname "$target")"
                    cp "$tmpdir/$archive_rel" "$target"
                    echo "Restored: $rel"
                    ;;
                volume)
                    local device project volume archive_rel
                    IFS=$'\t' read -r _kind device project volume archive_rel <<<"$line"
                    if [[ "$force" == "true" ]] && docker volume inspect "$volume" >/dev/null 2>&1; then
                        docker volume rm "$volume" >/dev/null 2>&1 || true
                    fi
                    docker volume create "$volume" >/dev/null
                    if ! docker run --rm -v "$volume:/volume" -v "$(dirname "$tmpdir/$archive_rel"):/backup" alpine tar -C /volume -xf "/backup/$(basename "$archive_rel")"; then
                        echo "error: failed to restore volume: $volume" >&2
                        return 1
                    fi
                    echo "Restored volume: $volume"
                    ;;
                *)
                    echo "error: unknown manifest entry: $kind" >&2
                    return 1
                    ;;
            esac
        done < "$tmpdir/manifest.tsv"

        echo "Done."
        return 0
    fi

    local env_files=()
    while IFS= read -r -d '' f; do
        env_files+=("$f")
    done < <(find "$tmpdir" -type f -print0)

    if [[ ${#env_files[@]} -eq 0 ]]; then
        echo "no environment files found in archive" >&2
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
