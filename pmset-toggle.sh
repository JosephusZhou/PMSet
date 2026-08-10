#!/bin/bash

CONFIG_DIR="${HOME}/.pmset-backup"
BACKUP_FILE="${CONFIG_DIR}/pmset-backup.txt"
KEYS="disablesleep sleep standby autopoweroff hibernatemode tcpkeepalive womp displaysleep disksleep"

backup() {
  mkdir -p "$CONFIG_DIR"
  : > "$BACKUP_FILE"
  for key in $KEYS; do
    val=$(pmset -g | awk -v k="$key" '$1==k {print $2; exit}')
    if [ -n "$val" ]; then
      echo "$key $val" >> "$BACKUP_FILE"
    fi
  done
  echo "已备份当前 pmset 配置 -> $BACKUP_FILE"
  cat "$BACKUP_FILE"
}

restore() {
  if [ ! -f "$BACKUP_FILE" ]; then
    echo "没有找到备份文件: $BACKUP_FILE"
    return 1
  fi
  while read -r key val; do
    [ -z "$key" ] && continue
    echo "sudo pmset -a $key $val"
    sudo pmset -a "$key" "$val"
  done < "$BACKUP_FILE"
  echo "已恢复备份配置"
}

lid_no_sleep() {
  sudo pmset -a disablesleep 1 sleep 0 standby 0 autopoweroff 0 hibernatemode 0 displaysleep 0 disksleep 0
  sudo pmset tcpkeepalive 1
  sudo pmset womp 1
  echo "已设置：合盖不睡眠（插电使用，注意发热）"
}

lid_sleep() {
  sudo pmset -a disablesleep 0 sleep 1 standby 1 autopoweroff 1 hibernatemode 3
  echo "已设置：合盖正常睡眠"
}

menu() {
  while true; do
    echo ""
    echo "===== pmset 管理菜单 ====="
    echo "1) 备份当前 pmset 配置"
    echo "2) 恢复备份配置"
    echo "3) 设置合盖不睡眠"
    echo "4) 设置合盖睡眠"
    echo "q) 退出"
    echo "========================"
    read -r -p "请输入数字: " choice
    case $choice in
      1) backup ;;
      2) restore ;;
      3) lid_no_sleep ;;
      4) lid_sleep ;;
      q|Q) echo "再见"; break ;;
      *) echo "无效输入，请输入 1-4 或 q" ;;
    esac
  done
}

menu
