#!/bin/bash

set -e

# mongoexport --port=6002 -d suizhou -c col_user -o col_user.dat
# mongoimport --port 6002 -d test -c col_robot col_user.dat

# mongoimport -d test -c students --type csv --headerline --file students_csv.dat

# mongodump --collection COLLECTION --db DB_NAME
# mongorestore -h dbhost -d dbname --directoryperdb dbdirectory

usage() {
    echo " ./ctrl cmd "
    echo " cmd : mongodb (start|stop) "
    echo " cmd : mongo-console "
    echo " cmd : mongodump 备份整个数据库"
    echo " cmd : mongorestore (DBNAME PATH) 恢复指定位置备份"
    echo " cmd : coldump 备份bson格式集合"
    echo " cmd : colimport (DBNAME PATH) 导入bson格式集合 "
}

# server conf
workDir=$(cd `dirname $0`; pwd)

cd $workDir

# mongodb conf
db_host=127.0.0.1:27017
db_name=suizhou
collections_array=(col_user col_id_gen)
remote_host=127.0.0.1
remote_addr=/home/database/backup/
db_conf=mongodb.conf
db_path=~/data/mgo
db_data=${db_path}/data
db_logpath=${db_path}/mongodb.log
db_pidfile=${db_path}/mongodb.pid

MONGODB_DIR="/usr/local/Cellar/mongodb/3.4.4/bin"
BACKUP_DIR="${db_path}/backup"
TAR="/usr/bin/tar"

get_curr_last_month() {
    #echo `date -d last-month +"%Y-%m-%d"`
    echo `date +"%Y-%m-%d"`
}

get_curr_day() {
    echo `date +"%Y-%m-%d"`
}

get_curr_time() {
    echo `date +"%Y-%m-%d %H:%M:%S"`
}

get_curr_time_str() {
    echo `date +"%Y%m%d%H%M%S"`
}

MONGO="${MONGODB_DIR}/mongo"
MONGOD="${MONGODB_DIR}/mongod"
BSONDUMP="${MONGODB_DIR}/bsondump"
MONGODUMP="${MONGODB_DIR}/mongodump"
MONGORESTORE="${MONGODB_DIR}/mongorestore"
MONGOEXPORT="${MONGODB_DIR}/mongoexport"
MONGOIMPORT="${MONGODB_DIR}/mongoimport"
LOGFILE="${BACKUP_DIR}/backup_database.log"

CURRDAY=`get_curr_day`
CURRDAY_LASTMONTH=`get_curr_last_month`
BACKUPPARENTDIR="${BACKUP_DIR}/${db_name}"

BACKUPDIR="${BACKUPPARENTDIR}/${CURRDAY}"
BACKUPFILENAME="${BACKUPPARENTDIR}/${db_name}_${CURRDAY}.tar.gz"

BACKUPDIR_LASTMONTH="${BACKUPPARENTDIR}/${CURRDAY_LASTMONTH}"
BACKUPFILENAME_LASTMONTH="${BACKUPPARENTDIR}/${db_name}_${CURRDAY_LASTMONTH}.tar.gz"

CURR_TIME_STR=`get_curr_time_str`
BACKUPDIR_STR="${BACKUPPARENTDIR}/${CURR_TIME_STR}"
BACKUPFILENAME_STR="${BACKUPPARENTDIR}/${db_name}_${CURR_TIME_STR}.tar.gz"

save_log() {
    echo "" >> ${LOGFILE}
    echo "Time: "`get_curr_time`"   $1 " >> ${LOGFILE}
}

# test mysql connection
mysql_conn() {
    mysql --host=127.0.0.1 --port=8081 -uroot -p`cat ~/.mysql` -e "show databases;"
}

# mongodb – this script starts and stops the mongodb daemon
# chkconfig: - 85 15
# description: MongoDB is a non-relational database storage system.
# processname: mongodb
mongodb_() {
    test -x $DAEMON || exit 0
    #set -e
    case "$1" in
        start)
            echo -n "Starting MongoDB... "
            ${MONGOD} -f ${db_conf}
            ;;
        stop)
            echo -n "Stopping MongoDB... "
            # pid=`ps -o pid,command ax | grep mongod | awk '!/awk/ && !/grep/ {print $1}'`;
            pid=`ps aux | grep mongod | awk '!/awk/ && !/grep/ {print $2}'`;
            if [ "${pid}" != "" ]; then
                kill -2 ${pid};
            fi
            ;;
        *)
            echo "Usage: ./mongodb {start|stop}" >&2
            exit 1
            ;;
    esac
    exit 0
}

remote_backup_sync() {
    if [ ! -e "${1}" ]
    then
        echo "${1} file not exist! "
        exit 1
    fi
    echo "${1} sync to ${remote_host}"
    save_log "${1} sync to ${remote_host}"
    scp $1 root@${remote_host}:${remote_addr}
    save_log "${1} sync done"
}

