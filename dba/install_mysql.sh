
#!/bin/bash
# install_mysql ansible
# 1.定义全局初化变量
# 1.1 MySQL二进制包与安装脚本存放目录
source_package_dir=/usr/local/src/
# 1.2 MySQL二进制包全称
mysql_package=$1
# 1.3 操作系统层mysql用户的初始密码
ospassword=wd6r@SF1
# 1.4 MySQL数据库实例超级用户的初始密码
dbuser=admin
dbpassword=Q@XXA8Yj
# 1.5 MySQL实例端口
port=35972
# 1.6 MySQL实例的服务器ID 
server_id=$(date +%s)
# 1.7 并行复制的工作线程数
cpu_num=$(cat /proc/cpuinfo | grep name | cut -f2 -d: | wc -l)
cpu=`expr $cpu_num / 4`
# 1.8 生成清理通用日志和慢日志后台作业的开始执行时间
purge_date=$(date +%Y-%m-%d)" 00:00:00"
# 1.9 获取SSD硬盘RIAD组的虚拟磁盘
ldisk=$(df -h|grep /app|awk '{print $1}'|cut -d '/' -f 3)
pdisk=${ldisk:0:3}

# 2.停止正在运行中的mysql进程
function stop_mysql_service()
{
	mysql_process=$(ps -ef|grep mysql|grep -v grep|wc -l)
  if [ $mysql_process -eq 0 ];then
     echo "MySQL services don't exist."
     exit
  else
     echo "MySQL service already exists."
     service mysql stop
     echo "MySQL service stopped."
  fi
}

# 3.删除操作系统默认安装的老版本mysql数据库
function unload_old_mysql()
{
  old_version_mysql=$(rpm -qa|grep mysql|wc -l)
  if [ $old_version_mysql -eq 0 ];then
     echo "The old version doesn't exist."
  else
     echo "The old version already exists need to remove."
     rpm -e mysql-devel-5.1.73-8.el6_8.x86_64 qt-mysql-4.6.2-28.el6_5.x86_64 mysql-5.1.73-8.el6_8.x86_64 mysql-libs-5.1.73-8.el6_8.x86_64 mysql-server-5.1.73-8.el6_8.x86_64 --nodeps
     echo "The old version has been deleted."
  fi	
}

# 4.删除操作系统层旧的mysql用户与安装部署目录
function purge_old_user_folder()
{
  old_mysql_user=$(cat /etc/passwd|grep mysql|wc -l)
  if [ $old_mysql_user -eq 0 ];then
     echo "The user does not exist."
  else
     echo "User already exists need to remove."
     userdel mysql
     rm -rf /home/mysql
     rm -rf /var/spool/mail/mysql
     rm -rf /app/mysql
     echo "User deleted."
  fi	
}

