#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

VERSION=""
SIGN_IDENTITY="-"  # 默认 ad-hoc 签名
SIGN_INTERACTIVE=0 # --sign 未给值时为 1，进入交互式选择
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --sign)
            if [[ $# -gt 1 && "$2" != --* ]]; then
                SIGN_IDENTITY="$2"
                shift 2
            else
                SIGN_INTERACTIVE=1
                shift
            fi
            ;;
        *)
            shift
            ;;
    esac
done

# ad-hoc 签名（默认）下，launchd 无法加载 SMJobBless 的 Helper。
# 只在 SIGN_IDENTITY 为 "-" 时打印警告，且不影响脚本继续执行。
warn_if_adhoc() {
    if [[ "$SIGN_IDENTITY" == "-" ]]; then
        echo ""
        echo "    WARNING: 当前使用 ad-hoc 签名（SIGN_IDENTITY=\"-\"）。"
        echo "    WARNING: SMJobBless 特权 Helper 在 ad-hoc 签名下无法被 launchd 加载，安装会失败，"
        echo "    WARNING: App 会自动回退到「每次输入管理员密码」的执行方式（功能不受影响）。"
        echo "    WARNING: 如需免密静默执行，请用正式证书构建："
        echo "    WARNING:   bash build-app.sh --sign \"Developer ID Application: <你的名字> (TEAMID)\""
        echo ""
    fi
}

# ---------------------------------------------------------------------------
# 签名身份选择（--sign 未给值时交互式列出本机证书）
# ---------------------------------------------------------------------------

CERT_DUMP=""            # security find-certificate -a -Z -p 的完整输出
XCODE_TEAM_IDS=()       # Xcode 团队表：teamID / teamName / teamType 三组平行数组
XCODE_TEAM_NAMES=()
XCODE_TEAM_TYPES=()
SIGN_IDENT_HASHES=()    # 去重后的 SHA-1（仅用于去重，不展示）
SIGN_IDENT_NAMES=()     # 证书名
SIGN_IDENT_TEAMS=()     # 团队名（取证书 O=，优先用 Xcode 团队表里的 teamName）
SIGN_IDENT_TEAMIDS=()   # TeamID（取证书 OU=）
SIGN_IDENT_KINDS=()     # 个人 / 团队
SIGN_MENU_ROWS=()       # 已对齐列宽的展示行，第 0 行为表头
SIGN_MENU_CURSOR=0      # 当前高亮项（0 起）
SIGN_MENU_BUF=""        # 已输入的数字
SIGN_MENU_LINES=0       # 菜单占用的终端行数，用于回退重绘
MENU_KEY=""             # 最近一次按键：UP/DOWN/DIGIT/BACKSPACE/ENTER/QUIT/IGNORE
MENU_KEY_CHAR=""        # 数字键对应的字符

# 读取 Xcode 团队表（teamID / teamName / teamType 成组出现）
_load_xcode_teams() {
    local plist="$HOME/Library/Preferences/com.apple.dt.Xcode.plist"
    local rows line key val id="" name=""

    [ -f "$plist" ] || return 0
    rows=$(plutil -p "$plist" 2>/dev/null | grep -E '"(teamID|teamName|teamType)"' || true)
    [ -n "$rows" ] || return 0

    while IFS= read -r line; do
        key=$(printf '%s' "$line" | sed -E 's/^[[:space:]]*"([^"]*)"[[:space:]]*=>.*$/\1/')
        val=$(printf '%s' "$line" | sed -E 's/^[^=]*=>[[:space:]]*"(.*)"[[:space:]]*$/\1/')
        case "$key" in
            teamID)   id="$val" ;;
            teamName) name="$val" ;;
            teamType)
                if [ -n "$id" ]; then
                    XCODE_TEAM_IDS+=("$id")
                    XCODE_TEAM_NAMES+=("$name")
                    XCODE_TEAM_TYPES+=("$val")
                fi
                id=""
                name=""
                ;;
        esac
    done <<< "$rows"
}