mongorestore_() {
    name=$1
    if [ "${name}" == "" ]
    then
        echo "${$name} db not exist! "
        exit 1
    fi
    path=$2
    # 目录或文件已经存在，则程序退出
    if [ ! -d "${path}" ]
    then
        echo "${path} directory not exist! "
        exit 1
    fi
    echo "Start restore ${path} to db ${name}! "
    save_log "Start restore ${path} to db ${name}! "
    ${MONGORESTORE} -h ${db_host} -d ${name} ${path}
    save_log "RESTORE DATABASE ${name} SUCCEED"
}

mongodump_() {
    # 目录或文件已经存在，则程序退出
    if [ -d "${BACKUPDIR}" ]
    then
        echo "${BACKUPDIR} directory had exist! "
        exit 1
    fi
    if [ -e "${BACKUPFILENAME}" ]
    then
        echo "${BACKUPFILENAME} file had exist! "
        exit 1
    fi

    if [ -d "${BACKUPDIR_LASTMONTH}" ]
    then
        echo "${BACKUPDIR_LASTMONTH} directory had exist! "
        #rm -rf ${BACKUPDIR_LASTMONTH}
        save_log "${BACKUPDIR_LASTMONTH} directory already remove! "
    fi

    if [ -e "${BACKUPFILENAME_LASTMONTH}" ]
    then
        echo "${BACKUPFILENAME_LASTMONTH} file had exist! "
        #rm -rf ${BACKUPFILENAME_LASTMONTH}
        save_log "${BACKUPFILENAME_LASTMONTH} file already remove! "
    fi

    mkdir -p ${BACKUPDIR}

    echo "Start dump ${db_name} all data to DIR ${BACKUPDIR}"
    save_log "Start dump ${db_name} all data to DIR ${BACKUPDIR}"
    cd ${BACKUPPARENTDIR}
    ${MONGODUMP} --host=${db_host} -d ${db_name} -o ${BACKUPDIR}
    echo "Start compress to ${BACKUPFILENAME}"
    save_log "Start compress to ${BACKUPFILENAME}"
    cd ${BACKUPPARENTDIR}
    ${TAR} cvf ${BACKUPFILENAME} ${CURRDAY}

    save_log "BACKUP DATABASE ${db_name} SUCCEED"

    # remote_backup_sync ${BACKUPFILENAME}
}

collections_import_by_json() {
    name=$1
    if [ "${name}" == "" ]
    then
        echo "${$name} db not exist! "
        exit 1
    fi
    path=$2
    # 目录或文件已经存在，则程序退出
    if [ ! -d "${path}" ]
    then
        echo "${path} directory not exist! "
        exit 1
    fi

    for col in ${collections_array[@]};
    do
        file=${path}/${col}.json
        if [ ! -e "${file}" ]
        then
            echo "${file} file not exist! "
            exit 1
        fi
        echo "Start import collection ${file} to db ${name}! "
        save_log "Start import collection ${file} to db ${name}! "
        ${MONGOIMPORT} -h ${db_host} -d ${name} -c ${col} --type json --file ${file}
    done

    save_log "RESTORE DATABASE ${name} SUCCEED"
}

collections_dump_to_json() {
    # 目录或文件已经存在，则程序退出
    if [ -d "${BACKUPDIR_STR}" ]
    then
        echo "${BACKUPDIR_STR} directory had exist! "
        exit 1
    fi
    if [ -e "${BACKUPFILENAME_STR}" ]
    then
        echo "${BACKUPFILENAME_STR} file had exist! "
        exit 1
    fi

    mkdir -p ${BACKUPDIR_STR}

    cd ${BACKUPPARENTDIR}
    for col in ${collections_array[@]};
    do
        echo "Start dump collection ${col} to DIR ${BACKUPDIR_STR}"
        save_log "Start dump collection ${col} to DIR ${BACKUPDIR_STR}"
        ${MONGODUMP} --host=${db_host} -d ${db_name} --collection ${col} -o ${BACKUPDIR_STR}
        echo "bson to json ${col} to DIR ${BACKUPDIR_STR}"
        save_log "bson to json ${col} to DIR ${BACKUPDIR_STR}"
        ${BSONDUMP} --outFile ${BACKUPDIR_STR}/${db_name}/${col}.json ${BACKUPDIR_STR}/${db_name}/${col}.bson
    done

    echo "Start compress to ${BACKUPFILENAME_STR}"
    save_log "Start compress to ${BACKUPFILENAME_STR}"
    cd ${BACKUPPARENTDIR}
    ${TAR} cvf ${BACKUPFILENAME_STR} ${CURR_TIME_STR}

    save_log "BACKUP DATABASE ${db_name} SUCCEED"

    # remote_backup_sync ${BACKUPFILENAME_STR}
}

mongo_console() {
    ${MONGO} --host=${db_host}
}

case $1 in
    mongodb)
        mongodb_ $2;;
    mongodump)
        mongodump_;;
    mongorestore)
        mongorestore_ $2 $3;;
    coldump)
        collections_dump_to_json;;
    colimport)
        collections_import_by_json $2 $3;;
    mongo-console)
        mongo_console;;
    mysql)
        mysql_conn;;
    *)
        usage;;
esac
