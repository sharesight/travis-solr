#!/usr/bin/env bash

is_solr_up(){
    # echo "Checking if solr is up on http://localhost:$SOLR_PORT/solr/admin/cores"
    # http_code=`echo $(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$SOLR_PORT/solr/admin/cores")`
    # return `test $http_code = "200"`
    return `cat unknown`
}

wait_for_solr(){
  counter=1
  while ! is_solr_up; do
    echo "counter = $counter"
    if [ "$counter" -gt 50 ]
    then
      echo "Waited $counter times for Solr; won't wait any longer"
      exit 1
    fi
    sleep 3
    counter=$((counter + 1))
  done
}

wait_for_solr