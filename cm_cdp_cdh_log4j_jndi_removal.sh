#!/bin/bash
# CLOUDERA SCRIPTS FOR LOG4J
#
# (C) Cloudera, Inc. 2021. All rights reserved.
#
# Applicable Open Source License: Apache License 2.0
#
# CLOUDERA PROVIDES THIS CODE TO YOU WITHOUT WARRANTIES OF ANY KIND. CLOUDERA DISCLAIMS ANY AND ALL EXPRESS AND IMPLIED WARRANTIES WITH RESPECT TO THIS CODE, INCLUDING BUT NOT LIMITED TO IMPLIED WARRANTIES OF TITLE, NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. CLOUDERA IS NOT LIABLE TO YOU,  AND WILL NOT DEFEND, INDEMNIFY, NOR HOLD YOU HARMLESS FOR ANY CLAIMS ARISING FROM OR RELATED TO THE CODE. ND WITH RESPECT TO YOUR EXERCISE OF ANY RIGHTS GRANTED TO YOU FOR THE CODE, CLOUDERA IS NOT LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, PUNITIVE OR ONSEQUENTIAL DAMAGES INCLUDING, BUT NOT LIMITED TO, DAMAGES  RELATED TO LOST REVENUE, LOST PROFITS, LOSS OF INCOME, LOSS OF  BUSINESS ADVANTAGE OR UNAVAILABILITY, OR LOSS OR CORRUPTION OF DATA.
#
# --------------------------------------------------------------------------------------

function scan_for_jndi {
  local targetdir=${1:-/opt/cloudera}
  echo "Running on '$targetdir'"

  pattern=JndiLookup.class
  good_pattern=ClassArbiter.class

  for jarfile in $(find -L $targetdir -name "*.jar" -o -name "*.tar"); do
    if [ -L  "$jarfile" ]; then
      continue
    fi
    if grep -q $pattern $jarfile; then
      if grep -q $good_pattern $jarfile; then
        echo "Fixed version of Log4j-core found in '$jarfile'"
      else
        echo "Vulnerable version of Log4j-core found in '$jarfile'"
      fi
    fi
    # Is this jar in jar (uber-jars)?
    if unzip -l $jarfile | grep -v 'Archive:' | grep '\.jar$' >/dev/null; then
      for inner in $(unzip -l $jarfile | grep -v 'Archive:' | grep '\.jar$' | awk '{print $4}'); do
        if unzip -p $jarfile $inner | grep -q JndiLookup.class; then
          echo "Vulnerable version of Log4j-core found in inner '$inner' of '$jarfile'"
        fi
      done
    fi
  done

  for warfile in $(find -L $targetdir -name "*.war" -o -name "*.nar"); do
    if [ -L  "$warfile" ]; then
      continue
    fi
    rm -r -f $tmpdir/unzip_target
    mkdir $tmpdir/unzip_target
    unzip -qq $warfile -d $tmpdir/unzip_target

    found=0  # not found
    for f in $(grep -r -l $pattern $tmpdir/unzip_target); do
      found=1  # found vulnerable class
      if grep -q $good_pattern $f; then
        found=2  # found fixed class
      fi
    done
    if [ $found -eq 2 ]; then
      echo "Fixed version of Log4j-core found in '$warfile'"
    elif [ $found -eq 1 ]; then
      echo "Vulnerable version of Log4j-core found in '$warfile'"
    fi
    rm -r -f $tmpdir/unzip_target
  done

  for tarfile in $(find -L $targetdir -name "*.tar.gz" -o "*.tgz"); do
    if [ -L  "$tarfile" ]; then
      continue
    fi
    if zgrep -q $pattern $tarfile; then
      if zgrep -q $good_pattern $tarfile; then
        echo "Fixed version of Log4j-core found in '$tarfile'"
      else
        echo "Vulnerable version of Log4j-core found in '$tarfile'"
      fi
    fi
  done

  echo "Scan complete"

}


