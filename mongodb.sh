#!/bin/bash

#mongoexport --port=6002 -d suizhou -c col_user -o col_user.dat
#mongoimport --port 6002 -d test -c col_robot col_user.dat

usage() {
    echo " ./ctrl cmd "
    echo " cmd : mongodb (start|stop) "
    echo " cmd : mongorestore (DBNAME PATH) "
    echo " cmd : mongo-console, mongodump "
}

# server conf
workDir=$(cd `dirname $0`; pwd)

cd $workDir

# mongodb conf
db_host=127.0.0.1:27017
db_name=suizhou
db_conf=mongodb.conf
db_path=~/data/mgo
db_data=${db_path}/data
db_logpath=${db_path}/mongodb.log
db_pidfile=${db_path}/mongodb.pid

MONGODB_DIR="/usr/local/Cellar/mongodb/3.4.4/bin"
BACKUP_DIR="${db_path}/backup"
TAR="/bin/tar"

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

MONGO="${MONGODB_DIR}/mongo"
MONGOD="${MONGODB_DIR}/mongod"
MONGODUMP="${MONGODB_DIR}/mongodump"
MONGORESTORE="${MONGODB_DIR}/mongorestore"
LOGFILE="${BACKUP_DIR}/backup_database.log"

CURRDAY=`get_curr_day`
CURRDAY_LASTMONTH=`get_curr_last_month`
BACKUPPARENTDIR="${BACKUP_DIR}/${db_name}"
BACKUPDIR="${BACKUPPARENTDIR}/${CURRDAY}"
BACKUPFILENAME="${BACKUPPARENTDIR}/${db_name}_${CURRDAY}.tar.gz"
BACKUPDIR_LASTMONTH="${BACKUPPARENTDIR}/${CURRDAY_LASTMONTH}"
BACKUPFILENAME_LASTMONTH="${BACKUPPARENTDIR}/${db_name}_${CURRDAY_LASTMONTH}.tar.gz"

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
    set -e
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
    mongo-console)
        mongo_console;;
    mysql)
        mysql_conn;;
    *)
        usage;;
esac
