class SystemCallError < StandardError
  def self.exception(*args)
    if args.size == 2
      detail = args.first
      num = args.last
    elsif args.size == 1
      detail = nil
      num = args.first
    else
      # TODO: Ruby accepts 3 args??
      raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 1..2)"
    end
    klass, message =
      {
        0 => [Errno::NOERROR, 'Success'],
        1 => [Errno::EPERM, 'Operation not permitted'],
        2 => [Errno::ENOENT, 'No such file or directory'],
        3 => [Errno::ESRCH, 'No such process'],
        4 => [Errno::EINTR, 'Interrupted system call'],
        5 => [Errno::EIO, 'Input/output error'],
        6 => [Errno::ENXIO, 'No such device or address'],
        7 => [Errno::E2BIG, 'Argument list too long'],
        8 => [Errno::ENOEXEC, 'Exec format error'],
        9 => [Errno::EBADF, 'Bad file descriptor'],
        10 => [Errno::ECHILD, 'No child processes'],
        11 => [Errno::EAGAIN, 'Resource temporarily unavailable'],
        12 => [Errno::ENOMEM, 'Cannot allocate memory'],
        13 => [Errno::EACCES, 'Permission denied'],
        14 => [Errno::EFAULT, 'Bad address'],
        15 => [Errno::ENOTBLK, 'Block device required'],
        16 => [Errno::EBUSY, 'Device or resource busy'],
        17 => [Errno::EEXIST, 'File exists'],
        18 => [Errno::EXDEV, 'Invalid cross-device link'],
        19 => [Errno::ENODEV, 'No such device'],
        20 => [Errno::ENOTDIR, 'Not a directory'],
        21 => [Errno::EISDIR, 'Is a directory'],
        22 => [Errno::EINVAL, 'Invalid argument'],
        23 => [Errno::ENFILE, 'Too many open files in system'],
        24 => [Errno::EMFILE, 'Too many open files'],
        25 => [Errno::ENOTTY, 'Inappropriate ioctl for device'],
        26 => [Errno::ETXTBSY, 'Text file busy'],
        27 => [Errno::EFBIG, 'File too large'],
        28 => [Errno::ENOSPC, 'No space left on device'],
        29 => [Errno::ESPIPE, 'Illegal seek'],
        30 => [Errno::EROFS, 'Read-only file system'],
        31 => [Errno::EMLINK, 'Too many links'],
        32 => [Errno::EPIPE, 'Broken pipe'],
        33 => [Errno::EDOM, 'Numerical argument out of domain'],
        34 => [Errno::ERANGE, 'Numerical result out of range'],
        35 => [Errno::EDEADLK, 'Resource deadlock avoided'],
        36 => [Errno::ENAMETOOLONG, 'File name too long'],
        37 => [Errno::ENOLCK, 'No locks available'],
        38 => [Errno::ENOSYS, 'Function not implemented'],
        39 => [Errno::ENOTEMPTY, 'Directory not empty'],
        40 => [Errno::ELOOP, 'Too many levels of symbolic links'],
        42 => [Errno::ENOMSG, 'No message of desired type'],
        43 => [Errno::EIDRM, 'Identifier removed'],
        44 => [Errno::ECHRNG, 'Channel number out of range'],
        45 => [Errno::EL2NSYNC, 'Level 2 not synchronized'],
        46 => [Errno::EL3HLT, 'Level 3 halted'],
        47 => [Errno::EL3RST, 'Level 3 reset'],
        48 => [Errno::ELNRNG, 'Link number out of range'],
        49 => [Errno::EUNATCH, 'Protocol driver not attached'],
        50 => [Errno::ENOCSI, 'No CSI structure available'],
        51 => [Errno::EL2HLT, 'Level 2 halted'],
        52 => [Errno::EBADE, 'Invalid exchange'],
        53 => [Errno::EBADR, 'Invalid request descriptor'],
        54 => [Errno::EXFULL, 'Exchange full'],
        55 => [Errno::ENOANO, 'No anode'],
        56 => [Errno::EBADRQC, 'Invalid request code'],
        57 => [Errno::EBADSLT, 'Invalid slot'],
        59 => [Errno::EBFONT, 'Bad font file format'],
        60 => [Errno::ENOSTR, 'Device not a stream'],
        61 => [Errno::ENODATA, 'No data available'],
        62 => [Errno::ETIME, 'Timer expired'],
        63 => [Errno::ENOSR, 'Out of streams resources'],
        64 => [Errno::ENONET, 'Machine is not on the network'],
        65 => [Errno::ENOPKG, 'Package not installed'],
        66 => [Errno::EREMOTE, 'Object is remote'],
        67 => [Errno::ENOLINK, 'Link has been severed'],
        68 => [Errno::EADV, 'Advertise error'],
        69 => [Errno::ESRMNT, 'Srmount error'],
        70 => [Errno::ECOMM, 'Communication error on send'],
        71 => [Errno::EPROTO, 'Protocol error'],
        72 => [Errno::EMULTIHOP, 'Multihop attempted'],
        73 => [Errno::EDOTDOT, 'RFS specific error'],
        74 => [Errno::EBADMSG, 'Bad message'],
        75 => [Errno::EOVERFLOW, 'Object too large for defined data type'],
        76 => [Errno::ENOTUNIQ, 'Name not unique on network'],
        77 => [Errno::EBADFD, 'File descriptor in bad state'],
        78 => [Errno::EREMCHG, 'Remote address changed'],
        79 => [Errno::ELIBACC, 'Can not access a needed shared library'],
        80 => [Errno::ELIBBAD, 'Accessing a corrupted shared library'],
        81 => [Errno::ELIBSCN, '.lib section in a.out corrupted'],
        82 => [Errno::ELIBMAX, 'Attempting to link in too many shared libraries'],
        83 => [Errno::ELIBEXEC, 'Cannot exec a shared library directly'],
        84 => [Errno::EILSEQ, 'Invalid or incomplete multibyte or wide character'],
        85 => [Errno::ERESTART, 'Interrupted system call should be restarted'],
        86 => [Errno::ESTRPIPE, 'Streams pipe error'],
        87 => [Errno::EUSERS, 'Too many users'],
        88 => [Errno::ENOTSOCK, 'Socket operation on non-socket'],
        89 => [Errno::EDESTADDRREQ, 'Destination address required'],
        90 => [Errno::EMSGSIZE, 'Message too long'],
        91 => [Errno::EPROTOTYPE, 'Protocol wrong type for socket'],
        92 => [Errno::ENOPROTOOPT, 'Protocol not available'],
        93 => [Errno::EPROTONOSUPPORT, 'Protocol not supported'],
        94 => [Errno::ESOCKTNOSUPPORT, 'Socket type not supported'],
        95 => [Errno::ENOTSUP, 'Operation not supported'],
        96 => [Errno::EPFNOSUPPORT, 'Protocol family not supported'],
        97 => [Errno::EAFNOSUPPORT, 'Address family not supported by protocol'],
        98 => [Errno::EADDRINUSE, 'Address already in use'],
        99 => [Errno::EADDRNOTAVAIL, 'Cannot assign requested address'],
        100 => [Errno::ENETDOWN, 'Network is down'],
        101 => [Errno::ENETUNREACH, 'Network is unreachable'],
        102 => [Errno::ENETRESET, 'Network dropped connection on reset'],
        103 => [Errno::ECONNABORTED, 'Software caused connection abort'],
        104 => [Errno::ECONNRESET, 'Connection reset by peer'],
        105 => [Errno::ENOBUFS, 'No buffer space available'],
        106 => [Errno::EISCONN, 'Transport endpoint is already connected'],
        107 => [Errno::ENOTCONN, 'Transport endpoint is not connected'],
        108 => [Errno::ESHUTDOWN, 'Cannot send after transport endpoint shutdown'],
        109 => [Errno::ETOOMANYREFS, 'Too many references: cannot splice'],
        110 => [Errno::ETIMEDOUT, 'Connection timed out'],
        111 => [Errno::ECONNREFUSED, 'Connection refused'],
        112 => [Errno::EHOSTDOWN, 'Host is down'],
        113 => [Errno::EHOSTUNREACH, 'No route to host'],
        114 => [Errno::EALREADY, 'Operation already in progress'],
        115 => [Errno::EINPROGRESS, 'Operation now in progress'],
        116 => [Errno::ESTALE, 'Stale file handle'],
        117 => [Errno::EUCLEAN, 'Structure needs cleaning'],
        118 => [Errno::ENOTNAM, 'Not a XENIX named type file'],
        119 => [Errno::ENAVAIL, 'No XENIX semaphores available'],
        120 => [Errno::EISNAM, 'Is a named type file'],
        121 => [Errno::EREMOTEIO, 'Remote I/O error'],
        122 => [Errno::EDQUOT, 'Disk quota exceeded'],
        123 => [Errno::ENOMEDIUM, 'No medium found'],
        124 => [Errno::EMEDIUMTYPE, 'Wrong medium type'],
        125 => [Errno::ECANCELED, 'Operation canceled'],
        126 => [Errno::ENOKEY, 'Required key not available'],
        127 => [Errno::EKEYEXPIRED, 'Key has expired'],
        128 => [Errno::EKEYREVOKED, 'Key has been revoked'],
        129 => [Errno::EKEYREJECTED, 'Key was rejected by service'],
        130 => [Errno::EOWNERDEAD, 'Owner died'],
        131 => [Errno::ENOTRECOVERABLE, 'State not recoverable'],
        132 => [Errno::ERFKILL, 'Operation not possible due to RF-kill'],
        133 => [Errno::EHWPOISON, 'Memory page has hardware error'],
      }[
        num
      ]
    if klass
      message = "#{message} - #{detail}" if detail
      klass.new(message)
    else
      new("Unknown error #{num}")
    end
  end

  def errno
    self::Errno
  end