function delete_jndi_from_jar_files {
  local _sha256sum_org
  local _sha256sum_backup
  local targetdir=${1:-/opt/cloudera}
  echo "Running on '$targetdir'"

  local backupdir=${2:-/opt/cloudera/log4shell-backup}
  mkdir -p "$backupdir"
  echo "Backing up files to '$backupdir'"

  for jarfile in $(find -L $targetdir -name "*.jar"); do
    if [ -L  "$jarfile" ]; then
      continue
    fi
    if grep -q JndiLookup.class $jarfile; then
      # Backup file only if backup doesn't already exist
      mkdir -p "$backupdir/$(dirname $jarfile)"
      local targetbackup="$backupdir/$jarfile.backup"
      if [ ! -f "$targetbackup" ]; then
        echo "Backing up to '$targetbackup'"
        cp -f "$jarfile" "$targetbackup"
      else
        echo "Backup file exists: ${targetbackup} - skipping backup"
      fi

      # Check the backup matches the original before altering it
      _sha256sum_org=$(sha256sum ${jarfile} | awk -F' '  '{print $1}')
      _sha256sum_backup=$(sha256sum ${targetbackup} | awk -F' '  '{print $1}')
      if [ "${_sha256sum_org}" = "${_sha256sum_backup}" ] ; then
        # Rip out class
        echo "Deleting JndiLookup.class from '$jarfile'"
        zip -q -d "$jarfile" */JndiLookup.class
      else
        echo "Backup of file ${jarfile} doesn't match ${targetbackup}"
        echo "NOT removing JndiLookup.class from ${jarfile}"
        exit 1
      fi
    fi

    # Is this jar in jar (uber-jars)?
    if unzip -l $jarfile | grep -v 'Archive:' | grep '\.jar$' >/dev/null; then
      for inner in $(unzip -l $jarfile | grep -v 'Archive:' | grep '\.jar$' | awk '{print $4}'); do
        if unzip -p $jarfile $inner | grep -q JndiLookup.class; then

          # Backup file only if backup doesn't already exist
          mkdir -p "$backupdir/$(dirname $jarfile)"
          local targetbackup="$backupdir/$jarfile.backup"
          if [ ! -f "$targetbackup" ]; then
            echo "Backing up to '$targetbackup'"
            cp -f "$jarfile" "$targetbackup"
          else
            echo "Backup file exists: ${targetbackup} - skipping backup"
          fi

          TMP_DIR=$(mktemp -d)
          pushd $TMP_DIR
          unzip -q $jarfile $inner
          echo "Deleting JndiLookup.class in nested jar $inner of $jarfile"
          zip -q -d $inner \*/JndiLookup.class
          zip -qur $jarfile .
          popd
          rm -rf $TMP_DIR
        fi
      done
    fi
  done

  echo "Completed removing JNDI from jar files"

  for narfile in $(find -L $targetdir -name "*.nar"); do
    if [ -L  "$narfile" ]; then
      continue
    fi
    doZip=0

    rm -r -f $tmpdir/unzip_target
    mkdir $tmpdir/unzip_target
    unzip -qq $narfile -d $tmpdir/unzip_target
    for jarfile in $(find -L $tmpdir/unzip_target -name "*.jar"); do
      if [ -L  "$jarfile" ]; then
        continue
      fi
      if grep -q JndiLookup.class $jarfile; then

        # Backup file only if backup doesn't already exist
        mkdir -p "$backupdir/$(dirname $jarfile)"
        targetbackup="$backupdir/$jarfile.backup"
        if [ ! -f "$targetbackup" ]; then
          echo "Backing up to '$targetbackup'"
          cp -f "$jarfile" "$targetbackup"
        fi

        # Rip out class
        echo "Deleting JndiLookup.class from '$jarfile'"
        zip -q -d "$jarfile" \*/JndiLookup.class
        doZip=1
      fi
    done

    if [ 1 -eq $doZip ]; then
      echo "Updating '$narfile'"
      pushd $tmpdir/unzip_target
      zip -r -q $narfile .
      popd
    fi

    rm -r -f $tmpdir/unzip_target
  done

  echo "Completed removing JNDI from nar files"


}

