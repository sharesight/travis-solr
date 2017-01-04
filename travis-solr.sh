#!/usr/bin/env bash

SOLR_PORT=${SOLR_PORT:-8983}
SOLR_VERSION=${SOLR_VERSION:-4.9.1}
DEBUG=${DEBUG:-false}
SOLR_CORE=${SOLR_CORE:-core0}
# Since Solr 5.x
SOLR_COLLECTION=${SOLR_COLLECTION:-gettingstarted}
RUN_ONLY=${RUN_ONLY:-false}

download() {
    FILE="$2.tgz"
    if [ -f $FILE ];
    then
       echo "File $FILE exists."
       tar -zxf $FILE
    else
       echo "File $FILE does not exist. Downloading solr from $1..."
       curl -O $1
       # echo "-----------------------"
       # cat $FILE
       # echo "-----------------------"
       tar -zxf $FILE
    fi
    echo "Downloaded!"
}

is_solr_up(){
    echo "Checking if solr is up on http://localhost:$SOLR_PORT/solr/admin/cores"
    http_code=`echo $(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$SOLR_PORT/solr/admin/cores")`
    return `test $http_code = "200"`
}

wait_for_solr(){
    counter=1
    while ! is_solr_up; do
        if [ "$counter" -gt 50 ]
        then
          echo "Waited $counter times for Solr; won't wait any longer"
          exit 1
        fi
        sleep 3
        counter=$((counter + 1))
    done
}

run() {
    dir_name=$1
    solr_port=$2
    solr_core=$3
    # Run solr
    echo "Running with folder $dir_name"
    echo "Starting solr on port ${solr_port}..."

    # go to the solr folder
    cd $1/example

    if [ "$DEBUG" = "true" ]
    then
        java -Djetty.port=$solr_port -Dsolr.solr.home=multicore -jar start.jar &
    else
        java -Djetty.port=$solr_port -Dsolr.solr.home=multicore -jar start.jar > /dev/null 2>&1 &
    fi
    wait_for_solr
    cd ../../
    echo "Started"
}

run_solr5_example() {
    dir_name=$1
    solr_port=$2
    ./$dir_name/bin/solr -p $solr_port -c -e schemaless
    echo "Started"
}

run_solr5() {
    dir_name=$1
    solr_port=$2
    if [ "$3" = true ] ; then
        echo "Starting in $dir_name without core create"
        ./$dir_name/bin/solr -p $solr_port
    else
        ./$dir_name/bin/solr -p $solr_port -c
    fi
    echo "Started"
}

download_using_cache() {
    cache_url = ''
    case $1 in
     3.*|4.0.0)
         apache_url="http://archive.apache.org/dist/lucene/solr/4.0.0/apache-solr-4.0.0.tgz"
         ;;
     4.*)
         apache_url="http://archive.apache.org/dist/lucene/solr/${SOLR_VERSION}/solr-${SOLR_VERSION}.tgz"
         cache_url="http://sharesight-build-cache.s3-website-us-east-1.amazonaws.com/solr-${SOLR_VERSION}.tgz"
         ;;
     5.*|6.*)
         apache_url="http://archive.apache.org/dist/lucene/solr/${SOLR_VERSION}/solr-${SOLR_VERSION}.tgz"
         cache_url="http://sharesight-build-cache.s3-website-us-east-1.amazonaws.com/solr-${SOLR_VERSION}.tgz"
         ;;
     *)
        echo "Sorry, $1 is not supported or not valid SOLR_VERSION."
        exit 1
    esac

    if [[ $cache_url -ne '' ]]; then
        http_code=`echo $(curl -I -w "%{http_code}" -o /dev/null $cache_url)`
        if [[ $http_code -eq '200' ]]; then
          echo "Downloading from cache $cache_url"
          download $cache_url $dir_name
          return
        fi
    fi

    echo "No cache, downloading from apache $apache_url"
    download $apache_url $dir_name
}