end

module Errno
  class NOERROR < SystemCallError
    Errno = 0
  end

  class EPERM < SystemCallError
    Errno = 1
  end

  class ENOENT < SystemCallError
    Errno = 2
  end

  class ESRCH < SystemCallError
    Errno = 3
  end

  class EINTR < SystemCallError
    Errno = 4
  end

  class EIO < SystemCallError
    Errno = 5
  end

  class ENXIO < SystemCallError
    Errno = 6
  end

  class E2BIG < SystemCallError
    Errno = 7
  end

  class ENOEXEC < SystemCallError
    Errno = 8
  end

  class EBADF < SystemCallError
    Errno = 9
  end

  class ECHILD < SystemCallError
    Errno = 10
  end

  class EAGAIN < SystemCallError
    Errno = 11
  end

  class EAGAIN < SystemCallError
    Errno = 11
  end

  class ENOMEM < SystemCallError
    Errno = 12
  end

  class EACCES < SystemCallError
    Errno = 13
  end

  class EFAULT < SystemCallError
    Errno = 14
  end

  class ENOTBLK < SystemCallError
    Errno = 15
  end

  class EBUSY < SystemCallError
    Errno = 16
  end

  class EEXIST < SystemCallError
    Errno = 17
  end

  class EXDEV < SystemCallError
    Errno = 18
  end

  class ENODEV < SystemCallError
    Errno = 19
  end

  class ENOTDIR < SystemCallError
    Errno = 20
  end

  class EISDIR < SystemCallError
    Errno = 21
  end

  class EINVAL < SystemCallError
    Errno = 22
  end

  class ENFILE < SystemCallError
    Errno = 23
  end

  class EMFILE < SystemCallError
    Errno = 24
  end

  class ENOTTY < SystemCallError
    Errno = 25
  end

  class ETXTBSY < SystemCallError
    Errno = 26
  end

  class EFBIG < SystemCallError
    Errno = 27
  end

  class ENOSPC < SystemCallError
    Errno = 28
  end

  class ESPIPE < SystemCallError
    Errno = 29
  end

  class EROFS < SystemCallError
    Errno = 30
  end

  class EMLINK < SystemCallError
    Errno = 31
  end

  class EPIPE < SystemCallError
    Errno = 32
  end

  class EDOM < SystemCallError
    Errno = 33
  end

  class ERANGE < SystemCallError
    Errno = 34
  end

  class EDEADLK < SystemCallError
    Errno = 35
  end

  class EDEADLK < SystemCallError
    Errno = 35
  end

  class ENAMETOOLONG < SystemCallError
    Errno = 36
  end

  class ENOLCK < SystemCallError
    Errno = 37
  end

  class ENOSYS < SystemCallError
    Errno = 38
  end

  class ENOTEMPTY < SystemCallError
    Errno = 39
  end

  class ELOOP < SystemCallError
    Errno = 40
  end

  class ENOMSG < SystemCallError
    Errno = 42
  end

  class EIDRM < SystemCallError
    Errno = 43
  end

  class ECHRNG < SystemCallError
    Errno = 44
  end

  class EL2NSYNC < SystemCallError
    Errno = 45
  end

  class EL3HLT < SystemCallError
    Errno = 46
  end

  class EL3RST < SystemCallError
    Errno = 47
  end

  class ELNRNG < SystemCallError
    Errno = 48
  end

  class EUNATCH < SystemCallError
    Errno = 49
  end

  class ENOCSI < SystemCallError
    Errno = 50
  end

  class EL2HLT < SystemCallError
    Errno = 51
  end

  class EBADE < SystemCallError
    Errno = 52
  end

  class EBADR < SystemCallError
    Errno = 53
  end

  class EXFULL < SystemCallError
    Errno = 54
  end

  class ENOANO < SystemCallError
    Errno = 55
  end

  class EBADRQC < SystemCallError
    Errno = 56
  end

  class EBADSLT < SystemCallError
    Errno = 57
  end

  class EBFONT < SystemCallError
    Errno = 59
  end

  class ENOSTR < SystemCallError
    Errno = 60
  end

  class ENODATA < SystemCallError
    Errno = 61
  end

  class ETIME < SystemCallError
    Errno = 62
  end

  class ENOSR < SystemCallError
    Errno = 63
  end

  class ENONET < SystemCallError
    Errno = 64
  end

  class ENOPKG < SystemCallError
    Errno = 65
  end

  class EREMOTE < SystemCallError
    Errno = 66
  end

  class ENOLINK < SystemCallError
    Errno = 67
  end

  class EADV < SystemCallError
    Errno = 68
  end

  class ESRMNT < SystemCallError
    Errno = 69
  end

  class ECOMM < SystemCallError
    Errno = 70
  end

  class EPROTO < SystemCallError
    Errno = 71
  end

  class EMULTIHOP < SystemCallError
    Errno = 72
  end

  class EDOTDOT < SystemCallError
    Errno = 73
  end

  class EBADMSG < SystemCallError
    Errno = 74
  end

  class EOVERFLOW < SystemCallError
    Errno = 75
  end

  class ENOTUNIQ < SystemCallError
    Errno = 76
  end

  class EBADFD < SystemCallError
    Errno = 77
  end

  class EREMCHG < SystemCallError
    Errno = 78
  end

  class ELIBACC < SystemCallError
    Errno = 79
  end

  class ELIBBAD < SystemCallError
    Errno = 80
  end

  class ELIBSCN < SystemCallError
    Errno = 81
  end

  class ELIBMAX < SystemCallError
    Errno = 82
  end

  class ELIBEXEC < SystemCallError
    Errno = 83
  end

  class EILSEQ < SystemCallError
    Errno = 84
  end

  class ERESTART < SystemCallError
    Errno = 85
  end

  class ESTRPIPE < SystemCallError
    Errno = 86
  end

  class EUSERS < SystemCallError
    Errno = 87
  end

  class ENOTSOCK < SystemCallError
    Errno = 88
  end

  class EDESTADDRREQ < SystemCallError
    Errno = 89
  end

  class EMSGSIZE < SystemCallError
    Errno = 90
  end

  class EPROTOTYPE < SystemCallError
    Errno = 91
  end

  class ENOPROTOOPT < SystemCallError
    Errno = 92
  end

  class EPROTONOSUPPORT < SystemCallError
    Errno = 93
  end

  class ESOCKTNOSUPPORT < SystemCallError
    Errno = 94
  end

  class ENOTSUP < SystemCallError
    Errno = 95
  end

  class EOPNOTSUPP < SystemCallError
    Errno = 95
  end

  class EPFNOSUPPORT < SystemCallError
    Errno = 96
  end

  class EAFNOSUPPORT < SystemCallError
    Errno = 97
  end

  class EADDRINUSE < SystemCallError
    Errno = 98
  end

  class EADDRNOTAVAIL < SystemCallError
    Errno = 99
  end

  class ENETDOWN < SystemCallError
    Errno = 100
  end

  class ENETUNREACH < SystemCallError
    Errno = 101
  end

  class ENETRESET < SystemCallError
    Errno = 102
  end

  class ECONNABORTED < SystemCallError
    Errno = 103
  end

  class ECONNRESET < SystemCallError
    Errno = 104
  end

  class ENOBUFS < SystemCallError
    Errno = 105
  end

  class EISCONN < SystemCallError
    Errno = 106
  end

  class ENOTCONN < SystemCallError
    Errno = 107
  end

  class ESHUTDOWN < SystemCallError
    Errno = 108
  end

  class ETOOMANYREFS < SystemCallError
    Errno = 109
  end

  class ETIMEDOUT < SystemCallError
    Errno = 110
  end

  class ECONNREFUSED < SystemCallError
    Errno = 111
  end

  class EHOSTDOWN < SystemCallError
    Errno = 112
  end

  class EHOSTUNREACH < SystemCallError
    Errno = 113
  end

  class EALREADY < SystemCallError
    Errno = 114
  end

  class EINPROGRESS < SystemCallError
    Errno = 115
  end

  class ESTALE < SystemCallError
    Errno = 116
  end

  class EUCLEAN < SystemCallError
    Errno = 117
  end

  class ENOTNAM < SystemCallError
    Errno = 118
  end

  class ENAVAIL < SystemCallError
    Errno = 119
  end

  class EISNAM < SystemCallError
    Errno = 120
  end

  class EREMOTEIO < SystemCallError
    Errno = 121
  end

  class EDQUOT < SystemCallError
    Errno = 122
  end

  class ENOMEDIUM < SystemCallError
    Errno = 123
  end

  class EMEDIUMTYPE < SystemCallError
    Errno = 124
  end

  class ECANCELED < SystemCallError
    Errno = 125
  end

  class ENOKEY < SystemCallError
    Errno = 126
  end

  class EKEYEXPIRED < SystemCallError
    Errno = 127
  end

  class EKEYREVOKED < SystemCallError
    Errno = 128
  end

  class EKEYREJECTED < SystemCallError
    Errno = 129
  end

  class EOWNERDEAD < SystemCallError
    Errno = 130
  end

  class ENOTRECOVERABLE < SystemCallError
    Errno = 131
  end

  class ERFKILL < SystemCallError
    Errno = 132
  end

  class EHWPOISON < SystemCallError
    Errno = 133
  end
end