function delete_jndi_from_targz_file {

  tarfile=$1
  if [ ! -f "$tarfile" ]; then
    echo "Tar file '$tarfile' not found"
    exit 1
  fi

  local backupdir=${2:-/opt/cloudera/log4shell-backup}
  mkdir -p "$backupdir/$(dirname $tarfile)"
  targetbackup="$backupdir/$tarfile.backup"
  if [ ! -f "$targetbackup" ]; then
    echo "Backing up to '$targetbackup'"
    cp -f "$tarfile" "$targetbackup"
  else
     echo "Backup file exists: ${targetbackup} - skipping backup"
  fi

  echo "Patching '$tarfile'"
  tempfile=$(mktemp)
  tempdir=$(mktemp -d)
  tempbackupdir=$(mktemp -d)

  tar xf "$tarfile" -C "$tempdir"
  delete_jndi_from_jar_files "$tempdir" "$tempbackupdir"

  echo "Recompressing"
  (cd "$tempdir" && tar czf "$tempfile" --owner=1000 --group=100 .)

  # Restore old permissions before replacing original
  chown --reference="$tarfile" "$tempfile"
  chmod --reference="$tarfile" "$tempfile"

  mv "$tempfile" "$tarfile"

  rm -f $tempfile
  rm -rf $tempdir
  rm -rf $tempbackupdir

  echo "Completed removing JNDI from $tarfile"

}

function delete_jndi_from_hdfs {

  mr_hdfs_path="/user/yarn/mapreduce/mr-framework/"
  tez_hdfs_path="/user/tez/*"
  issecure="true"

  if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
        echo "Invalid arguments. Please choose 'mr' or 'tez' along with optional tar ball path."
    exit 1
  fi

  file_type=$1
  external_hdfs_path=${2:-""}

  if [ $file_type ==  "tez" ]; then
    if [ -z "$external_hdfs_path" ]; then
      external_hdfs_path=$tez_hdfs_path
    fi
    hdfs_path=$external_hdfs_path
  elif [ $file_type == "mr" ]; then
    if [ -z "$external_hdfs_path" ]; then
      external_hdfs_path=$mr_hdfs_path
    fi
    hdfs_path=$external_hdfs_path
  else
    echo "Invalid arguments. Please choose 'mr' or 'tez' along with optional tar ball path."
    exit 1
  fi

  user_option=""
  keytab_file="hdfs.keytab"
  keytab=$(find /var/run/cloudera-scm-agent/process/ -type f -iname $keytab_file | grep -e NAMENODE -e DATANODE | tail -1)
  if [[ -z "$keytab" || ! -s $keytab ]]; then
    echo "Keytab file is not found or is empty: $keytab_file. Considering this as a non-secure cluster deployment."
    issecure="false"
    user_option="sudo -u hdfs"
  fi

  if [ $issecure == "true" ]; then
    echo "Using $keytab to access HDFS"

    principal=$(klist -kt $keytab | grep -v HTTP | tail -1 | awk '{print $4}')
    if [ -z "$principal" ]; then
      echo "principal not found: $principal"
      exit 0
    fi
    kinit -kt $keytab $principal
  fi

  # In case two or more namenode host cleanups are running at exactly the same time, stagger the
  # probe of the HDFS marker.
  sleep $((1 + $RANDOM % 20))
  hdfs dfs -test -e $hdfs_path
  ret_status=$?
  if [ $ret_status -eq 1 ]; then
    echo "Tar ball is not available in $hdfs_path. $file_type is not installed."
    return
  fi

  hdfs_file_path=$(hdfs dfs -ls $hdfs_path | tail -1  | awk '{print $8}')

  if [[ ! $hdfs_file_path == *.tar.gz ]]; then
    echo "Desired tar ball path was not found in HDFS. Exiting."
    exit 0
  fi

  hdfs_lock_path="/user/upgrade-lock_${file_type}"
  hdfs dfs -test -e $hdfs_lock_path
  ret_status=$?
  if [ $ret_status -eq 1 ]; then
    $user_option hdfs dfs -touch $hdfs_lock_path
  else
    echo "Tar ball for $file_type in HDFS is already upgraded."
    return 0
  fi

  permissions=$(hdfs dfs -stat "%a" $hdfs_file_path)
  if [ -z $permissions ]; then
    echo "Unable to fetch permissions for $hdfs_file_path . Exiting"
    exit 1
  fi

  user_group=$(hdfs dfs -stat "%u:%g" $hdfs_file_path)
  if [ -z $user_group ]; then
    echo "Unable to fetch user and group for $hdfs_file_path . Exiting"
    exit 1
  fi

  current_time=$(date "+%Y.%m.%d-%H.%M.%S")
  echo "Current Time : $current_time"

  local_path="$tmpdir/hdfs_tar_files.${current_time}"
  mkdir -p $local_path

  echo "Downloading tar ball from HDFS path $hdfs_file_path to $local_path"
  echo "Printing current HDFS file stats"
  hdfs dfs -ls $hdfs_file_path
  hdfs dfs -get -f $hdfs_file_path $local_path

  hdfs_bc_path="$tmpdir/backup.${current_time}"

  echo "Taking a backup of HDFS dir $hdfs_file_path to $hdfs_bc_path"
  $user_option hdfs dfs -mkdir -p $hdfs_bc_path
  $user_option hdfs dfs -cp -f  $hdfs_file_path $hdfs_bc_path

  out="$(basename $local_path/*)"
  local_full_path="${local_path}/${out}"

  echo "Executing the log4j removal script"
  delete_jndi_from_targz_file $local_full_path

  echo "Completed executing log4j removal script and uploading $out to $hdfs_file_path"
  $user_option hdfs dfs -copyFromLocal -f $local_full_path $hdfs_file_path
  $user_option hdfs dfs -chown $user_group $hdfs_file_path
  $user_option hdfs dfs -chmod $permissions $hdfs_file_path

  echo "Printing updated HDFS file stats"
  hdfs dfs -ls $hdfs_file_path

  if [ $issecure == "true" ]; then
    which kdestroy && kdestroy
  fi


}

