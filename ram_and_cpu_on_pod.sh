#!/bin/sh
# pod-metrics.sh — CPU & RAM du conteneur (cgroups v2)

CG=/sys/fs/cgroup

# RAM
MEM_USED=$(cat $CG/memory.current)
MEM_MAX=$(cat $CG/memory.max)
MEM_USED_MB=$(awk "BEGIN{printf \"%.0f\", $MEM_USED/1048576}")
if [ "$MEM_MAX" = "max" ]; then
  MEM_INFO="limite : illimitée"
else
  MEM_MAX_MB=$(awk "BEGIN{printf \"%.0f\", $MEM_MAX/1048576}")
  MEM_PCT=$(awk "BEGIN{printf \"%.1f\", $MEM_USED/$MEM_MAX*100}")
  MEM_INFO="limite : ${MEM_MAX_MB} Mo  (${MEM_PCT}%)"
fi

# CPU
CPU_QUOTA=$(cat $CG/cpu.max)
CPU_PERIOD=$(echo $CPU_QUOTA | awk '{print $2}')
CPU_QUOTA_US=$(echo $CPU_QUOTA | awk '{print $1}')
if [ "$CPU_QUOTA_US" = "max" ]; then
  CPU_ALLOC="illimité"
else
  CPU_ALLOC=$(awk "BEGIN{printf \"%.2f vCPU\", $CPU_QUOTA_US/$CPU_PERIOD}")
fi

T1=$(awk '/usage_usec/{print $2}' $CG/cpu.stat)
sleep 1
T2=$(awk '/usage_usec/{print $2}' $CG/cpu.stat)
CPU_PCT=$(awk "BEGIN{printf \"%.1f\", ($T2-$T1)/10000}")

printf "RAM  : %s Mo  —  %s\n" "$MEM_USED_MB" "$MEM_INFO"
printf "CPU  : %s%%  —  quota : %s\n" "$CPU_PCT" "$CPU_ALLOC"
