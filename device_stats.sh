#!/usr/bin/env bash
set -e

WATCH=0
INTERVAL=2
ADB_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -w|--watch)
      WATCH=1
      if [[ "$2" =~ ^[0-9]+$ ]]; then
        INTERVAL="$2"
        shift
      fi
      shift
      ;;
    -s)
      ADB_ARGS+=("-s" "$2")
      shift 2
      ;;
    *)
      ADB_ARGS+=("$1")
      shift
      ;;
  esac
done

fetch_stats() {
  adb "${ADB_ARGS[@]}" shell top -n 1 -b | awk '
  /Mem:/ {
    for(i=1;i<=NF;i++) {
      if($i~/[0-9]+[kK]/) {
        v = substr($i, 1, length($i)-1)
        if($(i+1)~/total/) tot=v; if($(i+1)~/used/) usd=v; if($(i+1)~/free/) fre=v; if($(i+1)~/buffers/) buf=v
      }
    }
  }
  /Swap:/ {
    for(i=1;i<=NF;i++) {
      if($i~/[0-9]+[kK]/ && $(i+1)~/cached/) cch=substr($i, 1, length($i)-1)
    }
  }
  /%cpu/ {
    for(i=1;i<=NF;i++) {
      if($i~/%idle/) { match($i,/[0-9]+/); idl=substr($i,RSTART,RLENGTH) }
      if($i~/%cpu/)  { match($i,/[0-9]+/); tot_cpu=substr($i,RSTART,RLENGTH) }
    }
  }
  $1 ~ /^[0-9]+$/ {
    pid=$1; res=$6; cpu=$9+0; mem=$10+0;
    cmd=""; for(i=12;i<=NF;i++) cmd=(cmd==""?$i:cmd" "$i)
    if(cmd=="") cmd=$NF

    pids[n] = pid; cpus[n] = cpu; mems[n] = mem; ress[n] = res; cmds[n] = cmd;
    idx_cpu[n] = n; idx_mem[n] = n;
    n++
  }
  END {
    if (tot_cpu > 0) printf "=== SYSTEM RESOURCE USAGE ===\nCPU: %.1f%% used, %.1f%% available\n", ((tot_cpu-idl)/tot_cpu)*100, (idl/tot_cpu)*100
    avail = fre + buf + cch
    if (tot > 0) {
      if (avail > 0) printf "RAM: %.0f MB used, %.0f MB available (total: %.0f MB)\n\n", (tot - avail)/1024, avail/1024, tot/1024
      else printf "RAM: %.0f MB used, %.0f MB available (total: %.0f MB)\n\n", usd/1024, fre/1024, tot/1024
    }

    for(i=0; i<n; i++) {
      for(j=i+1; j<n; j++) {
        if(cpus[idx_cpu[j]] > cpus[idx_cpu[i]]) {
          tmp = idx_cpu[i]; idx_cpu[i] = idx_cpu[j]; idx_cpu[j] = tmp;
        }
        if(mems[idx_mem[j]] > mems[idx_mem[i]]) {
          tmp = idx_mem[i]; idx_mem[i] = idx_mem[j]; idx_mem[j] = tmp;
        }
      }
    }

    printf "TOP 3 PROCESSES BY CPU:\n"
    printf "  %-7s %-7s %-7s %s\n", "PID", "CPU%", "RAM", "COMMAND"
    for(k=0; k<3 && k<n; k++) {
      idx = idx_cpu[k]
      printf "  %-7s %-7.1f %-7s %s\n", pids[idx], cpus[idx], ress[idx], cmds[idx]
    }

    printf "\nTOP 3 PROCESSES BY RAM:\n"
    printf "  %-7s %-7s %-7s %s\n", "PID", "MEM%", "RAM", "COMMAND"
    for(k=0; k<3 && k<n; k++) {
      idx = idx_mem[k]
      printf "  %-7s %-7.1f %-7s %s\n", pids[idx], mems[idx], ress[idx], cmds[idx]
    }
  }'
}

if [ "$WATCH" -eq 1 ]; then
  while true; do
    clear
    fetch_stats
    sleep "$INTERVAL"
  done
else
  fetch_stats
fi
