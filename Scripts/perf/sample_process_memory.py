#!/usr/bin/env python3
"""Sample one explicit macOS PID; RSS and physical footprint are different columns.

No process discovery or termination. Sampling is 1 Hz by default, so peaks between
samples may be missed; lifetime_max_footprint is also reported by the kernel.
Stops on process exit, PID reuse, duration, or an optional stop-file appearing.
"""
import argparse
import csv
import ctypes
import os
from pathlib import Path
import sys
import time

# Darwin rusage_info_v4, from the SDK's sys/resource.h. uint64 fields follow UUID.
FIELDS = '''user_time system_time pkg_idle_wkups interrupt_wkups pageins wired_size
resident_size phys_footprint proc_start_abstime proc_exit_abstime child_user_time
child_system_time child_pkg_idle_wkups child_interrupt_wkups child_pageins
child_elapsed_abstime diskio_bytesread diskio_byteswritten cpu_time_qos_default
cpu_time_qos_maintenance cpu_time_qos_background cpu_time_qos_utility cpu_time_qos_legacy
cpu_time_qos_user_initiated cpu_time_qos_user_interactive billed_system_time
serviced_system_time logical_writes lifetime_max_phys_footprint instructions cycles
billed_energy serviced_energy interval_max_phys_footprint runnable_time'''.split()

class Usage(ctypes.Structure):
    _fields_ = [('uuid', ctypes.c_uint8 * 16)] + [(f, ctypes.c_uint64) for f in FIELDS]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--pid', type=int, required=True)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--duration', type=float, default=900)
    p.add_argument('--interval', type=float, default=1)
    p.add_argument('--stop-file', type=Path)
    a = p.parse_args()
    if sys.platform != 'darwin' or a.pid <= 0 or a.interval <= 0 or a.duration <= 0:
        p.error('Requires macOS, a positive PID, interval, and duration')
    lib = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
    lib.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
    lib.proc_pid_rusage.restype = ctypes.c_int
    a.out.parent.mkdir(parents=True, exist_ok=True)
    start = time.monotonic()
    identity = None
    with a.out.open('x', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=['elapsed_s','wall_time_s','pid','rss_bytes',
            'footprint_bytes','lifetime_max_footprint_bytes','user_cpu_ns','system_cpu_ns',
            'disk_read_bytes','disk_written_bytes','error'])
        writer.writeheader()
        while time.monotonic() - start <= a.duration:
            if a.stop_file and a.stop_file.exists():
                break
            usage = Usage()
            result = lib.proc_pid_rusage(a.pid, 4, ctypes.byref(usage))
            row = {'elapsed_s':time.monotonic()-start,'wall_time_s':time.time(),'pid':a.pid}
            if result != 0:
                row['error'] = os.strerror(ctypes.get_errno())
                writer.writerow(row); f.flush()
                return 1
            if identity is not None and identity != usage.proc_start_abstime:
                row['error'] = 'PID reused; stopped'
                writer.writerow(row); f.flush()
                return 1
            identity = usage.proc_start_abstime
            row.update(rss_bytes=usage.resident_size, footprint_bytes=usage.phys_footprint,
                lifetime_max_footprint_bytes=usage.lifetime_max_phys_footprint,
                user_cpu_ns=usage.user_time, system_cpu_ns=usage.system_time,
                disk_read_bytes=usage.diskio_bytesread, disk_written_bytes=usage.diskio_byteswritten,
                error='')
            writer.writerow(row); f.flush()
            time.sleep(a.interval)
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