# 按 TeamID 查 Xcode 团队表，命中时输出 "<teamName>\t<teamType>"
_xcode_team_lookup() {
    local want="$1" i=0
    while [ $i -lt ${#XCODE_TEAM_IDS[@]} ]; do
        if [ "${XCODE_TEAM_IDS[$i]}" == "$want" ]; then
            printf '%s\t%s' "${XCODE_TEAM_NAMES[$i]}" "${XCODE_TEAM_TYPES[$i]}"
            return 0
        fi
        i=$((i + 1))
    done
    return 1
}

# 从证书 subject 里按 SHA-1 精确定位，取某个字段（O= / OU=）。
# 本机存在同名同 CN 但 SHA-1 不同的证书，因此不能按 CN 抓第一张。
_cert_field_by_hash() {
    local hash="$1" field="$2" pem
    pem=$(printf '%s\n' "$CERT_DUMP" | awk -v want="$hash" '
        /^SHA-1 hash: / { cur = $3; next }
        cur == want { print }
    ')
    [ -n "$pem" ] || return 0
    printf '%s\n' "$pem" \
        | openssl x509 -noout -subject -nameopt sep_multiline,utf8 2>/dev/null \
        | sed -n "s/^ *${field}=//p" \
        | awk 'NR == 1'
}

# 从证书名里取出用户名：去掉 "Apple Development: " 前缀和末尾 " (XXXX)" 后缀
_identity_user_name() {
    printf '%s' "$1" \
        | sed -E 's/^(Apple Development|Apple Distribution|iPhone Developer|iPhone Distribution|Mac Developer|Developer ID Application|Developer ID Installer|Apple ID): //' \
        | sed -E 's/[[:space:]]*\([0-9A-Z]+\)$//'
}

# 收集本机所有可签名证书：按 SHA-1 去重，补齐团队名 / TeamID 与个人-团队判定
_load_signing_identities() {
    local line hash name o ou team teamid kind user entry i hit

    CERT_DUMP=$(security find-certificate -a -Z -p 2>/dev/null || true)
    _load_xcode_teams

    while IFS= read -r line; do
        case "$line" in
            *'"'*) ;;
            *) continue ;;
        esac
        hash=$(printf '%s' "$line" | sed -E 's/^[[:space:]]*[0-9]+\)[[:space:]]*([0-9A-F]+).*$/\1/')
        case "$hash" in
            ""|*[!0-9A-F]*) continue ;;
        esac
        name=$(printf '%s' "$line" | sed -E 's/^[^"]*"([^"]*)"[[:space:]]*$/\1/')

        # 同一证书会被重复列出，按 SHA-1 去重
        hit=0
        i=0
        while [ $i -lt ${#SIGN_IDENT_HASHES[@]} ]; do
            if [ "${SIGN_IDENT_HASHES[$i]}" == "$hash" ]; then
                hit=1
                break
            fi
            i=$((i + 1))
        done
        [ "$hit" -eq 0 ] || continue

        o=$(_cert_field_by_hash "$hash" O)
        ou=$(_cert_field_by_hash "$hash" OU)
        team="$o"
        teamid="$ou"
        kind=""

        # 优先读 Xcode 团队表：teamType == "Personal Team" 为个人，Company 为团队
        if [ -n "$teamid" ] && entry=$(_xcode_team_lookup "$teamid"); then
            team="${entry%%$'\t'*}"
            case "${entry##*$'\t'}" in
                "Personal Team") kind="个人" ;;
                *) kind="团队" ;;
            esac
        fi

        # 读不到团队表时退化：O 等于用户名，或 O 含 Personal → 个人
        if [ -z "$kind" ]; then
            user=$(_identity_user_name "$name")
            if [ -n "$o" ] && [ "$o" == "$user" ]; then
                kind="个人"
            else
                case "$o" in
                    *Personal*) kind="个人" ;;
                    *) kind="团队" ;;
                esac
            fi
        fi

        [ -n "$team" ] || team="-"
        [ -n "$teamid" ] || teamid="-"

        SIGN_IDENT_HASHES+=("$hash")
        SIGN_IDENT_NAMES+=("$name")
        SIGN_IDENT_TEAMS+=("$team")
        SIGN_IDENT_TEAMIDS+=("$teamid")
        SIGN_IDENT_KINDS+=("$kind")
    done <<< "$(security find-identity -v -p codesigning 2>/dev/null || true)"

    _dedupe_identity_labels
}

