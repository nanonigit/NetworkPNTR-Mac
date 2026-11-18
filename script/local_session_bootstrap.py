"""Apply a narrowly scoped native-session bootstrap to an existing guest init."""

OLD = '''IFS=' ' read -r operation transport setup extra
[ "$operation" = ARTEX_BOOTSTRAP ] && [ -z "${extra:-}" ] || fail bootstrap-frame
[ "${#transport}" -eq 64 ] && [ "${#setup}" -eq 64 ] || fail bootstrap-length
case "$transport$setup" in *[!0-9a-f]*) fail bootstrap-encoding ;; esac'''
NEW = '''IFS=' ' read -r operation transport setup local_session extra
case "$operation" in
    ARTEX_BOOTSTRAP)
        [ -z "${local_session:-}${extra:-}" ] || fail bootstrap-frame
        ;;
    NETWORKPNTR_BOOTSTRAP_2)
        [ -z "${extra:-}" ] && [ "${#local_session}" -eq 64 ] || fail bootstrap-frame
        case "$local_session" in *[!0-9a-f]*) fail bootstrap-encoding ;; esac
        [ "$local_session" != "$transport" ] && [ "$local_session" != "$setup" ] || fail bootstrap-independence
        export NETWORKPNTR_LOCAL_SESSION_CAPABILITY="$local_session"
        ;;
    *) fail bootstrap-frame ;;
esac
[ "${#transport}" -eq 64 ] && [ "${#setup}" -eq 64 ] || fail bootstrap-length
case "$transport$setup" in *[!0-9a-f]*) fail bootstrap-encoding ;; esac
[ "$transport" != "$setup" ] || fail bootstrap-independence
unset local_session'''
UNSET = 'unset ARTEX_PG_DSN ARTEX_SETUP_TOKEN'


def patch_init(data):
    """Preserve every unrelated cloud/runtime modification; fail on source drift."""
    source = data.decode('utf-8')
    if source.count(OLD) != 1 or source.count(UNSET + '\n') != 1:
        raise ValueError('Unsupported guest bootstrap source')
    return source.replace(OLD, NEW).replace(UNSET + '\n', UNSET + ' NETWORKPNTR_LOCAL_SESSION_CAPABILITY\n').encode()