function usage() {
cat << EOF
Search for and remove instances of the log4j security hole within Cloudera artifacts.
OPTIONAL PARAMETERS
target directory: The installed path of Cloudera software, default=/opt/cloudera
backupdir: Where the original jar and tar.gz files will be saved, default /opt/cloudera/log4shell-backup
EOF
}



targetdir=${1:-/opt/cloudera}
backupdir=${2:-/opt/cloudera/log4shell-backup}
tmpdir=${TMPDIR:-/tmp} 
mkdir -p $tmpdir
echo "Using tmp directory '$tmpdir'"

if ! command -v unzip &> /dev/null; then
  echo "unzip not found. unzip is required to run this script."
  exit 1
fi

if ! command -v zgrep &> /dev/null; then
  echo "zgrep not found. zgrep is required to run this script."
  exit 1
fi

if ! command -v zip &> /dev/null; then
  echo "zip not found. zip is required to run this script."
  exit 1
fi

if ! command -v sha256sum &> /dev/null; then
  echo "sha256sum not found. sha256sum is required to run this script."
  exit 1
fi

if [ -z "$SKIP_JAR" ]; then
  echo "Removing JNDI from jar files"
  delete_jndi_from_jar_files $targetdir $backupdir
else
  echo "Skipped patching .jar"
fi

if [ -z "$SKIP_TGZ" ]; then
  echo "Removing JNDI from tar.gz files"
  for targzfile in $(find -L $targetdir -name '*.tar.gz') ; do
    delete_jndi_from_targz_file $targzfile $backupdir
  done
else
  echo "Skipped patching .tar.gz"
fi

if [ -z "$SKIP_HDFS" ]; then
  if ps -efww | grep org.apache.hadoop.hdfs.server.namenode.NameNode | grep -v grep  1>/dev/null 2>&1; then
    echo "Found an HDFS namenode on this host, removing JNDI from HDFS tar.gz files"
    delete_jndi_from_hdfs tez
    delete_jndi_from_hdfs mr
  fi
else
  echo "Skipped patching .tar.gz in HDFS"
fi

if [ -n "$RUN_SCAN" ]; then
  echo "Running scan for missed JndiLookup classes. This may take a while."
  scan_for_jndi $targetdir
fi
