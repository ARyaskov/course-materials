#include <nestor/status.h>

#include <errno.h>

const char *nst_status_str(nst_status st) {
    switch (st) {
#define NST_X(name, value, text) case name: return text;
        NST_STATUS_LIST(NST_X)
#undef NST_X
    }
    return "unknown status";
}

nst_status nst_status_from_errno(int err) {
    switch (err) {
        case 0:        return NST_OK;
        case ENOMEM:   return NST_E_NOMEM;
        case ENOENT:   return NST_E_NOTFOUND;
        case EINVAL:   return NST_E_INVAL;
        case EAGAIN:   return NST_E_AGAIN;
        case EACCES:
        case EPERM:    return NST_E_LOCKED;
        case ENOSPC:
        case EDQUOT:   return NST_E_FULL;
        case EFBIG:    return NST_E_TOOBIG;
        default:       return NST_E_IO;
    }
}