# 5.创建操作系统层新的mysql用户与安装部署目录
function create_new_user_folder()
{
	groupadd mysql
	useradd mysql -g mysql
	echo mysql:$ospassword | chpasswd
	mkdir -p /app/mysql/{pid,data,conf,log} /app/mysql/log/{binlog,error,general,slow,replay}
	cd /app/mysql
	tar -xzf $source_package_dir$mysql_package
	mv ${mysql_package:0:(${#mysql_package}-7)} dist
}

# 6.create && optimize my.cnf
function create_optimize_mycnf()
{
   touch /app/mysql/conf/my.cnf
   chown -R mysql:mysql /app/mysql
   rm -rf /etc/my.cnf
   ln -s /app/mysql/conf/my.cnf /etc/my.cnf
   cat > /app/mysql/conf/my.cnf <<EOF
   [client]
   socket = /tmp/$port.sock
   port = $port
   
   [mysqld]
   # <General Parameter>
   sql_mode=NO_ENGINE_SUBSTITUTION,STRICT_TRANS_TABLES
   log_bin_trust_function_creators=1
   lower_case_table_names=1
   socket=/tmp/$port.sock
   port=$port
   basedir=/app/mysql/dist
   datadir=/app/mysql/data
   pid-file=/app/mysql/pid/$port.pid
   transaction_isolation=READ-COMMITTED
   event_scheduler=ON
   large_pages=ON
   skip_name_resolve=ON
   open_files_limit=65535
   read_buffer_size=720896
   read_rnd_buffer_size=360448
   sort_buffer_size=720896
   tmp_table_size=64M

   # <character set Parameter>
   character-set-server=utf8mb4
   
   # <Connections & Thread & Network Parameter>
   max_connections=3000
   max_allowed_packet=1024M
   
   # <Innodb Parameter>
   innodb_buffer_pool_size=40G
   innodb_file_per_table=1
   innodb_log_file_size=1000M
   innodb_flush_method=O_DIRECT
   innodb_log_files_in_group=2
   innodb_undo_tablespaces=8
   innodb_undo_log_truncate=1
   innodb_data_file_path=ibdata1:2G:autoextend
   innodb_flush_log_at_trx_commit=1
   innodb_log_buffer_size=8388608
   innodb_log_compressed_pages=OFF
   innodb_sort_buffer_size=1048576
   innodb_spin_wait_delay=30
   innodb_sync_spin_loops=100
   innodb_disable_sort_file_cache=ON
   innodb_open_files=3000

   # <Log Parameter>
   general_log=OFF
   general_log_file=/app/mysql/log/general/sql$port.log
   slow-query-log-file=/app/mysql/log/slow/slow$port.log
   slow_query_log=ON
   long_query_time=1
   log-error=/app/mysql/log/error/err$port.log
   log_output=TABLE
   log_timestamps=SYSTEM
   
   # <Binlog Parameter>
   log-bin = /app/mysql/log/binlog/bin$port-log
   log-bin-index = /app/mysql/log/binlog/bin$port-log.index
   expire_logs_days=3
   sync_binlog=1
   max_binlog_size=500M
   binlog_cache_size=2M
   binlog_order_commits=OFF
   
   # <Replication Parameter>
   server-id=$server_id
   skip_slave_start=1
   master-info-repository=table
   relay-log-info_repository=table
   binlog-format=ROW
   gtid-mode=on
   enforce-gtid-consistency=true
   log-slave-updates=true
   relay-log=/app/mysql/log/replay/replay$port-log
   relay-log-index=/app/mysql/log/replay/replay$port-log.index
   
   # <Parallel Parameter>
   slave_parallel_type=LOGICAL_CLOCK
   slave_parallel_workers=$cpu
   
   [mysql]
   prompt="\\\u@\\\h [\\\d] \\\R:\\\m:\\\s>"
EOF
}

# 7.初始化数据库并添加至系统服务
function initdb_system_service()
{
  /app/mysql/dist/bin/mysqld --initialize-insecure --user=mysql --basedir=/app/mysql/dist --datadir=/app/mysql/data
  cd /app/mysql/dist/support-files
  cp mysql.server /etc/rc.d/init.d/mysql
  chkconfig --add mysql
}


# 8.用户的环境变量配置
function user_environment_variable()
{
cat >> /home/mysql/.bash_profile <<EOF
MYSQL_BASE=/app/mysql export MYSQL_BASE
MYSQL_HOME=\$MYSQL_BASE/dist export MYSQL_HOME
MYSQL_LOG=\$MYSQL_BASE/log export MYSQL_LOG
PATH=\$PATH:\$HOME/bin:\$MYSQL_HOME/bin export PATH
EOF
sed -i '/MYSQL_BASE=/,$d' /root/.bash_profile
cat >> /root/.bash_profile <<EOF
MYSQL_BASE=/app/mysql export MYSQL_BASE
MYSQL_HOME=\$MYSQL_BASE/dist export MYSQL_HOME
MYSQL_LOG=\$MYSQL_BASE/log export MYSQL_LOG
PATH=\$PATH:\$HOME/bin:\$MYSQL_HOME/bin export PATH
EOF
  source /home/mysql/.bash_profile /root/.bash_profile
}

# 9.配置操作系统内核参数
function configuration_kernel()
{
sed -i '/net.ipv4.neigh.default.gc_stale_time = 120/,$d' /etc/sysctl.conf
cat >> /etc/sysctl.conf <<EOF
net.ipv4.neigh.default.gc_stale_time = 120
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.default.arp_announce = 2
net.ipv4.conf.lo.arp_announce = 2
net.ipv4.conf.all.arp_announce = 2
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_max_syn_backlog = 1024
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 1024
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_tw_recycle = 1
net.ipv4.tcp_keepalive_time = 1800
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 30
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
sysctl -p
echo deadline > /sys/block/$pdisk/queue/scheduler
}

# 10.配置mysql实例使用大页
function configuration_hugepages()
{
cat >> /etc/sysctl.conf <<EOF
vm.nr_hugepages = 23000
vm.hugetlb_shm_group = $(cat /etc/group|grep mysql|cut -d ':' -f 3)
EOF
sysctl -p
sed -i '/* soft nofile 65535/,$d' /etc/security/limits.conf
cat >> /etc/security/limits.conf <<EOF
* soft nofile 65535
* hard nofile 65535
mysql soft memlock 47244640256
mysql hard memlock 47244640256
EOF
}

# 11.安装半同步插件、初始化超级用户及密码
function install_plugin()
{
  service mysql start
  mysql -e "install plugin rpl_semi_sync_master soname 'semisync_master.so';install plugin rpl_semi_sync_slave soname 'semisync_slave.so';"
}

# 12.变更审计日志表与慢日志表的存储引擎
function alter_storage_engine()
{
  mysql -e "use mysql;SET GLOBAL slow_query_log=OFF;
  CREATE TABLE slow_log_bak LIKE slow_log;
  ALTER TABLE slow_log_bak ENGINE=INNODB;
  ALTER TABLE slow_log_bak ADD INDEX IDX_SL_01 (start_time);
  ALTER TABLE slow_log RENAME TO slow_log_old;
  ALTER TABLE slow_log_bak RENAME TO slow_log;
  SET GLOBAL slow_query_log=ON;
  CREATE TABLE general_log_bak LIKE general_log;
  ALTER TABLE general_log_bak ENGINE=INNODB;
  ALTER TABLE general_log_bak ADD INDEX IDX_GL_01 (event_time);
  ALTER TABLE general_log RENAME TO general_log_old;
  ALTER TABLE general_log_bak RENAME TO general_log;"
}

# 13.初始化mysql实例的超级用户与密码
function init_user_passwd()
{
 mysql -e "USE mysql;
UPDATE user
SET
  authentication_string = PASSWORD('${dbpassword}'),
  user = '${dbuser}',
  host = '%'
WHERE user = 'root'
  AND host = 'localhost';
FLUSH PRIVILEGES;
SET GLOBAL sql_safe_updates = 1;"
}

# 14.定期清理slow_log记录
function purge_slow_log()
{
  export MYSQL_PWD=Q@XXA8Yj
  mysql -u${dbuser} -e "DELIMITER $$
CREATE PROCEDURE mysql.purge_slow_log ()
BEGIN
  DECLARE v_purge_date DATE;
  SET v_purge_date = SUBDATE(DATE(NOW()), INTERVAL 6 DAY);
  DELETE
  FROM
    mysql.slow_log
  WHERE start_time < v_purge_date;
END $$
DELIMITER $$
CREATE EVENT mysql.purge_slow_log
ON SCHEDULE EVERY 1 DAY STARTS '${purge_date}'
ON COMPLETION PRESERVE ENABLE DO CALL purge_slow_log () $$"
}

# 15.定期清理general_log记录
function purge_general_log()
{
  export MYSQL_PWD=Q@XXA8Yj
  mysql -u${dbuser} -e "DELIMITER $$
CREATE PROCEDURE mysql.purge_general_log ()
BEGIN
  DECLARE v_purge_date DATE;
  SET v_purge_date = SUBDATE(DATE(NOW()), INTERVAL 6 DAY);
  DELETE
  FROM
    mysql.general_log
  WHERE event_time < v_purge_date;
END $$
DELIMITER $$
CREATE EVENT mysql.purge_general_log
ON SCHEDULE EVERY 1 DAY STARTS '${purge_date}'
ON COMPLETION PRESERVE ENABLE DO CALL purge_general_log () $$"
}


# 16.主函数调用执行
function run()
{
 stop_mysql_service
 unload_old_mysql
 purge_old_user_folder
 create_new_user_folder
 create_optimize_mycnf
 initdb_system_service
 user_environment_variable
 configuration_kernel
 configuration_hugepages
 install_plugin
 alter_storage_engine
 init_user_passwd
 purge_slow_log
 purge_general_log
}

run