# 同名证书（重复签发）展示时追加短 SHA-1，避免列表出现两行完全相同
_dedupe_identity_labels() {
    local i j total dup label
    total=${#SIGN_IDENT_NAMES[@]}
    SIGN_IDENT_LABELS=()
    i=0
    while [ $i -lt "$total" ]; do
        dup=0
        j=0
        while [ $j -lt "$total" ]; do
            if [ $j -ne $i ] && [ "${SIGN_IDENT_NAMES[$j]}" == "${SIGN_IDENT_NAMES[$i]}" ]; then
                dup=1
                break
            fi
            j=$((j + 1))
        done
        label="${SIGN_IDENT_NAMES[$i]}"
        if [ "$dup" -eq 1 ]; then
            label="$label [${SIGN_IDENT_HASHES[$i]:0:8}]"
        fi
        SIGN_IDENT_LABELS+=("$label")
        i=$((i + 1))
    done
}

# 生成对齐后的展示行：列宽按显示宽度（中文按 2 列）自适应
_build_menu_rows() {
    local tsv row i total
    total=${#SIGN_IDENT_NAMES[@]}

    tsv=$(printf '%s\t%s\t%s\t%s\t%s\n' "序号" "证书" "团队" "TeamID" "类型")
    tsv+=$'\n'   # 命令替换会吃掉行尾换行，这里补回来
    i=0
    while [ $i -lt "$total" ]; do
        tsv+=$(printf '%s\t%s\t%s\t%s\t%s\n' \
            "$((i + 1))" "${SIGN_IDENT_LABELS[$i]}" "${SIGN_IDENT_TEAMS[$i]}" \
            "${SIGN_IDENT_TEAMIDS[$i]}" "${SIGN_IDENT_KINDS[$i]}")
        tsv+=$'\n'   # 命令替换会吃掉行尾换行，这里补回来
        i=$((i + 1))
    done
    tsv+=$(printf '%s\t%s\t%s\t%s\t%s\n' "$((total + 1))" \
        "ad-hoc（不签名；Helper 不可用，自动回退密码方式）" "-" "-" "ad-hoc")

    SIGN_MENU_ROWS=()
    while IFS= read -r row; do
        SIGN_MENU_ROWS+=("$row")
    done <<< "$(printf '%s' "$tsv" | LC_ALL=C awk -F'\t' '
        BEGIN {
            for (i = 1; i < 256; i++) ORD[sprintf("%c", i)] = i
            for (c = 1; c <= 5; c++) W[c] = 0
        }
        # 显示宽度：按 UTF-8 字节判断，中文等三/四字节字符按 2 列计，续字节不计数
        function dw(s,   n, i, v, w) {
            n = length(s); w = 0
            for (i = 1; i <= n; i++) {
                v = ORD[substr(s, i, 1)]
                if (v >= 224) w += 2
                else if (v >= 192) w += 1
                else if (v < 128) w += 1
            }
            return w
        }
        function pad(s, target,   n) {
            n = target - dw(s)
            while (n-- > 0) s = s " "
            return s
        }
        {
            for (c = 1; c <= 5; c++) {
                line[c, NR] = $c
                w = dw($c)
                if (w > W[c]) W[c] = w
            }
            rows = NR
        }
        END {
            for (r = 1; r <= rows; r++) {
                out = ""
                for (c = 1; c <= 5; c++) {
                    if (c == 5) out = out line[c, r]
                    else out = out pad(line[c, r], W[c] + 2)
                }
                print out
            }
        }
    ')"
}

# 重绘菜单（列表 + 空行 + 操作提示）
_render_menu() {
    local i=0 row
    while [ $i -lt ${#SIGN_MENU_ROWS[@]} ]; do
        row="${SIGN_MENU_ROWS[$i]}"
        if [ "$i" -eq $((SIGN_MENU_CURSOR + 1)) ]; then
            printf '\033[7m%s\033[0m\033[K\n' "$row"
        else
            printf '%s\033[K\n' "$row"
        fi
        i=$((i + 1))
    done
    printf '\033[K\n'
    if [ -n "$SIGN_MENU_BUF" ]; then
        printf '  ↑/↓ 选择，输入序号可直接跳转，回车确认，q 取消（已输入 %s）\033[K\n' "$SIGN_MENU_BUF"
    else
        printf '  ↑/↓ 选择，输入序号可直接跳转，回车确认，q 取消\033[K\n'
    fi
}

# 从 /dev/tty 读一个按键，结果放在 MENU_KEY / MENU_KEY_CHAR
_read_menu_key() {
    local c="" c2="" c3=""
    MENU_KEY="IGNORE"
    MENU_KEY_CHAR=""

    if ! IFS= read -rsn1 c </dev/tty; then
        MENU_KEY="QUIT"
        return 0
    fi
    if [ -z "$c" ]; then
        MENU_KEY="ENTER"
        return 0
    fi
    if [ "$c" == $'\033' ]; then
        IFS= read -rsn1 -t 1 c2 </dev/tty || c2=""
        if [ "$c2" == "[" ]; then
            IFS= read -rsn1 -t 1 c3 </dev/tty || c3=""
            case "$c3" in
                A) MENU_KEY="UP" ;;
                B) MENU_KEY="DOWN" ;;
            esac
        fi
        return 0
    fi
    case "$c" in
        $'\177'|$'\010') MENU_KEY="BACKSPACE" ;;
        [qQ]) MENU_KEY="QUIT" ;;
        [0-9]) MENU_KEY="DIGIT"; MENU_KEY_CHAR="$c" ;;
    esac
    return 0
}

