#!/bin/bash

src_script_dir=/kon-src/script
src_job_dir=/kon-src/nomad/job

target_basedir=/etc/kon
target_script_dir=$target_basedir/script
target_job_dir=$target_basedir/nomad/job

mkdir -p $target_script_dir
mkdir -p $target_job_dir
mkdir -p /opt/bin

cp /kon-src/kon /opt/bin/
cp /kon-src/version $target_basedir
cp /kon-src/kon.sh $target_basedir
cp $src_script_dir/*.txt $target_script_dir/
cp $src_script_dir/*.sh $target_script_dir/
cp $src_job_dir/*.nomad $target_job_dir/

cp /kon-dev/kon.conf $target_basedir/