download_and_run() {
    download_using_cache

    case $1 in
     3.*)
         dir_name="apache-solr-${SOLR_VERSION}"
         dir_conf="conf/"
         ;;
     4.0.0)
         dir_name="apache-solr-4.0.0"
         dir_conf="collection1/conf/"
         ;;
     4.*|5.*|6.*)
         dir_name="solr-${SOLR_VERSION}"
         dir_conf="collection1/conf/"
         ;;
     *)
        echo "Sorry, $SOLR_VERSION is not supported or not valid version."
        exit 1
    esac

    if [[ $SOLR5_COLLECTIONS && ($SOLR_VERSION == 5* || $SOLR_VERSION == 6*) ]]
    then
        if [ -z "${SOLR_COLLECTION_CONF}" ]
        then
            run_solr5_example $dir_name $SOLR_PORT
        else
            run_solr5 $dir_name $SOLR_PORT
            create_collection $dir_name $SOLR_COLLECTION $SOLR_COLLECTION_CONF $SOLR_PORT
        fi
        if [ -z "${SOLR_DOCS}" ]
        then
            echo "SOLR_DOCS not defined, skipping initial indexing"
        else
            post_documents_solr5 $dir_name $SOLR_COLLECTION $SOLR_DOCS $SOLR_PORT
        fi
    else
        echo 'Solr config, wd='; pwd
        add_core $dir_name $dir_conf $SOLR_CORE "$SOLR_CONFS"
        du -a $dir_name

        if [[ $SOLR_VERSION == 5* || $SOLR_VERSION == 6* ]]
        then
            run_solr5 $dir_name $SOLR_PORT true
        else
            run $dir_name $SOLR_PORT $SOLR_CORE
        fi

        sleep 5

        # Test solr core
        response=$(curl --write-out %{http_code} 'http://localhost:'$SOLR_PORT'/solr/'$SOLR_CORE'/admin/ping' --output /dev/null)
        if [[ $response -ne '200' ]]; then
          echo "Ping failed, err "$response
        fi
        echo "Ping core $SOLR_CORE on port $SOLR_PORT was happy"

        cat $dir_name/server/logs/solr.log

        if [ -z "${SOLR_DOCS}" ]
        then
            echo "SOLR_DOCS not defined, skipping initial indexing"
        else
            post_documents $dir_name $SOLR_DOCS $SOLR_CORE $SOLR_PORT
        fi
#    fi
}

add_core() {
    dir_name=$1
    dir_conf=$2
    solr_core=$3
    solr_confs=$4
    echo "Add core: dir_name=$dir_name, dir_conf=$dir_conf, solr_core=$solr_core, solr_confs=$solr_confs"

    # prepare our folders
    [[ -d "${dir_name}/server/solr/${solr_core}" ]] || mkdir $dir_name/server/solr/$solr_core
    [[ -d "${dir_name}/server/solr/${solr_core}/conf" ]] || mkdir $dir_name/server/solr/$solr_core/conf

    if [[ $SOLR_VERSION == 5* || $SOLR_VERSION == 6* ]]; then
    touch $dir_name/server/solr/$solr_core/core.properties
    fi

    # And make a data dir
    mkdir -p $dir_name/server/solr/$solr_core/data

    # copies custom configurations
    if [ -d "${solr_confs}" ] ; then
      cp -R -v $solr_confs/* $dir_name/server/solr/$solr_core/conf/
      echo "Copied $solr_confs/* to solr conf directory: $dir_name/server/solr/$solr_core/conf/"
    else
      for file in $solr_confs
      do
        echo "Process conf file $file"
        if [ -f "${file}" ]; then
            cp $file $dir_name/server/solr/$solr_core/conf
            echo "Copied $file into solr conf directory."
        else
            echo "${file} is not valid";
            exit 1
        fi
      done
    fi

    # enable custom core
    if [ "$solr_core" != "core0" -a "$solr_core" != "core1" ] ; then
        echo "Adding $solr_core to solr.xml"
        sed -i -e "s/<\/cores>/<core name=\"$solr_core\" instanceDir=\"$solr_core\" \/><\/cores>/" $dir_name/server/solr/solr.xml
    fi
}

post_documents() {
    dir_name=$1
    solr_docs=$2
    solr_core=$3
    solr_port=$4
      # Post documents
    if [ -z "${solr_docs}" ]
    then
        echo "SOLR_DOCS not defined, skipping initial indexing"
    else
        echo "Indexing $solr_docs"
        java -Dtype=application/json -Durl=http://localhost:$solr_port/solr/$solr_core/update/json -jar $dir_name/example/exampledocs/post.jar $solr_docs
    fi
}

create_collection() {
    dir_name=$1
    name=$2
    dir_conf=$3
    solr_port=$4
    ./$dir_name/bin/solr create -c $name -d $dir_conf -shards 1 -replicationFactor 1 -p $solr_port
    echo "Created collection $name"
}

post_documents_solr5() {
    dir_name=$1
    collection=$2
    solr_docs=$3
    solr_port=$4
     # Post documents
    if [ -z "${solr_docs}" ]
    then
        echo "SOLR_DOCS not defined, skipping initial indexing"
    else
        echo "Indexing $solr_docs"
        echo "./$dir_name/bin/post -c $collection $solr_docs -p$solr_port"
        ./$dir_name/bin/post -c $collection $solr_docs -p $solr_port
    fi
}

download_and_run