# 序号是否落在 1..证书数+1（最后一项为 ad-hoc）
_valid_selection() {
    local idx="$1" total=${#SIGN_IDENT_NAMES[@]}
    case "$idx" in
        ""|*[!0-9]*) return 1 ;;
    esac
    [ "$idx" -ge 1 ] && [ "$idx" -le $((total + 1)) ]
}

# 应用选择结果到 SIGN_IDENTITY
_apply_selection() {
    local idx="$1" total=${#SIGN_IDENT_NAMES[@]}
    if [ "$idx" -eq $((total + 1)) ]; then
        SIGN_IDENTITY="-"
        echo "==> 使用签名身份: ad-hoc（不签名）"
        echo "    提示: Helper 需要正式证书才能免密安装，本次构建会自动回退密码方式"
    else
        i=$((idx - 1))
        SIGN_IDENTITY="${SIGN_IDENT_NAMES[$i]}"
        # 同名证书无法用名称区分，codesign 会报 ambiguous，改用 SHA-1 定位
        if [ "${SIGN_IDENT_LABELS[$i]}" != "${SIGN_IDENT_NAMES[$i]}" ]; then
            SIGN_IDENTITY="${SIGN_IDENT_HASHES[$i]}"
            echo "==> 使用签名身份: ${SIGN_IDENT_LABELS[$i]}"
            echo "    （同名证书按 SHA-1 签名: ${SIGN_IDENTITY}）"
        else
            echo "==> 使用签名身份: $SIGN_IDENTITY"
        fi
    fi
}

# 非 TTY（管道 / CI）：打印同样的列表，从 stdin 读一行
_select_signing_noninteractive() {
    local input idx i total
    total=${#SIGN_IDENT_NAMES[@]}

    printf '%s\n' "${SIGN_MENU_ROWS[@]}"
    printf '请输入序号或完整证书名: '
    if ! IFS= read -r input; then
        echo ""
        echo "ERROR: 未读取到选择输入，已退出构建"
        exit 1
    fi
    input=$(printf '%s' "$input" | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//')
    if [ -z "$input" ]; then
        echo ""
        echo "ERROR: 未选择签名身份，已退出构建"
        exit 1
    fi

    case "$input" in
        *[!0-9]*)
            idx=""
            if [ "$input" == "ad-hoc" ]; then
                idx=$((total + 1))
            else
                i=0
                while [ $i -lt "$total" ]; do
                    if [ "${SIGN_IDENT_LABELS[$i]}" == "$input" ] || [ "${SIGN_IDENT_NAMES[$i]}" == "$input" ]; then
                        idx=$((i + 1))
                        break
                    fi
                    i=$((i + 1))
                done
            fi
            if [ -z "$idx" ]; then
                echo ""
                echo "ERROR: 未找到匹配的证书: $input"
                exit 1
            fi
            ;;
        *)
            idx="$input"
            ;;
    esac

    if ! _valid_selection "$idx"; then
        echo ""
        echo "ERROR: 无效的序号: $idx"
        exit 1
    fi
    _apply_selection "$idx"
}

# TTY：↑/↓ 移动高亮，数字可直接跳转，回车确认，q / Ctrl-C 取消
_select_signing_interactive() {
    local total=${#SIGN_IDENT_NAMES[@]}
    local last=$((total + 1))

    SIGN_MENU_CURSOR=0
    SIGN_MENU_BUF=""
    SIGN_MENU_LINES=$(( ${#SIGN_MENU_ROWS[@]} + 2 ))

    trap 'printf "\033[?25h"; echo ""; echo "已取消，未执行构建"; exit 1' INT
    printf '\033[?25l'
    _render_menu

    while true; do
        _read_menu_key
        case "$MENU_KEY" in
            UP)
                if [ "$SIGN_MENU_CURSOR" -gt 0 ]; then
                    SIGN_MENU_CURSOR=$((SIGN_MENU_CURSOR - 1))
                fi
                ;;
            DOWN)
                if [ "$SIGN_MENU_CURSOR" -lt $((last - 1)) ]; then
                    SIGN_MENU_CURSOR=$((SIGN_MENU_CURSOR + 1))
                fi
                ;;
            DIGIT)
                SIGN_MENU_BUF="${SIGN_MENU_BUF}${MENU_KEY_CHAR}"
                ;;
            BACKSPACE)
                if [ -n "$SIGN_MENU_BUF" ]; then
                    SIGN_MENU_BUF="${SIGN_MENU_BUF%?}"
                fi
                ;;
            ENTER)
                if [ -n "$SIGN_MENU_BUF" ]; then
                    if _valid_selection "$SIGN_MENU_BUF"; then
                        printf '\033[?25h'
                        trap - INT
                        _apply_selection "$SIGN_MENU_BUF"
                        return 0
                    fi
                    SIGN_MENU_BUF=""
                else
                    printf '\033[?25h'
                    trap - INT
                    _apply_selection $((SIGN_MENU_CURSOR + 1))
                    return 0
                fi
                ;;
            QUIT)
                printf '\033[?25h'
                trap - INT
                echo ""
                echo "已取消，未执行构建"
                exit 1
                ;;
        esac
        # 回到列表顶部重画，避免刷屏
        printf '\033[%dA' "$SIGN_MENU_LINES"
        _render_menu
    done
}

select_signing_identity() {
    echo "==> 未指定签名身份，请选择（也可用 --sign <证书名> 直接指定）"
    _load_signing_identities
    _build_menu_rows
    if [ -t 0 ] && [ -t 1 ]; then
        _select_signing_interactive
    else
        _select_signing_noninteractive
    fi
}

if [ "$SIGN_INTERACTIVE" -eq 1 ]; then
    select_signing_identity
fi

echo "==> swift build (release)"
swift build -c release

echo "==> verifying Helper sections embedded"
# SMJobBless 需要两个 section：
#   __info_plist    → CFBundleIdentifier / SMAuthorizedClients
#   __launchd_plist → Label / MachServices（缺失会返回 kSMErrorJobPlistNotFound）
if otool -s __TEXT __info_plist .build/release/PMSetHelper >/dev/null 2>&1; then
    echo "    OK: __info_plist section found"
else
    echo "    ERROR: Helper binary missing __info_plist section"
    echo "    Check Package.swift linkerSettings and Sources/PMSetHelper/Info.plist"
    exit 1
fi

if otool -s __TEXT __launchd_plist .build/release/PMSetHelper >/dev/null 2>&1; then
    echo "    OK: __launchd_plist section found"
else
    echo "    ERROR: Helper binary missing __launchd_plist section"
    echo "    Check Package.swift linkerSettings and Sources/PMSetHelper/launchd.plist"
    exit 1
fi

echo "==> generating icon"
ICON_SOURCE="Resources/AppIcon-1024.png"
if [ ! -f "$ICON_SOURCE" ]; then
    echo "    ERROR: missing icon source $ICON_SOURCE"
    exit 1
fi
if [ ! -f "PMSet.icns" ] || [ "$ICON_SOURCE" -nt "PMSet.icns" ]; then
    rm -rf icon.iconset && mkdir -p icon.iconset
    sips -z 16 16 "$ICON_SOURCE" --out icon.iconset/icon_16x16.png >/dev/null
    sips -z 32 32 "$ICON_SOURCE" --out icon.iconset/icon_16x16@2x.png >/dev/null
    sips -z 32 32 "$ICON_SOURCE" --out icon.iconset/icon_32x32.png >/dev/null
    sips -z 64 64 "$ICON_SOURCE" --out icon.iconset/icon_32x32@2x.png >/dev/null
    sips -z 128 128 "$ICON_SOURCE" --out icon.iconset/icon_128x128.png >/dev/null
    sips -z 256 256 "$ICON_SOURCE" --out icon.iconset/icon_128x128@2x.png >/dev/null
    sips -z 256 256 "$ICON_SOURCE" --out icon.iconset/icon_256x256.png >/dev/null
    sips -z 512 512 "$ICON_SOURCE" --out icon.iconset/icon_256x256@2x.png >/dev/null
    sips -z 512 512 "$ICON_SOURCE" --out icon.iconset/icon_512x512.png >/dev/null
    cp "$ICON_SOURCE" icon.iconset/icon_512x512@2x.png
    iconutil -c icns icon.iconset -o PMSet.icns
    rm -rf icon.iconset
fi

echo "==> assembling PMSet.app"
APP=PMSet.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchServices"

# 主程序
cp .build/release/PMSet "$APP/Contents/MacOS/PMSet"

# 特权 Helper Tool
# SMJobBless 要求：
#   1. 必须放在 Contents/Library/LaunchServices/ 目录下
#   2. 文件名必须与 Helper 的 CFBundleIdentifier 完全一致
#   3. 二进制必须内置 Info.plist（__TEXT,__info_plist section）
cp .build/release/PMSetHelper "$APP/Contents/Library/LaunchServices/local.pmset.helper"

cp PMSet.icns "$APP/Contents/Resources/PMSet.icns"
cp Info.plist "$APP/Contents/Info.plist"

# 菜单栏图标（模板图，含 @2x / @3x）
cp Resources/MenuBarAwake*.png "$APP/Contents/Resources/"
cp Resources/MenuBarSleep*.png "$APP/Contents/Resources/"

if [[ -n "$VERSION" ]]; then
    echo "==> setting version to $VERSION"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
fi

echo "==> signing with identity: $SIGN_IDENTITY"
warn_if_adhoc
# 签名顺序：先签名内部的 Helper 二进制，再签名整个 App bundle。
# 注意：Helper 必须先签名，App 签名时会把 Helper 的签名纳入 seal。
codesign --force --sign "$SIGN_IDENTITY" "$APP/Contents/Library/LaunchServices/local.pmset.helper"
codesign --force --sign "$SIGN_IDENTITY" "$APP"

echo "==> verifying code signature"
codesign --verify --deep --strict "$APP" && echo "    OK: signature valid"

echo "==> signature details"
codesign -dvv "$APP" 2>&1 | head -8 || true
echo "    ---"
codesign -dvv "$APP/Contents/Library/LaunchServices/local.pmset.helper" 2>&1 | head -8 || true

warn_if_adhoc

echo "==> done: $PWD/$APP"
